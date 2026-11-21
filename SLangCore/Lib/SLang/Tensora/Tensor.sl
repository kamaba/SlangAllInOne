import Math;
# Tensor —— 多维张量（Float32，行主序扁平存储）
#
# 存储：_data 一维数组 + _shape（维度）+ _strides（步长）
# 语义：
#   - 逐元素运算均支持广播（add / sub / mul / div）
#   - matmul 目前实现 2D × 2D
#   - 所有 *_InPlace / copyFrom 接口供优化器与反向传播原地更新使用

@Nickname("Tensor")
public class Tensor
{
    Array<Float32> _data = null
    Shape _shape = null
    Array<Int32> _strides = null

    # ── 设备 / 类型字段（设计文档 §4.2 / §5 影子缓冲状态机）──
    # CPU 张量恒为默认值（零成本）：_device=null ≡ cpu，_devBlock=0，
    # _hostDirty/_devDirty 组合出的合法状态见 §5.1（S0/S1/S2 + 禁止态）
    Device _device = null
    Int32 _dtype = EDtype.F32
    Int64 _devBlock = 0
    bool _hostDirty = true
    bool _devDirty = false

    # ── 构造 ─────────────────────────────────────────────
    public void _init_()
    {
        this._shape = Shape.scalar()
        this._strides = this._shape.strides()
        this._data = Array<Float32>( 1 )
        this._data[0] = 0.0f
    }

    public void _init_( Shape shape )
    {
        this._shape = shape
        this._strides = shape.strides()
        this._data = Array<Float32>( shape.size() )
        this.zero()
    }

    public void _init_( Shape shape, Float32 fillValue )
    {
        this._shape = shape
        this._strides = shape.strides()
        this._data = Array<Float32>( shape.size() )
        this.fillValue( fillValue )
    }

    public void _init_( Array<Float32> values, Shape shape )
    {
        this._shape = shape
        this._strides = shape.strides()
        this._data = Array<Float32>( shape.size() )
        for i = 0, i < this._data.length, i++
        {
            this._data[i] = values[i]
        }
    }

    public void _init_( Int32 rows, Int32 cols )
    {
        this._shape = Shape.matrix( rows, cols )
        this._strides = this._shape.strides()
        this._data = Array<Float32>( rows * cols )
        this.zero()
    }

    # ── 属性 ─────────────────────────────────────────────
    get Shape shape()
    {
        ret this._shape
    }

    get int rank()
    {
        ret this._shape.rank()
    }

    get int size()
    {
        ret this._data.length
    }

    get int rows()
    {
        ret this._shape.dims[0]
    }

    get int cols()
    {
        ret this._shape.dims[ this._shape.rank() - 1 ]
    }

    # 保留字修复：data() 是关键字，改名 storage()（KwProbe 实证）
    get Array<Float32> storage()
    {
        this.ensureHostFresh()
        ret this._data
    }

    # ── 设备 / dtype 访问（§4.2）─────────────────────────
    get Device device()
    {
        if this._device == null
        {
            ret Device.cpu()
        }
        ret this._device
    }

    get Int32 dtype()
    {
        ret this._dtype
    }

    # 状态机自省（BackendTest 对 §5.1 不变式 I1-I4 断言用）
    get bool isHostDirty()
    {
        ret this._hostDirty
    }

    get bool isDevDirty()
    {
        ret this._devDirty
    }

    get bool hasDeviceBuffer()
    {
        ret this._devBlock != 0
    }

    # ── 读迫同步钩子（§5.2.3）───────────────────────────
    # P1：无设备影子，恒为空操作；P2 起 S2 时在此触发下载协议
    void ensureHostFresh()
    {
        if this._devDirty
        {
            # P1 不可达：_devBlock==0 ⇒ _devDirty==false（不变式 I3）
            this._devDirty = false
        }
    }

