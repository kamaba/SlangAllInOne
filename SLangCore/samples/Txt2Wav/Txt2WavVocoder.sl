import Tensora

import Math;

import Std

# =============================================================
# Txt2WavVocoder.sl —— 声码器（谱合成 + Griffin-Lim 相位重构）
#
# 仿 Tacotron 1 的 mel→wav 环节，但把 Griffin-Lim 换到线性谱域：
#   帧级声学参数 → 目标幅度谱（谐波梳齿 × 共振峰包络，源-滤波模型）
#   → 初始线性相位 → ISTFT（矩阵乘）→ Griffin-Lim 迭代打磨相位
#
# 设备自适应：全部重活（matmul / exp / sqrt / div / softmax）走 Tensora，
# 张量上 GPU 即 CUDA kernel，CPU 即标量循环——同一份代码两条路径。
# STFT 分析基 / ISTFT 合成基为常量矩阵，初始化时上传设备。
#
# 谱合成（全 GPU 算子）：
#   env    = Σ_i g_i·exp(-((f-F_i)/bw_i)²)          共振峰包络
#   comb   = tooth(f/f0)·(1/harmonic)                 谐波梳齿（O(1)：
#            tooth = exp(-(frac(f/f0)/δ)²)，round 取最近谐波）
#   tone   = env·comb·voiced
#   noise  = env·sqrt(f/fmax)·noiseMix                摩擦噪声谱
#   mag    = amp·(tone + noise)·highpass(f)
# =============================================================

public class Txt2WavVocoder
{
    public Int32 sampleRate = 16000
    public Int32 nfft = 512
    public Int32 hop = 256
    public Int32 specBins = 257
    public Int32 glIters = 3

    # 幅度谱逐帧热循环的分片并行（实验性，默认关）：
    # isolate 回传只能走 List<T>，T×K 结果的逐元素装箱/序列化开销在
    # 本机实测比本地单块慢 8~18%；大 T 或纯 CPU 长句可置 true 试并行。
    public bool asyncMag = false
    public Int32 magChunks = 2

    Device dev = null

    # 常量基（CPU 构造，to(dev) 后使用）
    Tensor winRowD = null     # [1, N] Hann 分析/合成窗（设备上）
    Tensor anaCT = null       # [N, K] 分析基转置（win·cos，设备上）
    Tensor anaST = null       # [N, K] 分析基转置（-win·sin，设备上）
    Tensor synB = null        # [K, N] 合成基 cos 折叠（设备上）
    Tensor synBS = null       # [K, N] 合成基 sin 折叠（设备上）
    Rng rng = null

    # CPU 兜底路径的常量数组（CPU 模式下 matmul 走 L0 解释循环，改数组 DFT）
    bool gpuMode = false
    Array<Float32> winArr = null
    Array<Float32> synBCT = null   # [N, K] 合成基 cos 转置（行主序，内层连续）
    Array<Float32> synBST = null   # [N, K] 合成基 sin 转置

    _init_( Device device, bool gpu )
    {
        this.dev = device
        this.gpuMode = gpu
        this.rng = Rng( 12345 )
        this.buildBases()
    }

