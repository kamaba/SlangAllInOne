# =========================================================================
# CudaBackend —— cvm GPU 平台的算子执行层（P2A，TensoraBackend.md §6.2）
#
# 通路（cvm 合一架构，不再引用外部 SLangCuda 模块）：
#   Tensor 算子设备分支 → stageOut（§5.2.1 上传协议）→ PTX kernel JIT
#   加载（CudaKernel.fromPtx 链路的句柄缓存）→ launch → 出口张量 S2
#   （读迫同步，§5.2.2 下载协议）。
#
# kernel 表（13 opId / 10 个 PTX entry + 2 个库级原语，§6.2）：
#   t_add/t_sub/t_mul/t_div  逐元素二元（dst, a, b, n, blen；广播下标映射
#                             blen==n 同形 / blen=cols 行向量 / blen=1 标量）
#   t_scale                  dst, a, k(f32), n（scale / scaleInPlace 原地版）
#   t_unary                  dst, a, n, op（0=relu 1=sigmoid 2=tanh 3=exp）
#   t_sum                    dst, a, n（单线程标量序累加，位级一致）
#   t_mmul                   dst, a, b, M, K, N（每线程一输出，p 序 dot）
#   t_smx                    dst, a, rows, cols（每线程一行，max→exp→归一）
#   t_fill                   dst, value(f32), n（fillValue 设备版）
#   （无 kernel）libMemcpyD2D —— 同设备 clone / copyFrom（P5，§5.2.4）
#   （无 kernel）libMemset8  —— zero 设备版（P5）
#
# 位级策略（§6.1.4 契约的 GPU 对应面）：
#   - 算术类（add/sub/mul/div/scale/mmul/sum/fill + D2D/memset）：kernel 内
#     运算序与 CPU L0 完全一致（mmul 的 p 序标量累加、sum 的单线程标量序、
#     mul.rn+add.rn 禁 fma）→ 与 L0 逐位一致（构造性保证）；
#   - 超越类（sigmoid/tanh/exp/softmax）：GPU 无 CRT expf，exp 以
#     f64 变换 + ex2.approx 实现（相对误差 ~2^-23），确定但不逐位 ——
#     一致性验收按容差 1e-6（PyTorch 同样不承诺跨设备逐位）；relu 为纯
#     比较语义，仍逐位一致。
#
# 状态机与协议（§5）：stageOut/uploadFlow/downloadFlow 实现三位置六原语
#   （P1/P2/P3/P4 逐元素循环 + 整块 DMA，P5 设备内）；分配走 §5.3 预检
#   （memFreeBytes）+ Device.bytesUsed 记账；v1 全同步语义（下载前
#   libCtxSync；算子间依赖 null stream 天然顺序化）。
#
# v1 已知取舍（见各方法注释）：
#   - kernel 模块 JIT 后不卸载（SL 无析构钩子，进程退出驱动回收，
#     与 vm_sl_cuda.h primary context 同策略）；
#   - JIT 失败粘性（一次性探测，之后全部回落 CPU 合并路径，值仍正确）；
#   - 混合设备 / 不支持广播形态 / 列向量广播 → Tensor 侧 CPU 合并路径
#     （§5.2.5 的 BackendError 抛错待算子 throws 通道扩展，v2）；
#   - 多卡：launch 前按张量 _device.id 切换 primary context；peer copy
#     不支持（OQ-9 同 v1——跨设备在 Tensor 侧体现为 CPU 合并回落）。
#
# 命名空间由 Tensora.jsonc struct 树定义（namespace Tensora / class
# CudaBackend），文件内不声明 namespace 块（同工程其余文件约定一致）。
# =========================================================================

public class CudaBackend
{
    # ── kernel 句柄缓存（Int64 承载，0 = 未加载；模块不卸载）──
    static bool _kTried = false
    static bool _kOk = false
    static Int64 _cfg = 0          # 启动描述块（40B，CudaKernel.launch 同布局）
    static Int64 _f_add = 0
    static Int64 _f_sub = 0
    static Int64 _f_mul = 0
    static Int64 _f_div = 0
    static Int64 _f_min = 0
    static Int64 _f_max = 0
    static Int64 _f_scale = 0
    static Int64 _f_unary = 0
    static Int64 _f_sum = 0
    static Int64 _f_mmul = 0
    static Int64 _f_smx = 0
    static Int64 _f_fill = 0

    # 驱动/设备就绪（不含 Backends 开关——开关只门 to() 的入口；
    # 张量一旦驻留 GPU，算子路径由位置决定，不再受开关影响）
    public static bool cudaOk()
    {
        ret Cuda.initialize() && Cuda.deviceCount() > 0
    }

    # kernel JIT 就绪（粘性：一次性探测；任一失败即永久回落 CPU）
    public static bool kernelsReady()
    {
        if CudaBackend._kOk
        {
            ret true
        }
        if CudaBackend._kTried
        {
            ret false
        }
        CudaBackend._kTried = true
        if !CudaBackend.cudaOk()
        {
            ret false
        }
        CudaBackend._cfg = Memory.alloc( 40 )
        if CudaBackend._cfg == 0
        {
            ret false
        }
        CudaBackend._f_add   = CudaBackend.jit( CudaBackend.ptxBin( "t_add", "add.rn.f32" ), "t_add" )
        CudaBackend._f_sub   = CudaBackend.jit( CudaBackend.ptxBin( "t_sub", "sub.rn.f32" ), "t_sub" )
        CudaBackend._f_mul   = CudaBackend.jit( CudaBackend.ptxBin( "t_mul", "mul.rn.f32" ), "t_mul" )
        CudaBackend._f_div   = CudaBackend.jit( CudaBackend.ptxBin( "t_div", "div.rn.f32" ), "t_div" )
        CudaBackend._f_min   = CudaBackend.jit( CudaBackend.ptxBin( "t_min", "min.f32" ), "t_min" )
        CudaBackend._f_max   = CudaBackend.jit( CudaBackend.ptxBin( "t_max", "max.f32" ), "t_max" )
        CudaBackend._f_scale = CudaBackend.jit( CudaBackend.ptxScale(), "t_scale" )
        CudaBackend._f_unary = CudaBackend.jit( CudaBackend.ptxUnary(), "t_unary" )
        CudaBackend._f_sum   = CudaBackend.jit( CudaBackend.ptxSum(), "t_sum" )
        CudaBackend._f_mmul  = CudaBackend.jit( CudaBackend.ptxMmul(), "t_mmul" )
        CudaBackend._f_smx   = CudaBackend.jit( CudaBackend.ptxSmx(), "t_smx" )
        CudaBackend._f_fill  = CudaBackend.jit( CudaBackend.ptxFill(), "t_fill" )
        if CudaBackend._f_add == 0 || CudaBackend._f_sub == 0 || CudaBackend._f_mul == 0
        {
            ret false
        }
        if CudaBackend._f_div == 0 || CudaBackend._f_min == 0 || CudaBackend._f_max == 0
        {
            ret false
        }
        if CudaBackend._f_sum == 0 || CudaBackend._f_mmul == 0
        {
            ret false
        }
        if CudaBackend._f_smx == 0 || CudaBackend._f_fill == 0
        {
            ret false
        }
        CudaBackend._kOk = true
        ret true
    }