    # ── 设备迁移（§5.3 分配协议）────────────────────────
    # to(device)：跨设备移动返回新张量（源不动，§5.2.5 唯一跨设备入口）；
    # 同设备无变化返回自身（对齐 torch.Tensor.to 的 no-op 短路）。
    # P1：目标设备仅支持 cpu（非 cpu 后端 available()==false，走显式报错）
    Tensor to( Device target ) throws
    {
        if target == null
        {
            target = Device.cpu()
        }
        bool srcCpu = this._device == null
        if !srcCpu
        {
            srcCpu = this._device.isCpu()
        }
        if target.isCpu()
        {
            if srcCpu
            {
                ret this
            }
            # 设备 -> cpu：P2 实现下载协议（§5.2.2）
            throw BackendError.Unavailable
        }
        # cpu -> 设备：P2 实现上传协议（§5.2.1）
        throw BackendError.Unavailable
    }

    Tensor cpu() throws
    {
        ret this.to( Device.cpu() )
    }

    # 释放设备侧影子（§5.3 释放协议）；CPU 张量为空操作。
    # SL 无析构钩子：长期驻留进程必须显式调用（OQ-8）
    void freeDevice()
    {
        this._devBlock = 0
        this._devDirty = false
        this._hostDirty = true
    }

    # ── 索引访问 ─────────────────────────────────────────
    int offset( Array<Int32> index )
    {
        ret this._shape.offset( index )
    }

    Float32 at( int flatIndex )
    {
        this.ensureHostFresh()
        ret this._data[ flatIndex ]
    }

    void setAt( int flatIndex, Float32 value )
    {
        this.ensureHostFresh()
        this._data[ flatIndex ] = value
        this._hostDirty = true
    }

    # get 为保留字语法，全部取值入口统一为 at 家族（KwProbe 实证）
    Float32 at( Array<Int32> index )
    {
        this.ensureHostFresh()
        ret this._data[ this._shape.offset( index ) ]
    }

    void setAt( Array<Int32> index, Float32 value )
    {
        this.ensureHostFresh()
        this._data[ this._shape.offset( index ) ] = value
        this._hostDirty = true
    }

    # get(int) 与已有 at(int flatIndex) 等价，删除避免重载冲突

    Float32 at( int i, int j )
    {
        this.ensureHostFresh()
        ret this._data[ i * this._strides[0] + j * this._strides[1] ]
    }

    void setAt( int i, int j, Float32 value )
    {
        this.ensureHostFresh()
        this._data[ i * this._strides[0] + j * this._strides[1] ] = value
        this._hostDirty = true
    }

    Float32 at( int i, int j, int k )
    {
        this.ensureHostFresh()
        ret this._data[ i * this._strides[0] + j * this._strides[1] + k * this._strides[2] ]
    }

    void setAt( int i, int j, int k, Float32 value )
    {
        this.ensureHostFresh()
        this._data[ i * this._strides[0] + j * this._strides[1] + k * this._strides[2] ] = value
        this._hostDirty = true
    }

    Float32 at( int i, int j, int k, int l )
    {
        this.ensureHostFresh()
        ret this._data[ i * this._strides[0] + j * this._strides[1] + k * this._strides[2] + l * this._strides[3] ]
    }

    void setAt( int i, int j, int k, int l, Float32 value )
    {
        this.ensureHostFresh()
        this._data[ i * this._strides[0] + j * this._strides[1] + k * this._strides[2] + l * this._strides[3] ] = value
        this._hostDirty = true
    }

    # 广播取值：把目标形状的索引映射到本张量
    Float32 pick( Array<Int32> index )
    {
        this.ensureHostFresh()
        int r = this.rank()
        Array<Int32> own = Array<Int32>( r )
        int shift = index.length - r
        for i = 0, i < r, i++
        {
            int src = shift + i
            if src < 0
            {
                own[i] = 0
            }
            else
            {
                if this._shape.dims[i] == 1
                {
                    own[i] = 0
                }
                else
                {
                    own[i] = index[ src ]
                }
            }
        }
        ret this._data[ this._shape.offset( own ) ]
    }