    void buildBases()
    {
        Int32 N = this.nfft
        Int32 K = this.specBins
        Float32 nf = SystemConvertFloat32( N )
        Float32 invN = 1.0f / nf

        # Hann 窗（周期式）
        Array<Float32> w = Array<Float32>( N )
        Int32 n = 0
        while n < N
        {
            Float32 x = SystemConvertFloat32( n ) / nf
            w[ n ] = 0.5f - 0.5f * Mathf.cos( 6.2831853f * x )
            n = n + 1
        }

        # 分析基 AC[k,n] = win[n]·cos(2πkn/N)，AS[k,n] = -win[n]·sin(2πkn/N)
        Array<Float32> ac = Array<Float32>( K * N )
        Array<Float32> asArr = Array<Float32>( K * N )
        Int32 k = 0
        while k < K
        {
            n = 0
            while n < N
            {
                Float32 ang = 6.2831853f * SystemConvertFloat32( k * n % N ) / nf
                ac[ k * N + n ] = w[ n ] * Mathf.cos( ang )
                asArr[ k * N + n ] = 0.0f - w[ n ] * Mathf.sin( ang )
                n = n + 1
            }
            k = k + 1
        }
        Tensor anaC = Tensor( ac, Shape.matrix( K, N ) )
        Tensor anaS = Tensor( asArr, Shape.matrix( K, N ) )
        this.anaCT = anaC.transpose().to( this.dev )
        this.anaST = anaS.transpose().to( this.dev )

        # 合成基（IDFT 折叠，含 1/N 归一化）：
        #   x[n] = (1/N)·[ Re0 + Re_{K-1}·(-1)^n + Σ 2(Re_k·cos - Im_k·sin) ]
        #   SBc[k,n]: k=0→1；k=K-1→(-1)^n；内部→2cos（均 ×1/N）
        #   SBs[k,n]: 边界→0；内部→-2sin（均 ×1/N）
        Array<Float32> sbc = Array<Float32>( K * N )
        Array<Float32> sbs = Array<Float32>( K * N )
        k = 0
        while k < K
        {
            n = 0
            while n < N
            {
                Float32 ang = 6.2831853f * SystemConvertFloat32( k * n % N ) / nf
                if k == 0
                {
                    sbc[ k * N + n ] = invN
                    sbs[ k * N + n ] = 0.0f
                }
                elif k == K - 1
                {
                    if n % 2 == 0
                    {
                        sbc[ k * N + n ] = invN
                    }
                    else
                    {
                        sbc[ k * N + n ] = -invN
                    }
                    sbs[ k * N + n ] = 0.0f
                }
                else
                {
                    sbc[ k * N + n ] = 2.0f * Mathf.cos( ang ) * invN
                    sbs[ k * N + n ] = -2.0f * Mathf.sin( ang ) * invN
                }
                n = n + 1
            }
            k = k + 1
        }
        this.synB = Tensor( sbc, Shape.matrix( K, N ) ).to( this.dev )
        this.synBS = Tensor( sbs, Shape.matrix( K, N ) ).to( this.dev )

        # 窗（设备版 + CPU 数组版）
        this.winRowD = Tensor( w, Shape.matrix( 1, N ) ).to( this.dev )
        this.winArr = w

        # 合成基转置 [N, K]（CPU 数组 DFT 用，内层 k 连续访问）
        this.synBCT = Array<Float32>( N * K )
        this.synBST = Array<Float32>( N * K )
        Int32 nn = 0
        while nn < N
        {
            Int32 kk = 0
            while kk < K
            {
                this.synBCT[ nn * K + kk ] = sbc[ kk * N + nn ]
                this.synBST[ nn * K + kk ] = sbs[ kk * N + nn ]
                kk = kk + 1
            }
            nn = nn + 1
        }
    }

    # ── 幅度谱合成作业体（本地/isolate 共用）────────────────
    # isolate 消息通道只认 List<T>，故全部载荷用 List；返回与 TensorAsync
    # 一致的打包张量 [ dims:List<Int32>, data:List<Float32> ]。
    # payload: [0]=[rows,K] [1]=[binHz] [2]=ctx 行块(rows*8) [3]=f0 行块(rows)
    static object synthMagJob( object arg )
    {
        List<object> job = arg as List<object>
        if job == null
        {
            ret null
        }
        List<Int32> meta = job._getItem_( 0 ) as List<Int32>
        List<Float32> cfg = job._getItem_( 1 ) as List<Float32>
        List<Float32> cd = job._getItem_( 2 ) as List<Float32>
        List<Float32> f0 = job._getItem_( 3 ) as List<Float32>
        if meta == null || cfg == null || cd == null || f0 == null
        {
            ret null
        }
        Int32 rows = meta._getItem_( 0 )
        Int32 K = meta._getItem_( 1 )
        Float32 binHz = cfg._getItem_( 0 )
        List<Float32> mag = new()