    # 单 kernel JIT：fromPtx 链路（模块不卸载，句柄失效仅随进程）
    static Int64 jit( string ptx, string entry )
    {
        Int64 m = Cuda.libModuleLoadData( ptx )
        if m == 0
        {
            ret 0
        }
        Int64 f = Cuda.libModuleGetFunction( m, entry )
        if f == 0
        {
            Cuda.libModuleUnload( m )
            ret 0
        }
        ret f
    }

    # ── launch 底座：写启动描述块 + libKernelLaunch（null stream）──
    # total/block 决定 grid（一维）；v1 全同步语义依赖 null stream 顺序化
    static bool launchFlat( Int64 func, Int32 total, Int32 block, Int64 argsPtr )
    {
        Int32 grid = ( total + block - 1 ) / block
        if grid < 1
        {
            grid = 1
        }
        ret CudaBackend.launch2D( func, grid, 1, block, 1, 0, argsPtr )
    }

    # 二维 launch（t_mmul tiled 用）：grid gx×gy / block bx×by / shared 字节
    static bool launch2D( Int64 func, Int32 gx, Int32 gy, Int32 bx, Int32 by,
                          Int32 sharedBytes, Int64 argsPtr )
    {
        if func == 0 || CudaBackend._cfg == 0
        {
            ret false
        }
        if gx < 1
        {
            gx = 1
        }
        if gy < 1
        {
            gy = 1
        }
        Memory.writeI32( CudaBackend._cfg, 0, gx )
        Memory.writeI32( CudaBackend._cfg, 4, gy )
        Memory.writeI32( CudaBackend._cfg, 8, 1 )
        Memory.writeI32( CudaBackend._cfg, 12, bx )
        Memory.writeI32( CudaBackend._cfg, 16, by )
        Memory.writeI32( CudaBackend._cfg, 20, 1 )
        Memory.writeI32( CudaBackend._cfg, 24, sharedBytes )
        Memory.writeI32( CudaBackend._cfg, 28, 0 )
        Memory.writeI64( CudaBackend._cfg, 32, 0 )
        ret Cuda.libKernelLaunch( func, CudaBackend._cfg, argsPtr )
    }

    # ================================================================
    # PTX 生成器（.version 8.0 / .target sm_75，向下 JIT 兼容；
    # 实测教训见 Cuda.md：gid 块偏移公式 / 寄存器组预算 / 尾部越界判停）。
    # 注意：SL 语句按行切分——字符串一律逐行 s = s + "..." 累积构建。
    # ================================================================

    # 公共头：寄存器声明 + gid = %ctaid.x * %ntid.x + %tid.x
    # %r0/%r2/%r3/%r4 为 gid 专用；%r1 起由各 kernel 自用
    static string ptxHead( string entry, string paramDecls, string regs )
    {
        string s = ""
        s = s + ".version 8.0\n"
        s = s + ".target sm_75\n"
        s = s + ".address_size 64\n"
        s = s + "\n"
        s = s + ".visible .entry " + entry + "(\n"
        s = s + paramDecls
        s = s + "\n)\n"
        s = s + "{\n"
        s = s + "    .reg .b32 %r<27>;\n"
        s = s + regs
        s = s + "\n"
        s = s + "    mov.u32 %r0, %tid.x;\n"
        s = s + "    mov.u32 %r2, %ctaid.x;\n"
        s = s + "    mov.u32 %r3, %ntid.x;\n"
        s = s + "    mad.lo.u32 %r4, %r2, %r3, %r0;\n"
        ret s
    }

    # exp 序列：e^xin → xout = 2^(xin·log2e)，即 CUDA __expf 同构实现
    # （f32 乘 + ex2.approx，相对误差 ~ln2·ulp(y)）。**不用 f64 域**：
    # 驱动 13.3 JIT 实测坑（218）——f64/s64 域指令链（cvt.rn.f64.f32 /
    # mul.rn.f64 / cvt.s64.f64 等组合）触发 PTX JIT 失败（寄存器与舍入
    # 后缀多组合排查无果，见 CudaBackendTest 探针记录），纯 f32 链已验证
    # 可靠。精度：|x| ≤ 10 时相对误差 ≤ ~6e-7（1e-6 容差内）；超大 |x|
    # 误差按 |x|·2^-24·ln2 增长（已知取舍，等价 __expf 语义）。
    # 调用点寄存器约定：内部占用 %f6（乘法临时），输出写 xout——
    # t_unary/t_smx 的两次内联调用须时序错开（先后顺序使用则可复用）
    static string ptxExp( string xin, string xout )
    {
        string s = ""
        s = s + "    mul.rn.f32 %f6, %" + xin + ", 0f3FB8AA3B;\n"
        s = s + "    ex2.approx.f32 %" + xout + ", %f6;\n"
        ret s
    }

    # 逐元素二元：grid-stride；blen==n 同形直取，否则 b[gid % blen]
    # （行向量 [1,n] / 标量 [1] 的设备版广播映射，§5.2.6）
    static string ptxBin( string entry, string fop )
    {
        string s = CudaBackend.ptxHead( entry, "    .param .u64 dst,\n    .param .u64 a,\n    .param .u64 b,\n    .param .u32 n,\n    .param .u32 blen", "    .reg .b64 %rd<8>;\n    .reg .f32 %f<4>;\n    .reg .pred %p;\n" )
        s = s + "    ld.param.u64 %rd1, [dst];\n"
        s = s + "    ld.param.u64 %rd2, [a];\n"
        s = s + "    ld.param.u64 %rd3, [b];\n"
        s = s + "    ld.param.u32 %r1, [n];\n"
        s = s + "    ld.param.u32 %r5, [blen];\n"
        s = s + "    mov.u32 %r6, %nctaid.x;\n"
        s = s + "    mul.lo.u32 %r6, %r6, %r3;\n"
        s = s + "LOOP:\n"
        s = s + "    setp.ge.u32 %p, %r4, %r1;\n"
        s = s + "    @%p bra EXIT;\n"
        s = s + "    mov.u32 %r7, %r4;\n"
        s = s + "    setp.ne.u32 %p, %r5, %r1;\n"
        s = s + "    @%p rem.u32 %r7, %r4, %r5;\n"
        s = s + "    mad.wide.u32 %rd4, %r4, 4, %rd2;\n"
        s = s + "    mad.wide.u32 %rd5, %r7, 4, %rd3;\n"
        s = s + "    mad.wide.u32 %rd6, %r4, 4, %rd1;\n"
        s = s + "    ld.global.f32 %f1, [%rd4];\n"
        s = s + "    ld.global.f32 %f2, [%rd5];\n"
        s = s + "    " + fop + " %f3, %f1, %f2;\n"
        s = s + "    st.global.f32 [%rd6], %f3;\n"
        s = s + "    add.u32 %r4, %r4, %r6;\n"
        s = s + "    bra LOOP;\n"
        s = s + "EXIT:\n"
        s = s + "    ret;\n"
        s = s + "}\n"
        ret s
    }