    # ── 拷贝 / 填充 ──────────────────────────────────────
    Tensor clone()
    {
        Tensor r = Tensor( this._shape.clone() )
        r._dtype = this._dtype
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = this._data[i]
        }
        ret r
    }

    void copyFrom( Tensor src )
    {
        this.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            this._data[i] = src._data[i]
        }
        this._hostDirty = true
    }

    void fillValue( Float32 value )
    {
        this.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            this._data[i] = value
        }
        this._hostDirty = true
    }

    void zero()
    {
        this.fillValue( 0.0f )
    }

    bool sameShape( Tensor other )
    {
        ret this._shape.equals( other.shape() )
    }

    # ── 形状变换 ─────────────────────────────────────────
    Tensor reshape( Shape newShape )
    {
        Tensor r = Tensor( newShape )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = this._data[i]
        }
        ret r
    }

    Tensor flatten()
    {
        ret this.reshape( Shape.vector( this._data.length ) )
    }

    # 2D 转置
    Tensor transpose()
    {
        int m = this.rows()
        int n = this.cols()
        Tensor r = Tensor( Shape.matrix( n, m ) )
        for i = 0, i < m, i++
        {
            for j = 0, j < n, j++
            {
                r.setAt( j, i, this.at( i, j ) )
            }
        }
        ret r
    }

    # 通用轴置换：axes 为新的轴顺序
    Tensor transpose( Array<Int32> axes )
    {
        int r = this.rank()
        Array<Int32> newDims = Array<Int32>( r )
        for i = 0, i < r, i++
        {
            newDims[i] = this._shape.dims[ axes[i] ]
        }
        Shape outShape = Shape( newDims )
        Tensor res = Tensor( outShape )
        Array<Int32> src = Array<Int32>( r )
        for f = 0, f < this._data.length, f++
        {
            Array<Int32> idx = this._shape.unflatten( f )
            for a = 0, a < r, a++
            {
                src[ axes[a] ] = idx[a]
            }
            res.setAt( outShape.offset( src ), this._data[f] )
        }
        ret res
    }

    # 沿第 0 维切片 [start, start + count)
    Tensor slice( Int32 start, Int32 count )
    {
        int r = this.rank()
        Array<Int32> newDims = Array<Int32>( r )
        for i = 0, i < r, i++
        {
            newDims[i] = this._shape.dims[i]
        }
        newDims[0] = count
        Shape outShape = Shape( newDims )
        Tensor res = Tensor( outShape )
        int rowSize = this._data.length / this._shape.dims[0]
        int offBase = start * rowSize
        for i = 0, i < count * rowSize, i++
        {
            res._data[i] = this._data[ offBase + i ]
        }
        ret res
    }

    # 取第 r 行（保持二维：1 × cols）
    Tensor row( Int32 r )
    {
        this.ensureHostFresh()
        int n = this.cols()
        Tensor res = Tensor( Shape.matrix( 1, n ) )
        for j = 0, j < n, j++
        {
            res.setAt( 0, j, this.at( r, j ) )
        }
        ret res
    }

    # 写回第 r 行
    void setRow( Int32 r, Tensor v )
    {
        this.ensureHostFresh()
        for j = 0, j < this.cols(), j++
        {
            this.setAt( r, j, v.at( j ) )
        }
        this._hostDirty = true
    }

    # ── 逐元素运算（支持广播）─────────────────────────────
    Tensor add( Tensor b )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, this.pick( idx ) + b.pick( idx ) )
        }
        ret r
    }

    Tensor sub( Tensor b )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, this.pick( idx ) - b.pick( idx ) )
        }
        ret r
    }

    Tensor mul( Tensor b )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, this.pick( idx ) * b.pick( idx ) )
        }
        ret r
    }

    Tensor div( Tensor b )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, this.pick( idx ) / b.pick( idx ) )
        }
        ret r
    }

    Tensor scale( Float32 k )
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = this._data[i] * k
        }
        ret r
    }

    Tensor addScalar( Float32 k )
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = this._data[i] + k
        }
        ret r
    }

    Tensor neg()
    {
        ret this.scale( -1.0f )
    }

    # ── 矩阵乘法（2D × 2D）──────────────────────────────
    Tensor matmul( Tensor b )
    {
        int m = this.rows()
        int k = this.cols()
        int n = b.cols()
        Tensor r = Tensor( Shape.matrix( m, n ) )
        for i = 0, i < m, i++
        {
            for j = 0, j < n, j++
            {
                Float32 acc = 0.0f
                for p = 0, p < k, p++
                {
                    acc = acc + this.at( i, p ) * b.at( p, j )
                }
                r.setAt( i, j, acc )
            }
        }
        ret r
    }

    # ── 原地运算（优化器 / 反传用）───────────────────────
    void addInPlace( Tensor b )
    {
        this.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            this._data[i] = this._data[i] + b.pick( this._shape.unflatten( i ) )
        }
        this._hostDirty = true
    }

    void subInPlace( Tensor b )
    {
        this.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            this._data[i] = this._data[i] - b.pick( this._shape.unflatten( i ) )
        }
        this._hostDirty = true
    }

    void mulInPlace( Tensor b )
    {
        this.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            this._data[i] = this._data[i] * b.pick( this._shape.unflatten( i ) )
        }
        this._hostDirty = true
    }

    void scaleInPlace( Float32 k )
    {
        this.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            this._data[i] = this._data[i] * k
        }
        this._hostDirty = true
    }

    # ── 归约 ─────────────────────────────────────────────
    Float32 sum()
    {
        this.ensureHostFresh()
        Float32 s = 0.0f
        for i = 0, i < this._data.length, i++
        {
            s = s + this._data[i]
        }
        ret s
    }

    Float32 mean()
    {
        this.ensureHostFresh()
        ret this.sum() / SystemConvertFloat32( this._data.length )
    }

    Float32 max()
    {
        this.ensureHostFresh()
        Float32 m = this._data[0]
        for i = 1, i < this._data.length, i++
        {
            if this._data[i] > m
            {
                m = this._data[i]
            }
        }
        ret m
    }

    Float32 min()
    {
        this.ensureHostFresh()
        Float32 m = this._data[0]
        for i = 1, i < this._data.length, i++
        {
            if this._data[i] < m
            {
                m = this._data[i]
            }
        }
        ret m
    }

    int argmax()
    {
        this.ensureHostFresh()
        int best = 0
        Float32 m = this._data[0]
        for i = 1, i < this._data.length, i++
        {
            if this._data[i] > m
            {
                m = this._data[i]
                best = i
            }
        }
        ret best
    }

    int argmin()
    {
        this.ensureHostFresh()
        int best = 0
        Float32 m = this._data[0]
        for i = 1, i < this._data.length, i++
        {
            if this._data[i] < m
            {
                m = this._data[i]
                best = i
            }
        }
        ret best
    }

    # 沿指定轴求和（axis=0 压缩行，axis=1 压缩列）
    # 兼容入口：保持 [1,n]/[m,1] 输出（keepdim 语义，现有层零回归）
    Tensor sumAlong( Int32 axis )
    {
        ret this.reduceAxis( axis, 0, true )
    }

    Tensor meanAlong( Int32 axis )
    {
        ret this.reduceAxis( axis, 1, true )
    }

    Tensor maxAlong( Int32 axis )
    {
        ret this.reduceAxis( axis, 2, true )
    }

    Tensor minAlong( Int32 axis )
    {
        ret this.reduceAxis( axis, 3, true )
    }

    # 沿轴 argmax：返回该轴上最大值下标（F32 承载索引值；
    # I32 dtype 存储实装前以 F32 承载，§4.1 阶段裁剪）
    Tensor argmaxAlong( Int32 axis )
    {
        ret this.reduceAxis( axis, 7, false )
    }

    # PyTorch 语义入口（keepdim=false 降维；对齐 torch.sum(dim=)）
    Tensor sumDim( Int32 axis )
    {
        ret this.reduceAxis( axis, 0, false )
    }

    Tensor meanDim( Int32 axis )
    {
        ret this.reduceAxis( axis, 1, false )
    }

    Tensor maxDim( Int32 axis )
    {
        ret this.reduceAxis( axis, 2, false )
    }

    Tensor minDim( Int32 axis )
    {
        ret this.reduceAxis( axis, 3, false )
    }

    Tensor prodAlong( Int32 axis )
    {
        ret this.reduceAxis( axis, 4, false )
    }

    # 沿轴方差/标准差（无偏估计，除 d-1；d==1 时返回 0）
    Tensor varAlong( Int32 axis )
    {
        Tensor mn = this.reduceAxis( axis, 1, true )
        ret this._varAlongWith( axis, mn )
    }

    Tensor stdAlong( Int32 axis )
    {
        Tensor v = this._varAlongWith( axis, this.reduceAxis( axis, 1, true ) )
        ret v.sqrt()
    }

    # 全量归约（PyTorch 无 dim 形态）
    Float32 prod()
    {
        this.ensureHostFresh()
        Float32 p = 1.0f
        for i = 0, i < this._data.length, i++
        {
            p = p * this._data[i]
        }
        ret p
    }

    # 无偏方差（除 n-1；n==1 时返回 0，对齐 torch.var 默认 unbiased）
    Float32 variance()
    {
        this.ensureHostFresh()
        int n = this._data.length
        if n < 2
        {
            ret 0.0f
        }
        Float32 mn = this.mean()
        Float32 acc = 0.0f
        for i = 0, i < n, i++
        {
            Float32 dv = this._data[i] - mn
            acc = acc + dv * dv
        }
        ret acc / SystemConvertFloat32( n - 1 )
    }

    Float32 std()
    {
        ret Mathf.sqrt( this.variance() )
    }

    # L2 范数
    Float32 norm()
    {
        this.ensureHostFresh()
        Float32 acc = 0.0f
        for i = 0, i < this._data.length, i++
        {
            acc = acc + this._data[i] * this._data[i]
        }
        ret Mathf.sqrt( acc )
    }

    # 任一元素非零（bool 语义以 F32 0/1 承载）
    bool anyNonZero()
    {
        this.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            if this._data[i] != 0.0f
            {
                ret true
            }
        }
        ret false
    }

    bool allNonZero()
    {
        this.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            if this._data[i] == 0.0f
            {
                ret false
            }
        }
        ret true
    }

    # 沿轴前缀和（对齐 torch.cumsum(dim)）
    Tensor cumsumAlong( Int32 axis )
    {
        this.ensureHostFresh()
        int rk = this._shape.rank()
        if axis < 0 || axis >= rk
        {
            ret null
        }
        int d = this._shape.dims[axis]
        int outer = 1
        for i = 0, i < axis, i++
        {
            int di = this._shape.dims[i]
            outer = outer * di
        }
        int tail = 1
        for i = axis + 1, i < rk, i++
        {
            int di2 = this._shape.dims[i]
            tail = tail * di2
        }
        Tensor res = Tensor( this._shape.clone() )
        for oi = 0, oi < outer, oi++
        {
            for ti = 0, ti < tail, ti++
            {
                Float32 acc = 0.0f
                for ri = 0, ri < d, ri++
                {
                    int srcFlat = ( oi * d + ri ) * tail + ti
                    acc = acc + this._data[ srcFlat ]
                    res._data[ srcFlat ] = acc
                }
            }
        }
        ret res
    }

    # ── 通用任意轴归约（修复 OQ-7：旧实现隐含 2D 假设）──
    # mode: 0=sum 1=mean 2=max 3=min 4=prod 5=any 6=all 7=argmax
    # 索引结构：输入 flat = (outer*d + reduceIdx)*tail + tailIdx，
    #           输出 flat = outer*tail + tailIdx（keepdim 仅改形状不改布局）
    # 非法 axis 返回 null（沿用 broadcastShape 现有约定；签名级 throws
    # 改造需沿调用链评审，列入 P1 末统一处理——附录备忘录）
    Tensor reduceAxis( Int32 axis, Int32 mode, bool keepdim )
    {
        this.ensureHostFresh()
        int rk = this._shape.rank()
        if axis < 0 || axis >= rk
        {
            ret null
        }
        int d = this._shape.dims[axis]
        int outer = 1
        for i = 0, i < axis, i++
        {
            int di = this._shape.dims[i]
            outer = outer * di
        }
        int tail = 1
        for i = axis + 1, i < rk, i++
        {
            int di2 = this._shape.dims[i]
            tail = tail * di2
        }
        int outRank = rk - 1
        if keepdim
        {
            outRank = rk
        }
        Array<Int32> outDims = Array<Int32>( outRank )
        int w = 0
        for i = 0, i < rk, i++
        {
            if i != axis
            {
                outDims[w] = this._shape.dims[i]
                w++
            }
            elif keepdim
            {
                outDims[w] = 1
                w++
            }
        }
        # rank-1 且 keepdim=false 时 outRank==0 → 标量形状（dims 空数组）
        Shape outShape = Shape( outDims )
        Tensor res = Tensor( outShape )
        int bestIdx = 0
        for oi = 0, oi < outer, oi++
        {
            for ti = 0, ti < tail, ti++
            {
                Float32 acc = 0.0f
                if mode == 4
                {
                    acc = 1.0f
                }
                elif mode == 6
                {
                    acc = 1.0f
                }
                for ri = 0, ri < d, ri++
                {
                    Float32 v = this._data[ ( oi * d + ri ) * tail + ti ]
                    if mode == 0 || mode == 1
                    {
                        acc = acc + v
                    }
                    elif mode == 2
                    {
                        if ri == 0 || v > acc
                        {
                            acc = v
                        }
                    }
                    elif mode == 3
                    {
                        if ri == 0 || v < acc
                        {
                            acc = v
                        }
                    }
                    elif mode == 4
                    {
                        acc = acc * v
                    }
                    elif mode == 5
                    {
                        if v != 0.0f
                        {
                            acc = 1.0f
                        }
                    }
                    elif mode == 6
                    {
                        if v == 0.0f
                        {
                            acc = 0.0f
                        }
                    }
                    elif mode == 7
                    {
                        if ri == 0 || v > acc
                        {
                            acc = v
                            bestIdx = ri
                        }
                    }
                }
                if mode == 1
                {
                    acc = acc / SystemConvertFloat32( d )
                }
                elif mode == 7
                {
                    acc = SystemConvertFloat32( bestIdx )
                }
                res._data[ oi * tail + ti ] = acc
            }
        }
        ret res
    }

    # varAlong 辅助：以已知均值计算沿轴方差（两次遍历，稳定）
    Tensor _varAlongWith( Int32 axis, Tensor meanKept )
    {
        this.ensureHostFresh()
        int rk = this._shape.rank()
        if axis < 0 || axis >= rk
        {
            ret null
        }
        int d = this._shape.dims[axis]
        int outer = 1
        for i = 0, i < axis, i++
        {
            int di = this._shape.dims[i]
            outer = outer * di
        }
        int tail = 1
        for i = axis + 1, i < rk, i++
        {
            int di2 = this._shape.dims[i]
            tail = tail * di2
        }
        Array<Int32> outDims = Array<Int32>( rk )
        for i = 0, i < rk, i++
        {
            outDims[i] = this._shape.dims[i]
        }
        outDims[axis] = 1
        Tensor res = Tensor( Shape( outDims ) )
        Float32 denom = SystemConvertFloat32( d - 1 )
        if d < 2
        {
            denom = 1.0f
        }
        for oi = 0, oi < outer, oi++
        {
            for ti = 0, ti < tail, ti++
            {
                Float32 mn = meanKept._data[ oi * tail + ti ]
                Float32 acc = 0.0f
                for ri = 0, ri < d, ri++
                {
                    Float32 dv = this._data[ ( oi * d + ri ) * tail + ti ] - mn
                    acc = acc + dv * dv
                }
                if d < 2
                {
                    acc = 0.0f
                }
                res._data[ oi * tail + ti ] = acc / denom
            }
        }
        ret res
    }

    # ── 数学逐元素（AI 常用）─────────────────────────────
    Tensor exp()
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.exp( this._data[i] )
        }
        ret r
    }

    Tensor log()
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.safeLog( this._data[i] )
        }
        ret r
    }

    Tensor sqrt()
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.sqrt( this._data[i] )
        }
        ret r
    }

    Tensor abs()
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.abs( this._data[i] )
        }
        ret r
    }

    Tensor pow( Float32 p )
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.pow( this._data[i], p )
        }
        ret r
    }

    Tensor clamp( Float32 lo, Float32 hi )
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.clamp( this._data[i], lo, hi )
        }
        ret r
    }

    Tensor relu()
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.relu( this._data[i] )
        }
        ret r
    }

    Tensor sigmoid()
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.sigmoid( this._data[i] )
        }
        ret r
    }

    Tensor tanh()
    {
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.tanh( this._data[i] )
        }
        ret r
    }

    # 对最后一维做 softmax（逐行）
    Tensor softmax()
    {
        Tensor r = Tensor( this._shape.clone() )
        int m = this._shape.dims[0]
        int n = this.cols()
        for i = 0, i < m, i++
        {
            Float32 mx = this.at( i, 0 )
            for j = 1, j < n, j++
            {
                if this.at( i, j ) > mx
                {
                    mx = this.at( i, j )
                }
            }
            Float32 denom = 0.0f
            for j = 0, j < n, j++
            {
                denom = denom + TensorMath.exp( this.at( i, j ) - mx )
            }
            for j = 0, j < n, j++
            {
                r.setAt( i, j, TensorMath.exp( this.at( i, j ) - mx ) / denom )
            }
        }
        ret r
    }

    Tensor logSoftmax()
    {
        Tensor r = Tensor( this._shape.clone() )
        int m = this._shape.dims[0]
        int n = this.cols()
        for i = 0, i < m, i++
        {
            Float32 mx = this.at( i, 0 )
            Float32 denom = 0.0f
            for j = 0, j < n, j++
            {
                if this.at( i, j ) > mx
                {
                    mx = this.at( i, j )
                }
            }
            for j = 0, j < n, j++
            {
                denom = denom + TensorMath.exp( this.at( i, j ) - mx )
            }
            Float32 logSum = mx + TensorMath.safeLog( denom )
            for j = 0, j < n, j++
            {
                r.setAt( i, j, this.at( i, j ) - logSum )
            }
        }
        ret r
    }

    # ── 比较算子（广播，输出 0.0/1.0；bool dtype 实装前以 F32 承载）──
    # 内核：mode 0=eq 1=ne 2=gt 3=lt 4=ge 5=le 6=max 7=min
    Tensor _compareWith( Tensor b, Int32 mode )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        if broad == null
        {
            ret null
        }
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            Float32 x = this.pick( idx )
            Float32 y = b.pick( idx )
            Float32 v = 0.0f
            if mode == 0
            {
                if x == y
                {
                    v = 1.0f
                }
            }
            elif mode == 1
            {
                if x != y
                {
                    v = 1.0f
                }
            }
            elif mode == 2
            {
                if x > y
                {
                    v = 1.0f
                }
            }
            elif mode == 3
            {
                if x < y
                {
                    v = 1.0f
                }
            }
            elif mode == 4
            {
                if x >= y
                {
                    v = 1.0f
                }
            }
            elif mode == 5
            {
                if x <= y
                {
                    v = 1.0f
                }
            }
            elif mode == 6
            {
                if x > y
                {
                    v = x
                }
                else
                {
                    v = y
                }
            }
            else
            {
                if x < y
                {
                    v = x
                }
                else
                {
                    v = y
                }
            }
            r.setAt( f, v )
        }
        ret r
    }

    Tensor eq( Tensor b )
    {
        ret this._compareWith( b, 0 )
    }

    Tensor ne( Tensor b )
    {
        ret this._compareWith( b, 1 )
    }

    Tensor gt( Tensor b )
    {
        ret this._compareWith( b, 2 )
    }

    Tensor lt( Tensor b )
    {
        ret this._compareWith( b, 3 )
    }

    Tensor ge( Tensor b )
    {
        ret this._compareWith( b, 4 )
    }

    Tensor le( Tensor b )
    {
        ret this._compareWith( b, 5 )
    }

    Tensor maximum( Tensor b )
    {
        ret this._compareWith( b, 6 )
    }

    Tensor minimum( Tensor b )
    {
        ret this._compareWith( b, 7 )
    }

    # torch.where：cond 非 0 取 a，否则取 b；三形状广播
    public static Tensor where( Tensor cond, Tensor a, Tensor b )
    {
        Shape s1 = Shape.broadcastShape( cond.shape(), a.shape() )
        if s1 == null
        {
            ret null
        }
        Shape broad = Shape.broadcastShape( s1, b.shape() )
        if broad == null
        {
            ret null
        }
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            Float32 c = cond.pick( idx )
            if c != 0.0f
            {
                r.setAt( f, a.pick( idx ) )
            }
            else
            {
                r.setAt( f, b.pick( idx ) )
            }
        }
        ret r
    }

    # ── 静态工厂 ─────────────────────────────────────────
    public static Tensor zeros( Shape shape )
    {
        ret Tensor( shape, 0.0f )
    }

    public static Tensor ones( Shape shape )
    {
        ret Tensor( shape, 1.0f )
    }

    public static Tensor full( Shape shape, Float32 value )
    {
        ret Tensor( shape, value )
    }

    public static Tensor scalar( Float32 value )
    {
        Tensor t = Tensor( Shape.scalar() )
        t.setAt( 0, value )
        ret t
    }

    public static Tensor vector( Array<Float32> values )
    {
        ret Tensor( values, Shape.vector( values.length ) )
    }

    public static Tensor matrix( Array<Float32> values, Int32 rows, Int32 cols )
    {
        ret Tensor( values, Shape.matrix( rows, cols ) )
    }

    public static Tensor identity( Int32 n )
    {
        Tensor t = Tensor( Shape.matrix( n, n ) )
        for i = 0, i < n, i++
        {
            t.setAt( i, i, 1.0f )
        }
        ret t
    }

    # 均匀分布 [0,1)
    public static Tensor random( Shape shape )
    {
        Tensor t = Tensor( shape )
        for i = 0, i < t._data.length, i++
        {
            t._data[i] = Rng.current().nextFloat()
        }
        ret t
    }

    # 标准正态分布
    public static Tensor randn( Shape shape )
    {
        Tensor t = Tensor( shape )
        for i = 0, i < t._data.length, i++
        {
            t._data[i] = Rng.current().nextNormal()
        }
        ret t
    }

    public static Tensor zerosLike( Tensor x )
    {
        ret Tensor.zeros( x.shape() )
    }

    public static Tensor onesLike( Tensor x )
    {
        ret Tensor.ones( x.shape() )
    }

    override string toString()
    {
        this.ensureHostFresh()
        string s = "Tensor" + this._shape.toString() + "["
        int n = this._data.length
        if n > 8
        {
            n = 8
        }
        for i = 0, i < n, i++
        {
            if i > 0
            {
                s = s + ", "
            }
            s = s + SystemConvertString( this._data[i] )
        }
        if this._data.length > n
        {
            s = s + ", ..."
        }
        s = s + "]"
        ret s
    }
}