        Int32 t = 0
        while t < rows
        {
            Int32 rb = t * 8
            Float32 f1 = cd._getItem_( rb ) * 2000.0f
            Float32 f2 = cd._getItem_( rb + 1 ) * 6000.0f
            Float32 f3 = cd._getItem_( rb + 2 ) * 4000.0f
            Float32 v = 0.0f
            if cd._getItem_( rb + 3 ) > 0.4f
            {
                v = 1.0f
            }
            Float32 amp = cd._getItem_( rb + 4 ) * 2.0f
            Float32 nm = cd._getItem_( rb + 6 ) * 2.0f
            if nm > 1.0f
            {
                nm = 1.0f
            }
            Float32 bwn = cd._getItem_( rb + 7 ) * 2.0f
            if bwn < 0.5f
            {
                bwn = 0.5f
            }
            Float32 b1 = 105.0f * bwn
            Float32 b2 = 150.0f * bwn
            Float32 b3 = 210.0f * bwn
            Float32 f0t = f0._getItem_( t )
            if f0t < 20.0f
            {
                f0t = 20.0f
            }

            Int32 k = 0
            while k < K
            {
                Float32 f = SystemConvertFloat32( k ) * binHz

                # 共振峰包络（三共振峰高斯叠加）
                Float32 q1 = ( f - f1 ) / b1
                Float32 q2 = ( f - f2 ) / b2
                Float32 q3 = ( f - f3 ) / b3
                Float32 env = TensorMath.exp( 0.0f - q1 * q1 )
                env = env + 0.55f * TensorMath.exp( 0.0f - q2 * q2 )
                env = env + 0.3f * TensorMath.exp( 0.0f - q3 * q3 )

                # 谐波梳齿（O(1)：最近谐波高斯 + 1/h 衰减）
                Float32 xh = f / f0t
                Int32 ri = SystemConvertInt32( xh + 0.5f )
                if ri < 1
                {
                    ri = 1
                }
                Float32 rr = SystemConvertFloat32( ri )
                Float32 dd = xh - rr
                Float32 tooth = TensorMath.exp( 0.0f - 20.0f * dd * dd )
                Float32 comb = tooth / rr

                # 噪声谱（高频上翘）与浊音谱
                Float32 noise = env * Mathf.sqrt( f / 7800.0f ) * nm
                Float32 tone = env * comb * v

                # 高通滚降 + 振幅
                Float32 hp = f / 160.0f + 0.12f
                if hp < 0.12f
                {
                    hp = 0.12f
                }
                if hp > 1.0f
                {
                    hp = 1.0f
                }
                mag.add( amp * ( tone + noise ) * hp )
                k = k + 1
            }
            t = t + 1
        }

        List<Int32> dims = new()
        dims.add( rows )
        dims.add( K )
        List<object> packed = new()
        packed.add( dims )
        packed.add( mag )
        ret packed
    }

    # Isolate worker：执行行块作业并把打包结果送回请求方端口。
    static void magWorker( SendPort reply, List<object> payload )
    {
        if reply == null
        {
            ret
        }
        object res = Txt2WavVocoder.synthMagJob( payload )
        reply.send( res )
    }

    # 构造一个行块载荷（ctx 行 [r0,r1) + f0 行），全部用 List 便于跨 isolate。
    List<object> makeMagPayload( Array<Float32> cd, Array<Float32> f0, Int32 r0, Int32 r1, Int32 K, Float32 binHz )
    {
        List<Int32> meta = new()
        meta.add( r1 - r0 )
        meta.add( K )
        List<Float32> cfg = new()
        cfg.add( binHz )
        List<Float32> cdPart = new()
        Int32 q = r0 * 8
        Int32 qEnd = r1 * 8
        while q < qEnd
        {
            cdPart.add( cd[ q ] )
            q = q + 1
        }
        List<Float32> f0Part = new()
        q = r0
        while q < r1
        {
            f0Part.add( f0[ q ] )
            q = q + 1
        }
        List<object> payload = new()
        payload.add( meta )
        payload.add( cfg )
        payload.add( cdPart )
        payload.add( f0Part )
        ret payload
    }