    # dst[i] = a[i] * k（scaleInPlace 传 dst==a 即原地版，§5.2.4）
    static string ptxScale()
    {
        string s = CudaBackend.ptxHead( "t_scale", "    .param .u64 dst,\n    .param .u64 a,\n    .param .f32 k,\n    .param .u32 n", "    .reg .b64 %rd<7>;\n    .reg .f32 %f<4>;\n    .reg .pred %p;\n" )
        s = s + "    ld.param.u64 %rd1, [dst];\n"
        s = s + "    ld.param.u64 %rd2, [a];\n"
        s = s + "    ld.param.f32 %f1, [k];\n"
        s = s + "    ld.param.u32 %r1, [n];\n"
        s = s + "    mov.u32 %r6, %nctaid.x;\n"
        s = s + "    mul.lo.u32 %r6, %r6, %r3;\n"
        s = s + "LOOP:\n"
        s = s + "    setp.ge.u32 %p, %r4, %r1;\n"
        s = s + "    @%p bra EXIT;\n"
        s = s + "    mad.wide.u32 %rd4, %r4, 4, %rd2;\n"
        s = s + "    mad.wide.u32 %rd5, %r4, 4, %rd1;\n"
        s = s + "    ld.global.f32 %f2, [%rd4];\n"
        s = s + "    mul.rn.f32 %f3, %f2, %f1;\n"
        s = s + "    st.global.f32 [%rd5], %f3;\n"
        s = s + "    add.u32 %r4, %r4, %r6;\n"
        s = s + "    bra LOOP;\n"
        s = s + "EXIT:\n"
        s = s + "    ret;\n"
        s = s + "}\n"
        ret s
    }