    # 在静态上下文里起 isolate（闭包不能捕获 this / Device / Tensor）。
    static TensorJob submitMagJob( List<object> payload )
    {
        ReceivePort rp = ReceivePort()
        SendPort sp = rp.sendPort
        function worker = function( SendPort reply, List<object> partPayload )
        {
            Txt2WavVocoder.magWorker( reply, partPayload )
        }
        Isolate iso = Isolate.spawn( worker( sp, payload ) )
        TensorJob j = TensorJob( EComputeMode.Iso )
        j._attachIsolate( iso, rp )
        ret j
    }

    # ── 幅度谱合成：ctx [T, 8]（CPU 张量）→ mag [T, K]（设备上）──
    # 默认本地单块直算；asyncMag=true 时按行块切给 isolate 并行，
    # waitAll 挂起当前协程收口。数学与原地循环一致（同一运算次序）。
    Tensor synthMagnitude( Tensor ctx, Array<Float32> f0 )
    {
        Int32 T = ctx.rows()
        Int32 K = this.specBins
        Tensor ctxC = ctx.cpu()
        Array<Float32> cd = ctxC._data
        Array<Float32> mag = Array<Float32>( T * K )
        Float32 binHz = SystemConvertFloat32( this.sampleRate ) / SystemConvertFloat32( this.nfft )

        Int32 chunks = this.magChunks
        if chunks < 1
        {
            chunks = 1
        }
        if !this.asyncMag || T < 32
        {
            chunks = 1
        }
        if chunks > T
        {
            chunks = T
        }

        if chunks == 1
        {
            # 默认快路径：原始 Array 逐帧循环，零装箱零序列化
            Int32 t = 0
            while t < T
            {
                Int32 rb = t * 8
                Float32 f1 = cd[ rb ] * 2000.0f
                Float32 f2 = cd[ rb + 1 ] * 6000.0f
                Float32 f3 = cd[ rb + 2 ] * 4000.0f
                Float32 v = 0.0f
                if cd[ rb + 3 ] > 0.4f
                {
                    v = 1.0f
                }
                Float32 amp = cd[ rb + 4 ] * 2.0f
                Float32 nm = cd[ rb + 6 ] * 2.0f
                if nm > 1.0f
                {
                    nm = 1.0f
                }
                Float32 bwn = cd[ rb + 7 ] * 2.0f
                if bwn < 0.5f
                {
                    bwn = 0.5f
                }
                Float32 b1 = 105.0f * bwn
                Float32 b2 = 150.0f * bwn
                Float32 b3 = 210.0f * bwn
                Float32 f0t = f0[ t ]
                if f0t < 20.0f
                {
                    f0t = 20.0f
                }

                Int32 rowBase = t * K
                Int32 k = 0
                while k < K
                {
                    Float32 f = SystemConvertFloat32( k ) * binHz
                    Float32 q1 = ( f - f1 ) / b1
                    Float32 q2 = ( f - f2 ) / b2
                    Float32 q3 = ( f - f3 ) / b3
                    Float32 env = TensorMath.exp( 0.0f - q1 * q1 )
                    env = env + 0.55f * TensorMath.exp( 0.0f - q2 * q2 )
                    env = env + 0.3f * TensorMath.exp( 0.0f - q3 * q3 )

                    Float32 xh = f / f0t
                    Int32 ri = SystemConvertInt32( xh + 0.5f )
                    if ri < 1
                    {
                        ri = 1
                    }
                    Float32 rr = SystemConvertFloat32( ri )
                    Float32 dd = xh - rr
                    Float32 tooth = TensorMath.exp( 0.0f - 20.0f * dd * dd )
                    Float32 comb = tooth / rr

                    Float32 noise = env * Mathf.sqrt( f / 7800.0f ) * nm
                    Float32 tone = env * comb * v
                    Float32 hp = f / 160.0f + 0.12f
                    if hp < 0.12f
                    {
                        hp = 0.12f
                    }
                    if hp > 1.0f
                    {
                        hp = 1.0f
                    }
                    mag[ rowBase + k ] = amp * ( tone + noise ) * hp
                    k = k + 1
                }
                t = t + 1
            }
        }
        else
        {
            # 可选并行路径：行块送 isolate，waitAll 按序收敛
            Array<TensorJob> jobs = Array<TensorJob>( chunks )
            Array<Int32> rowStarts = Array<Int32>( chunks )
            Int32 ci = 0
            while ci < chunks
            {
                Int32 r0 = ( T * ci ) / chunks
                Int32 r1 = ( T * ( ci + 1 ) ) / chunks
                rowStarts[ ci ] = r0
                List<object> payload = this.makeMagPayload( cd, f0, r0, r1, K, binHz )
                jobs[ ci ] = Txt2WavVocoder.submitMagJob( payload )
                ci = ci + 1
            }
            Array<Tensor> parts = TensorAsync.waitAll( jobs )
            ci = 0
            while ci < chunks
            {
                Tensor part = parts[ ci ]
                if part != null
                {
                    Array<Float32> pd = part._data
                    Int32 baseRow = rowStarts[ ci ] * K
                    Int32 pi = 0
                    while pi < pd.length
                    {
                        mag[ baseRow + pi ] = pd[ pi ]
                        pi = pi + 1
                    }
                }
                ci = ci + 1
            }
        }

        Tensor m = Tensor()
        m._shape = Shape.matrix( T, K )
        m._strides = m._shape.strides()
        m._data = mag
        ret m.to( this.dev )
    }

    # ── 初始相位：线性相位（bin 对齐延迟）+ 噪声占比随机化 ──
    # 返回 [re, im]（CPU 张量对）
    Array<Tensor> initPhase( Int32 T, Array<Float32> nmxArr, Array<Float32> f0 )
    {
        Int32 K = this.specBins
        Array<Float32> re = Array<Float32>( T * K )
        Array<Float32> im = Array<Float32>( T * K )
        # 相位传播：φ[t,k] = φ[t-1,k] + 2π·round(f_k/f0)·f0·hop/sr
        # （谐波相位逐帧递推，比固定线性相位帧间更连续；wrap 防 Float32 精度损失）
        Array<Float32> prevAng = Array<Float32>( K )
        Float32 binHz = SystemConvertFloat32( this.sampleRate ) / SystemConvertFloat32( this.nfft )
        Int32 k0 = 0
        while k0 < K
        {
            prevAng[ k0 ] = 0.0f
            k0 = k0 + 1
        }

        Int32 t = 0
        while t < T
        {
            Float32 nm = nmxArr[ t ]
            Float32 f0t = f0[ t ]
            if f0t < 20.0f
            {
                f0t = 20.0f
            }
            # 每帧谐波相位基增量：2π·f0·hop/sr
            Float32 harmInc = 6.2831853f * f0t * SystemConvertFloat32( this.hop ) / SystemConvertFloat32( this.sampleRate )
            Int32 rowBase = t * K
            Int32 k = 0
            while k < K
            {
                # 谐波指数 rr = round(f_k / f0)
                Float32 xh = SystemConvertFloat32( k ) * binHz / f0t
                Int32 ri = SystemConvertInt32( xh + 0.5f )
                if ri < 1
                {
                    ri = 1
                }
                Float32 ang = prevAng[ k ] + SystemConvertFloat32( ri ) * harmInc
                # wrap 到 [0, 2π)
                Int32 wi = SystemConvertInt32( ang / 6.2831853f )
                ang = ang - 6.2831853f * SystemConvertFloat32( wi )
                if nm > 0.01f
                {
                    ang = ang + nm * 6.2831853f * this.rng.nextFloat()
                }
                prevAng[ k ] = ang
                re[ rowBase + k ] = Mathf.cos( ang )
                im[ rowBase + k ] = Mathf.sin( ang )
                k = k + 1
            }
            t = t + 1
        }
        Array<Tensor> pair = Array<Tensor>( 2 )
        Tensor reT = Tensor()
        reT._shape = Shape.matrix( T, K )
        reT._strides = reT._shape.strides()
        reT._data = re
        Tensor imT = Tensor()
        imT._shape = Shape.matrix( T, K )
        imT._strides = imT._shape.strides()
        imT._data = im
        pair[ 0 ] = reT
        pair[ 1 ] = imT
        ret pair
    }