    # 逐元素一元：op 分发表（对齐 Tensor.unaryGpu 调用点）——
    #   0=relu（逐位） 1=sigmoid 2=tanh 3=exp（以上容差类走 __expf）
    #   4=reciprocal 5=sqrt 6=rsqrt* 7=log2* 8=exp2*（*approx 容差）
    #   9=abs 10=neg 11=floor 12=ceil 13=round 14=sign 15=square（逐位）
    #   16=silu 17=gelu（tanh 近似式，容差）
    static string ptxUnary()
    {
        string s = CudaBackend.ptxHead( "t_unary", "    .param .u64 dst,\n    .param .u64 a,\n    .param .u32 n,\n    .param .u32 op", "    .reg .b32 %r<27>;\n    .reg .f32 %f<12>;\n    .reg .f64 %fd<4>;\n    .reg .pred %p;\n    .reg .pred %p1;\n" )
        s = s + "    ld.param.u64 %rd1, [dst];\n"
        s = s + "    ld.param.u64 %rd2, [a];\n"
        s = s + "    ld.param.u32 %r1, [n];\n"
        s = s + "    ld.param.u32 %r5, [op];\n"
        s = s + "    mov.u32 %r6, %nctaid.x;\n"
        s = s + "    mul.lo.u32 %r6, %r6, %r3;\n"
        s = s + "ULOOP:\n"
        s = s + "    setp.ge.u32 %p, %r4, %r1;\n"
        s = s + "    @%p bra EXIT;\n"
        s = s + "    mad.wide.u32 %rd4, %r4, 4, %rd2;\n"
        s = s + "    mad.wide.u32 %rd5, %r4, 4, %rd1;\n"
        s = s + "    ld.global.f32 %f1, [%rd4];\n"
        s = s + "    setp.lt.u32 %p, %r5, 4;\n"
        s = s + "    @%p bra UOLD;\n"
        s = s + "    setp.lt.u32 %p, %r5, 9;\n"
        s = s + "    @%p bra UNEW;\n"
        s = s + "    setp.lt.u32 %p, %r5, 16;\n"
        s = s + "    @%p bra UBIT;\n"
        s = s + "    setp.eq.u32 %p, %r5, 16;\n"
        s = s + "    @%p bra USILU;\n"
        s = s + "    setp.eq.u32 %p, %r5, 17;\n"
        s = s + "    @%p bra UGELU;\n"
        s = s + "    bra EXIT;\n"
        # ── 旧 op 0-3（relu/sigmoid/tanh/exp）──
        s = s + "UOLD:\n"
        s = s + "    setp.eq.u32 %p, %r5, 0;\n"
        s = s + "    @%p bra URELU;\n"
        s = s + "    setp.eq.u32 %p, %r5, 1;\n"
        s = s + "    @%p bra USIGM;\n"
        s = s + "    setp.eq.u32 %p, %r5, 2;\n"
        s = s + "    @%p bra UTANH;\n"
        s = s + CudaBackend.ptxExp( "f1", "f2" )
        s = s + "    bra UST;\n"
        s = s + "URELU:\n"
        s = s + "    setp.gt.f32 %p1, %f1, 0f00000000;\n"
        s = s + "    selp.f32 %f2, %f1, 0f00000000, %p1;\n"
        s = s + "    bra UST;\n"
        s = s + "USIGM:\n"
        s = s + "    mul.rn.f32 %f3, %f1, 0fBF800000;\n"
        s = s + CudaBackend.ptxExp( "f3", "f4" )
        s = s + "    add.rn.f32 %f5, %f4, 0f3F800000;\n"
        s = s + "    div.rn.f32 %f2, 0f3F800000, %f5;\n"
        s = s + "    bra UST;\n"
        s = s + "UTANH:\n"
        s = s + CudaBackend.ptxExp( "f1", "f4" )
        s = s + "    mul.rn.f32 %f5, %f1, 0fBF800000;\n"
        s = s + CudaBackend.ptxExp( "f5", "f6" )
        s = s + "    sub.rn.f32 %f10, %f4, %f6;\n"
        s = s + "    add.rn.f32 %f11, %f4, %f6;\n"
        s = s + "    div.rn.f32 %f2, %f10, %f11;\n"
        s = s + "    bra UST;\n"
        # ── 新 op 4-8（reciprocal/sqrt/rsqrt/log2/exp2，approx 容差）──
        s = s + "UNEW:\n"
        s = s + "    setp.eq.u32 %p, %r5, 4;\n"
        s = s + "    @%p div.rn.f32 %f2, 0f3F800000, %f1;\n"
        s = s + "    setp.eq.u32 %p, %r5, 5;\n"
        s = s + "    @%p sqrt.rn.f32 %f2, %f1;\n"
        s = s + "    setp.eq.u32 %p, %r5, 6;\n"
        s = s + "    @%p rsqrt.approx.f32 %f2, %f1;\n"
        s = s + "    setp.eq.u32 %p, %r5, 7;\n"
        s = s + "    @%p lg2.approx.f32 %f2, %f1;\n"
        s = s + "    setp.eq.u32 %p, %r5, 8;\n"
        s = s + "    @%p ex2.approx.f32 %f2, %f1;\n"
        s = s + "    bra UST;\n"
        # ── 新 op 9-15（abs/neg/floor/ceil/round/sign/square，逐位）──
        s = s + "UBIT:\n"
        s = s + "    setp.eq.u32 %p, %r5, 9;\n"
        s = s + "    @%p bra UABS;\n"
        s = s + "    setp.eq.u32 %p, %r5, 10;\n"
        s = s + "    @%p bra UNEG;\n"
        s = s + "    setp.eq.u32 %p, %r5, 11;\n"
        s = s + "    @%p cvt.rm.f32.f32 %f2, %f1;\n"
        s = s + "    setp.eq.u32 %p, %r5, 12;\n"
        s = s + "    @%p cvt.rp.f32.f32 %f2, %f1;\n"
        s = s + "    setp.eq.u32 %p, %r5, 13;\n"
        s = s + "    @%p cvt.rni.f32.f32 %f2, %f1;\n"
        s = s + "    setp.eq.u32 %p, %r5, 15;\n"
        s = s + "    @%p mul.rn.f32 %f2, %f1, %f1;\n"
        s = s + "    setp.eq.u32 %p, %r5, 14;\n"
        s = s + "    @%p bra USIGN;\n"
        s = s + "    bra UST;\n"
        s = s + "UABS:\n"
        s = s + "    mov.b32 %r7, %f1;\n"
        s = s + "    and.b32 %r7, %r7, 0x7FFFFFFF;\n"
        s = s + "    mov.b32 %f2, %r7;\n"
        s = s + "    bra UST;\n"
        s = s + "UNEG:\n"
        s = s + "    mov.b32 %r7, %f1;\n"
        s = s + "    xor.b32 %r7, %r7, 0x80000000;\n"
        s = s + "    mov.b32 %f2, %r7;\n"
        s = s + "    bra UST;\n"
        s = s + "USIGN:\n"
        s = s + "    mov.f32 %f2, 0f00000000;\n"
        s = s + "    setp.gt.f32 %p1, %f1, 0f00000000;\n"
        s = s + "    @%p1 mov.f32 %f2, 0f3F800000;\n"
        s = s + "    setp.lt.f32 %p1, %f1, 0f00000000;\n"
        s = s + "    @%p1 mov.f32 %f2, 0fBF800000;\n"
        s = s + "    bra UST;\n"
        # ── 新 op 16/17（silu/gelu，tanh 近似容差）──
        s = s + "USILU:\n"
        s = s + "    mul.rn.f32 %f3, %f1, 0fBF800000;\n"
        s = s + CudaBackend.ptxExp( "f3", "f4" )
        s = s + "    add.rn.f32 %f5, %f4, 0f3F800000;\n"
        s = s + "    div.rn.f32 %f6, 0f3F800000, %f5;\n"
        s = s + "    mul.rn.f32 %f2, %f1, %f6;\n"
        s = s + "    bra UST;\n"
        s = s + "UGELU:\n"
        s = s + "    mul.rn.f32 %f3, %f1, %f1;\n"
        s = s + "    mul.rn.f32 %f4, %f3, %f1;\n"
        s = s + "    mul.rn.f32 %f4, %f4, 0f3D372713;\n"
        s = s + "    add.rn.f32 %f4, %f4, %f1;\n"
        s = s + "    mul.rn.f32 %f4, %f4, 0f3F4C422A;\n"
        s = s + "    mul.rn.f32 %f5, %f4, 0f40000000;\n"
        s = s + CudaBackend.ptxExp( "f5", "f6" )
        s = s + "    sub.rn.f32 %f7, %f6, 0f3F800000;\n"
        s = s + "    add.rn.f32 %f8, %f6, 0f3F800000;\n"
        s = s + "    div.rn.f32 %f9, %f7, %f8;\n"
        s = s + "    add.rn.f32 %f10, %f9, 0f3F800000;\n"
        s = s + "    mul.rn.f32 %f10, %f10, 0f3F000000;\n"
        s = s + "    mul.rn.f32 %f2, %f10, %f1;\n"
        s = s + "UST:\n"
        s = s + "    st.global.f32 [%rd5], %f2;\n"
        s = s + "    add.u32 %r4, %r4, %r6;\n"
        s = s + "    bra ULOOP;\n"
        s = s + "EXIT:\n"
        s = s + "    ret;\n"
        s = s + "}\n"
        ret s
    }

    # r[0] = sum(a)：单线程标量序累加（与 L0 逐位一致；并行树归约为 v2，
    # 那时改容差验收——float 加法不满足结合律，逐位一致只能保串行）
    static string ptxSum()
    {
        string s = CudaBackend.ptxHead( "t_sum", "    .param .u64 dst,\n    .param .u64 a,\n    .param .u32 n", "    .reg .b64 %rd<5>;\n    .reg .f32 %f<3>;\n    .reg .pred %p;\n" )
        s = s + "    ld.param.u64 %rd1, [dst];\n"
        s = s + "    ld.param.u64 %rd2, [a];\n"
        s = s + "    ld.param.u32 %r1, [n];\n"
        s = s + "    setp.gt.u32 %p, %r4, 0;\n"
        s = s + "    @%p bra EXIT;\n"
        s = s + "    mov.f32 %f1, 0f00000000;\n"
        s = s + "    mov.u32 %r5, 0;\n"
        s = s + "SLOOP:\n"
        s = s + "    setp.ge.u32 %p, %r5, %r1;\n"
        s = s + "    @%p bra SDONE;\n"
        s = s + "    mad.wide.u32 %rd3, %r5, 4, %rd2;\n"
        s = s + "    ld.global.f32 %f2, [%rd3];\n"
        s = s + "    add.rn.f32 %f1, %f1, %f2;\n"
        s = s + "    add.u32 %r5, %r5, 1;\n"
        s = s + "    bra SLOOP;\n"
        s = s + "SDONE:\n"
        s = s + "    st.global.f32 [%rd1], %f1;\n"
        s = s + "EXIT:\n"
        s = s + "    ret;\n"
        s = s + "}\n"
        ret s
    }