    # ── ISTFT：Re/Im [T,K]（设备上）→ y [M]（CPU 数组）──
    Array<Float32> istft( Tensor reD, Tensor imD, Int32 T )
    {
        Int32 N = this.nfft
        Int32 K = this.specBins
        Array<Float32> fd = null
        if this.gpuMode
        {
            Tensor frames = reD.matmul( this.synB ).add( imD.matmul( this.synBS ) )
            Tensor fw = frames.mul( this.winRowD )
            Tensor fwC = fw.cpu()
            fd = fwC._data
        }
        else
        {
            # CPU 数组 DFT：fw[t,n] = win[n]·Σ_k( re[t,k]·SBcT[n,k] + im[t,k]·SBsT[n,k] )
            # （CPU 模式下 Tensor.matmul 走 L0 解释循环的 at()，慢两个数量级）
            Tensor reC = reD.cpu()
            Tensor imC = imD.cpu()
            Array<Float32> red = reC._data
            Array<Float32> imd = imC._data
            Array<Float32> fw = Array<Float32>( T * N )
            Int32 t = 0
            while t < T
            {
                Int32 rowR = t * K
                Int32 rowF = t * N
                Int32 n = 0
                while n < N
                {
                    Int32 rowB = n * K
                    Float32 acc = 0.0f
                    Int32 k = 0
                    while k < K
                    {
                        acc = acc + red[ rowR + k ] * this.synBCT[ rowB + k ] + imd[ rowR + k ] * this.synBST[ rowB + k ]
                        k = k + 1
                    }
                    fw[ rowF + n ] = acc * this.winArr[ n ]
                    n = n + 1
                }
                t = t + 1
            }
            fd = fw
        }

        Int32 M = ( T - 1 ) * this.hop + N
        Array<Float32> y = Array<Float32>( M )
        y.fill( 0.0f )
        Int32 t = 0
        while t < T
        {
            Int32 off0 = t * this.hop
            Int32 rowBase = t * N
            Int32 n = 0
            while n < N
            {
                y[ off0 + n ] = y[ off0 + n ] + fd[ rowBase + n ]
                n = n + 1
            }
            t = t + 1
        }
        ret y
    }

    # ── STFT：y [M]（CPU 数组）→ Re/Im [T,K]（设备上）──
    Array<Tensor> stft( Array<Float32> y, Int32 T )
    {
        Int32 N = this.nfft
        Tensor fr = Tensor()
        fr._shape = Shape.matrix( T, N )
        fr._strides = fr._shape.strides()
        Array<Float32> frd = Array<Float32>( T * N )
        fr._data = frd
        Int32 t = 0
        while t < T
        {
            Int32 off0 = t * this.hop
            Int32 rowBase = t * N
            Int32 n = 0
            while n < N
            {
                frd[ rowBase + n ] = y[ off0 + n ]
                n = n + 1
            }
            t = t + 1
        }
        Tensor frD = fr.to( this.dev )
        Tensor reD = frD.matmul( this.anaCT )
        Tensor imD = frD.matmul( this.anaST )
        frD.freeDevice()
        Array<Tensor> pair = Array<Tensor>( 2 )
        pair[ 0 ] = reD
        pair[ 1 ] = imD
        ret pair
    }

    # ── 主入口：ctx [T,8] + f0[T] → 波形（CPU Float32 数组）──
    Array<Float32> synthesize( Tensor ctx, Array<Float32> f0 )
    {
        Int32 T = ctx.rows()
        Int32 K = this.specBins

        # 目标幅度谱（设备上）
        Tensor magD = this.synthMagnitude( ctx, f0 )

        # 读取 noiseMix 用于相位随机化
        Tensor ctxC = ctx.cpu()
        Array<Float32> nmxArr = Array<Float32>( T )
        Int32 t = 0
        while t < T
        {
            Float32 nm = ctxC.at( t, 6 ) * 2.0f
            if nm > 1.0f
            {
                nm = 1.0f
            }
            nmxArr[ t ] = nm
            t = t + 1
        }

        # 初始相位 + ISTFT
        Array<Tensor> ph = this.initPhase( T, nmxArr, f0 )
        Tensor reD = ph[ 0 ].to( this.dev )
        Tensor imD = ph[ 1 ].to( this.dev )
        Array<Float32> y = this.istft( reD, imD, T )
        reD.freeDevice()
        imD.freeDevice()

        # Griffin-Lim 迭代：|STFT(y)| 向 mag 投影
        # 投影在 CPU 数组上做（GPU 只留 STFT/ISTFT 的 matmul）：
        # 张量链版本每迭代分配 ~10 个 T×K/T×N 装箱数组触发 GC 风暴，
        # 实测每迭代固定 ~15s；数组版 <1s
        if this.glIters > 0
        {
            Tensor magCpu = magD.cpu()
            Array<Float32> magd = magCpu._data
            Int32 tk = T * K
            Int32 it = 0
            while it < this.glIters
            {
                Array<Tensor> sp = this.stft( y, T )
                Tensor yr = sp[ 0 ]
                Tensor yi = sp[ 1 ]
                Tensor yrC = yr.cpu()
                Tensor yiC = yi.cpu()
                Array<Float32> yrd = yrC._data
                Array<Float32> yid = yiC._data
                Array<Float32> nrd = Array<Float32>( tk )
                Array<Float32> nid = Array<Float32>( tk )
                Int32 idx = 0
                while idx < tk
                {
                    Float32 r = yrd[ idx ]
                    Float32 c = yid[ idx ]
                    Float32 dn = Mathf.sqrt( r * r + c * c ) + 0.000001f
                    Float32 sc = magd[ idx ] / dn
                    nrd[ idx ] = r * sc
                    nid[ idx ] = c * sc
                    idx = idx + 1
                }
                yr.freeDevice()
                yi.freeDevice()
                Tensor nrT = Tensor()
                nrT._shape = Shape.matrix( T, K )
                nrT._strides = nrT._shape.strides()
                nrT._data = nrd
                Tensor niT = Tensor()
                niT._shape = Shape.matrix( T, K )
                niT._strides = niT._shape.strides()
                niT._data = nid
                Tensor nrD = nrT.to( this.dev )
                Tensor niD = niT.to( this.dev )
                y = this.istft( nrD, niD, T )
                nrD.freeDevice()
                niD.freeDevice()
                it = it + 1
            }
        }
        magD.freeDevice()

        # 峰值归一化 + 首尾淡入淡出
        Float32 peak = 0.0f
        t = 0
        while t < y.length
        {
            Float32 a = y[ t ]
            if a < 0.0f
            {
                a = -a
            }
            if a > peak
            {
                peak = a
            }
            t = t + 1
        }
        if peak > 1e-6f
        {
            Float32 g = 0.82f / peak
            t = 0
            while t < y.length
            {
                y[ t ] = y[ t ] * g
                t = t + 1
            }
        }
        Int32 fade = this.sampleRate / 100
        if fade > y.length / 4
        {
            fade = y.length / 4
        }
        t = 0
        while t < fade
        {
            Float32 g = SystemConvertFloat32( t ) / SystemConvertFloat32( fade )
            y[ t ] = y[ t ] * g
            y[ y.length - 1 - t ] = y[ y.length - 1 - t ] * g
            t = t + 1
        }
        ret y
    }
}