    # r[i,j] = Σ_p a[i,p]*b[p,j]：16×16 共享内存分块（tiled，二维 launch）。
    # 每线程负责一个输出格点；K 方向按 16 步进，每块协作加载 A/B tile 进
    # shared，块内 p 序升序 mul.rn+add.rn——块序列升序 × 块内升序 = 全局
    # p 升序，与 L0 同舍入链 → **逐位一致**（tiling 不改变单元素累加顺序）。
    # grid=(ceil(N/16),ceil(M/16))、block=(16,16)=256 线程、shared=2048B。
    # 边界三处（实测踩坑，均会读 stale 污染累加）：
    #   1) tile 加载条件：A 侧 by<M && ts<K，B 侧 bs<K && bx<N——越界格点
    #      跳过写（p 循环由 lim=min(16,K-kt) 截断保证不读越界列/行）；
    #   2) 越界线程**不得提前退出**：block 内 256 线程协作加载 + bar.sync
    #      全员参与，M 或 N <16 时多余线程若退出，B tile 的 K 维行
    #      （K>M 时仍合法）就没人写（13×17×9 实测错值根因）；
    #   3) 写出条件：by<M && bx<N 才写 dst。
    # 位级注意：越界用条件跳过而非填 0（0×NaN 会污染）。
    static string ptxMmul()
    {
        string s = CudaBackend.ptxHead( "t_mmul", "    .param .u64 dst,\n    .param .u64 a,\n    .param .u64 b,\n    .param .u32 M,\n    .param .u32 K,\n    .param .u32 N", "    .reg .b64 %rd<7>;\n    .reg .f32 %f<5>;\n    .reg .pred %p;\n    .reg .pred %p1;\n" )
        s = s + "    .shared .align 4 .b8 smem[2048];\n"
        s = s + "    ld.param.u64 %rd1, [dst];\n"
        s = s + "    ld.param.u64 %rd2, [a];\n"
        s = s + "    ld.param.u64 %rd3, [b];\n"
        s = s + "    ld.param.u32 %r1, [M];\n"
        s = s + "    ld.param.u32 %r5, [K];\n"
        s = s + "    ld.param.u32 %r6, [N];\n"
        s = s + "    mov.u32 %r10, %tid.x;\n"
        s = s + "    mov.u32 %r11, %tid.y;\n"
        s = s + "    mov.u32 %r12, %ctaid.y;\n"
        s = s + "    shl.b32 %r12, %r12, 4;\n"
        s = s + "    add.u32 %r13, %r12, %r11;\n"
        s = s + "    mov.u32 %r14, %ctaid.x;\n"
        s = s + "    shl.b32 %r14, %r14, 4;\n"
        s = s + "    add.u32 %r15, %r14, %r10;\n"
        s = s + "    mov.u32 %r20, smem;\n"
        s = s + "    add.u32 %r21, %r20, 1024;\n"
        s = s + "    shl.b32 %r18, %r11, 6;\n"
        s = s + "    shl.b32 %r19, %r10, 2;\n"
        s = s + "    add.u32 %r18, %r18, %r19;\n"
        s = s + "    add.u32 %r19, %r20, %r18;\n"
        s = s + "    add.u32 %r22, %r21, %r18;\n"
        s = s + "    mov.f32 %f1, 0f00000000;\n"
        s = s + "    mov.u32 %r16, 0;\n"
        s = s + "KLOOP:\n"
        s = s + "    setp.ge.u32 %p, %r16, %r5;\n"
        s = s + "    @%p bra KDONE;\n"
        s = s + "    add.u32 %r24, %r16, %r10;\n"
        s = s + "    mul.lo.u32 %r25, %r13, %r5;\n"
        s = s + "    add.u32 %r25, %r25, %r24;\n"
        s = s + "    mad.wide.u32 %rd4, %r25, 4, %rd2;\n"
        s = s + "    setp.ge.u32 %p, %r13, %r1;\n"
        s = s + "    @%p bra SKIPA;\n"
        s = s + "    setp.ge.u32 %p, %r24, %r5;\n"
        s = s + "    @%p bra SKIPA;\n"
        s = s + "    ld.global.f32 %f2, [%rd4];\n"
        s = s + "    st.shared.f32 [%r19], %f2;\n"
        s = s + "SKIPA:\n"
        s = s + "    add.u32 %r24, %r16, %r11;\n"
        s = s + "    mul.lo.u32 %r25, %r24, %r6;\n"
        s = s + "    add.u32 %r25, %r25, %r15;\n"
        s = s + "    mad.wide.u32 %rd5, %r25, 4, %rd3;\n"
        s = s + "    setp.ge.u32 %p, %r24, %r5;\n"
        s = s + "    @%p bra SKIPB;\n"
        s = s + "    setp.ge.u32 %p, %r15, %r6;\n"
        s = s + "    @%p bra SKIPB;\n"
        s = s + "    ld.global.f32 %f3, [%rd5];\n"
        s = s + "    st.shared.f32 [%r22], %f3;\n"
        s = s + "SKIPB:\n"
        s = s + "    bar.sync 0;\n"
        s = s + "    sub.u32 %r17, %r5, %r16;\n"
        s = s + "    setp.gt.u32 %p1, %r17, 16;\n"
        s = s + "    @%p1 mov.u32 %r17, 16;\n"
        s = s + "    mov.u32 %r24, 0;\n"
        s = s + "PLOOP:\n"
        s = s + "    setp.ge.u32 %p1, %r24, %r17;\n"
        s = s + "    @%p1 bra PDONE;\n"
        s = s + "    shl.b32 %r25, %r11, 6;\n"
        s = s + "    shl.b32 %r26, %r24, 2;\n"
        s = s + "    add.u32 %r25, %r25, %r26;\n"
        s = s + "    add.u32 %r26, %r20, %r25;\n"
        s = s + "    ld.shared.f32 %f2, [%r26];\n"
        s = s + "    shl.b32 %r25, %r24, 6;\n"
        s = s + "    shl.b32 %r26, %r10, 2;\n"
        s = s + "    add.u32 %r25, %r25, %r26;\n"
        s = s + "    add.u32 %r26, %r21, %r25;\n"
        s = s + "    ld.shared.f32 %f3, [%r26];\n"
        s = s + "    mul.rn.f32 %f4, %f2, %f3;\n"
        s = s + "    add.rn.f32 %f1, %f1, %f4;\n"
        s = s + "    add.u32 %r24, %r24, 1;\n"
        s = s + "    bra PLOOP;\n"
        s = s + "PDONE:\n"
        s = s + "    bar.sync 0;\n"
        s = s + "    add.u32 %r16, %r16, 16;\n"
        s = s + "    bra KLOOP;\n"
        s = s + "KDONE:\n"
        s = s + "    setp.ge.u32 %p, %r13, %r1;\n"
        s = s + "    @%p bra EXIT;\n"
        s = s + "    setp.ge.u32 %p, %r15, %r6;\n"
        s = s + "    @%p bra EXIT;\n"
        s = s + "    mul.lo.u32 %r25, %r13, %r6;\n"
        s = s + "    add.u32 %r25, %r25, %r15;\n"
        s = s + "    mad.wide.u32 %rd6, %r25, 4, %rd1;\n"
        s = s + "    st.global.f32 [%rd6], %f1;\n"
        s = s + "EXIT:\n"
        s = s + "    ret;\n"
        s = s + "}\n"
        ret s
    }

    # 逐行 softmax：每线程一行，max→exp-sum→归一三遍标量序
    # （与 L0 同算法结构；exp 差异由容差验收）
    static string ptxSmx()
    {
        string s = CudaBackend.ptxHead( "t_smx", "    .param .u64 dst,\n    .param .u64 a,\n    .param .u32 rows,\n    .param .u32 cols", "    .reg .b64 %rd<8>;\n    .reg .f32 %f<10>;\n    .reg .f64 %fd<4>;\n    .reg .pred %p;\n    .reg .pred %p1;\n" )
        s = s + "    ld.param.u64 %rd1, [dst];\n"
        s = s + "    ld.param.u64 %rd2, [a];\n"
        s = s + "    ld.param.u32 %r1, [rows];\n"
        s = s + "    ld.param.u32 %r5, [cols];\n"
        s = s + "    setp.ge.u32 %p, %r4, %r1;\n"
        s = s + "    @%p bra EXIT;\n"
        s = s + "    mul.lo.u32 %r6, %r4, %r5;\n"
        s = s + "    mad.wide.u32 %rd3, %r6, 4, %rd2;\n"
        s = s + "    mad.wide.u32 %rd4, %r6, 4, %rd1;\n"
        s = s + "    mov.u32 %r7, 0;\n"
        s = s + "    ld.global.f32 %f1, [%rd3];\n"
        s = s + "MLOOP:\n"
        s = s + "    setp.ge.u32 %p, %r7, %r5;\n"
        s = s + "    @%p bra MDONE;\n"
        s = s + "    mad.wide.u32 %rd5, %r7, 4, %rd3;\n"
        s = s + "    ld.global.f32 %f2, [%rd5];\n"
        s = s + "    setp.gt.f32 %p1, %f2, %f1;\n"
        s = s + "    @%p1 mov.f32 %f1, %f2;\n"
        s = s + "    add.u32 %r7, %r7, 1;\n"
        s = s + "    bra MLOOP;\n"
        s = s + "MDONE:\n"
        s = s + "    mov.f32 %f3, 0f00000000;\n"
        s = s + "    mov.u32 %r7, 0;\n"
        s = s + "DLOOP:\n"
        s = s + "    setp.ge.u32 %p, %r7, %r5;\n"
        s = s + "    @%p bra DDONE;\n"
        s = s + "    mad.wide.u32 %rd5, %r7, 4, %rd3;\n"
        s = s + "    ld.global.f32 %f4, [%rd5];\n"
        s = s + "    sub.rn.f32 %f4, %f4, %f1;\n"
        s = s + CudaBackend.ptxExp( "f4", "f5" )
        s = s + "    add.rn.f32 %f3, %f3, %f5;\n"
        s = s + "    add.u32 %r7, %r7, 1;\n"
        s = s + "    bra DLOOP;\n"
        s = s + "DDONE:\n"
        s = s + "    mov.u32 %r7, 0;\n"
        s = s + "OLOOP:\n"
        s = s + "    setp.ge.u32 %p, %r7, %r5;\n"
        s = s + "    @%p bra ODONE;\n"
        s = s + "    mad.wide.u32 %rd5, %r7, 4, %rd3;\n"
        s = s + "    ld.global.f32 %f4, [%rd5];\n"
        s = s + "    sub.rn.f32 %f4, %f4, %f1;\n"
        s = s + CudaBackend.ptxExp( "f4", "f5" )
        s = s + "    div.rn.f32 %f5, %f5, %f3;\n"
        s = s + "    mad.wide.u32 %rd7, %r7, 4, %rd4;\n"
        s = s + "    st.global.f32 [%rd7], %f5;\n"
        s = s + "    add.u32 %r7, %r7, 1;\n"
        s = s + "    bra OLOOP;\n"
        s = s + "ODONE:\n"
        s = s + "EXIT:\n"
        s = s + "    ret;\n"
        s = s + "}\n"
        ret s
    }

    # dst[i] = value（fillValue 设备版；0 值走 memset8 更省一次 launch）
    static string ptxFill()
    {
        string s = CudaBackend.ptxHead( "t_fill", "    .param .u64 dst,\n    .param .f32 value,\n    .param .u32 n", "    .reg .b64 %rd<5>;\n    .reg .f32 %f<2>;\n    .reg .pred %p;\n" )
        s = s + "    ld.param.u64 %rd1, [dst];\n"
        s = s + "    ld.param.f32 %f1, [value];\n"
        s = s + "    ld.param.u32 %r1, [n];\n"
        s = s + "    mov.u32 %r6, %nctaid.x;\n"
        s = s + "    mul.lo.u32 %r6, %r6, %r3;\n"
        s = s + "LOOP:\n"
        s = s + "    setp.ge.u32 %p, %r4, %r1;\n"
        s = s + "    @%p bra EXIT;\n"
        s = s + "    mad.wide.u32 %rd4, %r4, 4, %rd1;\n"
        s = s + "    st.global.f32 [%rd4], %f1;\n"
        s = s + "    add.u32 %r4, %r4, %r6;\n"
        s = s + "    bra LOOP;\n"
        s = s + "EXIT:\n"
        s = s + "    ret;\n"
        s = s + "}\n"
        ret s
    }

    # ================================================================
    # §5 staging 原语（三位置六原语的收口实现）
    # ================================================================

    # OQ-1（§5.7 基准立项，本轮落地）：SL 数组裸数据指针。
    # VMArray（csimple_lang vm_array.h）布局：VMObject(32B) + length@32 +
    # unit_length@36 + element_runtime_type@40 + data@48 —— data 即紧凑
    # 元素缓冲（f32 数组 = n*4 字节裸 float 区）。经已注册系统调用
    # SystemPtrFromObject + SystemPtrReadInt64 组合读取，DMA 直接消费，
    # 消除 P1/P4 逐元素循环（h2d_bench 实测占搬运成本 >99%）。
    # 布局防漂移：CudaBackendTest 的 pin 探针固化断言此偏移（data@48/
    # length@32 + 位模式对照），csimple_lang 布局变更时测试即红。
    # GC 安全（v1 全同步语义）：DMA 为同步调用，期间 VM 无并发执行、
    # 无 GC 触发；mark-sweep 非移动（对象/缓冲地址稳定）。v2 引入异步
    # 搬运（P6）前必须扩展真 pin 语义（引用计数 / 显式 unpin）。
    static Int64 arrayDataPtr( Array<Float32> a )
    {
        if a == null
        {
            ret 0
        }
        ret SystemPtrReadInt64( SystemPtrFromObject( a ), 48 )
    }

    # §5.3 分配：预检（不静默换页）+ 分配 + Device.bytesUsed 记账。
    # 0 = 失败（调用方回落或抛错）；dev 为张量所挂 Device 实例（记账
    # 聚合依赖复用同一 Device 对象，P1 既有语义）
    static Int64 allocDevRaw( Int64 bytes, Device dev )
    {
        Int64 freeBytes = Cuda.memFreeBytes()
        if bytes > freeBytes
        {
            ret 0
        }
        Cuda.libDeviceSet( dev.id )
        Int64 ptr = Cuda.libMemAlloc( bytes )
        if ptr == 0
        {
            ret 0
        }
        dev.alloc( bytes )
        ret ptr
    }

    # §5.3 释放：free + 记账回收
    static void freeDevRaw( Int64 ptr, Int64 bytes, Device dev )
    {
        if ptr != 0 && dev != null
        {
            Cuda.libDeviceSet( dev.id )
            Cuda.libMemFree( ptr )
            dev.free( bytes )
        }
    }

    # P2：主机数组 → 设备块（OQ-1：数组 data 指针直接 DMA，零逐元素循环；
    # 旧的 Memory.alloc 组包 + writeF32 循环路径已删——16M 元素实测 10.8s → 0）
    static bool uploadInto( Int64 devPtr, Array<Float32> values, Int32 bytes )
    {
        Int64 src = CudaBackend.arrayDataPtr( values )
        if src == 0
        {
            ret false
        }
        ret Cuda.libMemcpyH2D( devPtr, src, bytes )
    }

    # §5.2.1 上传协议（S1→S0；devBlock==0 时惰性分配——to() 之外的
    # 设备挂靠路径由此补首配，不变式 I3 仍成立：分配与置位同源）
    static bool uploadFlow( Tensor t )
    {
        if t._device == null || t._device.isCpu()
        {
            ret false
        }
        if !t._hostDirty
        {
            ret true
        }
        Int32 bytes = t._data.length * 4
        if t._devBlock == 0
        {
            Int64 ptr = CudaBackend.allocDevRaw( bytes, t._device )
            if ptr == 0
            {
                ret false
            }
            t._devBlock = ptr
        }
        if !CudaBackend.uploadInto( t._devBlock, t._data, bytes )
        {
            ret false
        }
        t._hostDirty = false
        ret true
    }

    # §5.2.2 下载协议（S2→S0）：v1 全同步语义——P3 前显式 ctx sync；
    # OQ-1：D2H 直写 _data 的 data 缓冲（P4 循环消除，实测 16M 元素 9.4s → 0）
    static bool downloadFlow( Tensor t )
    {
        if !t._devDirty || t._devBlock == 0
        {
            ret true
        }
        Cuda.libDeviceSet( t._device.id )
        Cuda.libCtxSync()
        Int32 bytes = t._data.length * 4
        Int64 dst = CudaBackend.arrayDataPtr( t._data )
        if dst == 0
        {
            ret false
        }
        bool ok = Cuda.libMemcpyD2H( dst, t._devBlock, bytes )
        if ok
        {
            t._devDirty = false
        }
        ret ok
    }

    # §4.3-步2 staging：设备算子入口保证输入最新（I1）；
    # CPU 张量恒 true（无影子可 stale）
    static bool stageOut( Tensor t )
    {
        if t._device == null || t._device.isCpu()
        {
            ret true
        }
        ret CudaBackend.uploadFlow( t )
    }

    # 设备张量构造（算子出口，S2：影子权威、主机过期——读迫同步才回传）
    static Tensor deviceTensor( Shape shp, Device dev, Int64 ptr )
    {
        Tensor t = Tensor()
        t._shape = shp
        t._strides = shp.strides()
        t._dtype = EDtype.F32
        t._data = Array<Float32>( shp.size() )
        t._device = dev
        t._devBlock = ptr
        t._hostDirty = false
        t._devDirty = true
        ret t
    }

    # ================================================================
    # 算子执行入口（Tensor 设备分支调用；失败 ret null/false，
    # 调用方无脑回落 CPU 合并路径——值仍正确，防静默错算）
    # ================================================================

    # 逐元素二元：op 0=add 1=sub 2=mul 3=div；blen 语义见 ptxBin。
    # 前置由调用方保证：双侧同设备驻留、f32、out 形状 == a 形状、
    # b 为同形 / 行向量 / 标量
    static Tensor elemwise( Tensor a, Tensor b, Int32 op, Int32 blen )
    {
        if !CudaBackend.kernelsReady()
        {
            ret null
        }
        if !CudaBackend.stageOut( a ) || !CudaBackend.stageOut( b )
        {
            ret null
        }
        Int32 n = a._data.length
        Int64 dst = CudaBackend.allocDevRaw( n * 4, a._device )
        if dst == 0
        {
            ret null
        }
        Int64 f = 0
        if op == 0
        {
            f = CudaBackend._f_add
        }
        if op == 1
        {
            f = CudaBackend._f_sub
        }
        if op == 2
        {
            f = CudaBackend._f_mul
        }
        if op == 3
        {
            f = CudaBackend._f_div
        }
        if op == 4
        {
            f = CudaBackend._f_min
        }
        if op == 5
        {
            f = CudaBackend._f_max
        }
        if f == 0
        {
            CudaBackend.freeDevRaw( dst, n * 4, a._device )
            ret null
        }
        CudaKernelArgs args = CudaKernelArgs( 5 )
        args.addPtr( dst )
        args.addPtr( a._devBlock )
        args.addPtr( b._devBlock )
        args.addI32( n )
        args.addI32( blen )
        bool ok = CudaBackend.launchFlat( f, n, 256, args.paramsBlock )
        args.free()
        if !ok
        {
            CudaBackend.freeDevRaw( dst, n * 4, a._device )
            ret null
        }
        ret CudaBackend.deviceTensor( a._shape.clone(), a._device, dst )
    }

    # dst = a * k（scale；scaleInPlace 由 Tensor 侧传 t 自身）
    static Tensor scaleGpu( Tensor a, Float32 k )
    {
        if !CudaBackend.kernelsReady()
        {
            ret null
        }
        if !CudaBackend.stageOut( a )
        {
            ret null
        }
        Int32 n = a._data.length
        Int64 dst = CudaBackend.allocDevRaw( n * 4, a._device )
        if dst == 0
        {
            ret null
        }
        CudaKernelArgs args = CudaKernelArgs( 4 )
        args.addPtr( dst )
        args.addPtr( a._devBlock )
        args.addF32( k )
        args.addI32( n )
        bool ok = CudaBackend.launchFlat( CudaBackend._f_scale, n, 256, args.paramsBlock )
        args.free()
        if !ok
        {
            CudaBackend.freeDevRaw( dst, n * 4, a._device )
            ret null
        }
        ret CudaBackend.deviceTensor( a._shape.clone(), a._device, dst )
    }

    # 逐元素一元：op 0=relu 1=sigmoid 2=tanh 3=exp
    static Tensor unaryGpu( Tensor a, Int32 op )
    {
        if !CudaBackend.kernelsReady()
        {
            ret null
        }
        if !CudaBackend.stageOut( a )
        {
            ret null
        }
        Int32 n = a._data.length
        Int64 dst = CudaBackend.allocDevRaw( n * 4, a._device )
        if dst == 0
        {
            ret null
        }
        CudaKernelArgs args = CudaKernelArgs( 4 )
        args.addPtr( dst )
        args.addPtr( a._devBlock )
        args.addI32( n )
        args.addI32( op )
        bool ok = CudaBackend.launchFlat( CudaBackend._f_unary, n, 256, args.paramsBlock )
        args.free()
        if !ok
        {
            CudaBackend.freeDevRaw( dst, n * 4, a._device )
            ret null
        }
        ret CudaBackend.deviceTensor( a._shape.clone(), a._device, dst )
    }

    # 全量归约：ret[0] = sum(a)（单线程标量序 → 与 L0 逐位一致）。
    # 形态对齐 Backends.simdSumArray（1 元素数组承载，null = 回落）
    static Array<Float32> sumGpu( Tensor a )
    {
        if !CudaBackend.kernelsReady()
        {
            ret null
        }
        if !CudaBackend.stageOut( a )
        {
            ret null
        }
        Int32 n = a._data.length
        Int64 dst = CudaBackend.allocDevRaw( 4, a._device )
        if dst == 0
        {
            ret null
        }
        CudaKernelArgs args = CudaKernelArgs( 3 )
        args.addPtr( dst )
        args.addPtr( a._devBlock )
        args.addI32( n )
        bool ok = CudaBackend.launchFlat( CudaBackend._f_sum, 1, 1, args.paramsBlock )
        args.free()
        Array<Float32> r = null
        if ok
        {
            Cuda.libDeviceSet( a._device.id )
            Cuda.libCtxSync()
            Int64 blk = Memory.alloc( 4 )
            if blk != 0
            {
                if Cuda.libMemcpyD2H( blk, dst, 4 )
                {
                    r = Array<Float32>( 1 )
                    r[0] = Memory.readFloat32( blk, 0 )
                }
                Memory.free( blk )
            }
        }
        CudaBackend.freeDevRaw( dst, 4, a._device )
        ret r
    }

    # r[m,n] = a[m,k] * b[k,n]（16×16 分块，p 序累加 → 逐位一致）
    static Tensor matmulGpu( Tensor a, Tensor b, Int32 m, Int32 k, Int32 n )
    {
        if !CudaBackend.kernelsReady()
        {
            ret null
        }
        if !CudaBackend.stageOut( a ) || !CudaBackend.stageOut( b )
        {
            ret null
        }
        Int64 dst = CudaBackend.allocDevRaw( m * n * 4, a._device )
        if dst == 0
        {
            ret null
        }
        CudaKernelArgs args = CudaKernelArgs( 6 )
        args.addPtr( dst )
        args.addPtr( a._devBlock )
        args.addPtr( b._devBlock )
        args.addI32( m )
        args.addI32( k )
        args.addI32( n )
        Int32 gx = ( n + 15 ) / 16
        Int32 gy = ( m + 15 ) / 16
        bool ok = CudaBackend.launch2D( CudaBackend._f_mmul, gx, gy, 16, 16, 2048, args.paramsBlock )
        args.free()
        if !ok
        {
            CudaBackend.freeDevRaw( dst, m * n * 4, a._device )
            ret null
        }
        ret CudaBackend.deviceTensor( Shape.matrix( m, n ), a._device, dst )
    }

    # 逐行 softmax（与 L0 同算法结构；exp 容差验收）
    static Tensor softmaxGpu( Tensor a, Int32 rows, Int32 cols )
    {
        if !CudaBackend.kernelsReady()
        {
            ret null
        }
        if !CudaBackend.stageOut( a )
        {
            ret null
        }
        Int64 dst = CudaBackend.allocDevRaw( rows * cols * 4, a._device )
        if dst == 0
        {
            ret null
        }
        CudaKernelArgs args = CudaKernelArgs( 4 )
        args.addPtr( dst )
        args.addPtr( a._devBlock )
        args.addI32( rows )
        args.addI32( cols )
        bool ok = CudaBackend.launchFlat( CudaBackend._f_smx, rows, 32, args.paramsBlock )
        args.free()
        if !ok
        {
            CudaBackend.freeDevRaw( dst, rows * cols * 4, a._device )
            ret null
        }
        ret CudaBackend.deviceTensor( Shape.matrix( rows, cols ), a._device, dst )
    }

    # fillValue 设备版（§5.2.4；0 值由 Tensor 侧走 memset8）
    static bool fillGpu( Tensor t, Float32 v )
    {
        if !CudaBackend.kernelsReady() || t._devBlock == 0
        {
            ret false
        }
        CudaKernelArgs args = CudaKernelArgs( 3 )
        args.addPtr( t._devBlock )
        args.addF32( v )
        args.addI32( t._data.length )
        bool ok = CudaBackend.launchFlat( CudaBackend._f_fill, t._data.length, 256, args.paramsBlock )
        args.free()
        ret ok
    }

    # scaleInPlace 设备原地版（§5.2.4）：stageOut 先行（S1→S0）→
    # ESCALE dst==src → 出口 S2，不过主机
    static bool scaleInPlaceGpu( Tensor t, Float32 k )
    {
        if !CudaBackend.kernelsReady() || t._devBlock == 0
        {
            ret false
        }
        if !CudaBackend.stageOut( t )
        {
            ret false
        }
        CudaKernelArgs args = CudaKernelArgs( 4 )
        args.addPtr( t._devBlock )
        args.addPtr( t._devBlock )
        args.addF32( k )
        args.addI32( t._data.length )
        bool ok = CudaBackend.launchFlat( CudaBackend._f_scale, t._data.length, 256, args.paramsBlock )
        args.free()
        if ok
        {
            t._hostDirty = false
            t._devDirty = true
        }
        ret ok
    }
}
