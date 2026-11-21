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
    # S2 时触发下载协议（§5.2.2：P3 前全同步 + P4 循环回填）；CPU 张量空操作
    void ensureHostFresh()
    {
        if this._devDirty
        {
            CudaBackend.downloadFlow( this )
        }
    }

    # ── 设备迁移（§5.3 分配协议）────────────────────────
    # to(device)：跨设备移动返回新张量（源不动，§5.2.5 唯一跨设备入口）；
    # 同设备无变化返回自身（对齐 torch.Tensor.to 的 no-op 短路）。
    # P2A：GPU 实通路（§5.3 立即分配：预检+记账 + P1+P2 上传 → S0）；
    # 设备→cpu 下载进新张量（源影子不动）；非 GPU kind 显式报错
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
            # 设备 -> cpu：下载协议（§5.2.2 P3+P4），源张量不动
            Tensor r = Tensor( this._shape.clone() )
            r._dtype = this._dtype
            this.ensureHostFresh()
            for i = 0, i < this._data.length, i++
            {
                r._data[i] = this._data[i]
            }
            ret r
        }
        # 同设备 no-op 短路
        if !srcCpu
        {
            if this._device.sameDevice( target )
            {
                ret this
            }
        }
        # cpu -> 设备：v1 实通路仅 GPU；§5.3 立即分配（预检+记账）+上传
        if target.kind != EDeviceKind.GPU
        {
            throw BackendError.UnsupportedOp
        }
        if !Backends.available( target.kind )
        {
            throw BackendError.Unavailable
        }
        if this._dtype != EDtype.F32
        {
            throw BackendError.UnsupportedOp
        }
        Int32 bytes = this._data.length * 4
        Int64 ptr = CudaBackend.allocDevRaw( bytes, target )
        if ptr == 0
        {
            throw BackendError.Unavailable
        }
        # OQ-1：源数组 data 指针直接 H2D（零复制零循环）；出口张量置 S2
        # （dev 权威）——_data 为零填充占位，首次读值时 D2H 直写填充，
        # 消除旧路径的 O(n) 主机复制循环（h2d_bench：1024² 单张量省 ~1.9s）
        if !CudaBackend.uploadInto( ptr, this._data, bytes )
        {
            CudaBackend.freeDevRaw( ptr, bytes, target )
            throw BackendError.Unavailable
        }
        Tensor r = Tensor()
        r._shape = this._shape.clone()
        r._strides = r._shape.strides()
        r._dtype = this._dtype
        r._data = Array<Float32>( this._data.length )
        r._device = target
        r._devBlock = ptr
        r._hostDirty = false
        r._devDirty = true
        ret r
    }

    Tensor cpu() throws
    {
        ret this.to( Device.cpu() )
    }

    # 释放设备侧影子（§5.3 释放协议）；CPU 张量为空操作。
    # SL 无析构钩子：长期驻留进程必须显式调用（OQ-8）
    void freeDevice()
    {
        if this._devBlock != 0 && this._device != null
        {
            CudaBackend.freeDevRaw( this._devBlock, this._data.length * 4, this._device )
        }
        this._devBlock = 0
        this._devDirty = false
        this._hostDirty = true
    }

    # 张量是否驻留 GPU（算子设备分支判定；位置驱动——已上设备的张量
    # 不再受 Backends 开关影响，开关只门 to() 入口）
    bool onGpu()
    {
        if this._device == null
        {
            ret false
        }
        ret this._device.isGpu()
    }

    # 双侧同 GPU 同卡驻留（设备算子前置；跨设备/混合 v1 走 CPU 合并）
    bool sameGpuDevice( Tensor other )
    {
        if other == null
        {
            ret false
        }
        if !this.onGpu()
        {
            ret false
        }
        if other._device == null
        {
            ret false
        }
        ret this._device.sameDevice( other._device )
    }

    # 设备算子的 CPU 合并回落出口（§5.2.5：输出设备 = 输入设备）：
    # 结果挂源设备、主机权威（S1，devBlock=0 惰性上传）——值正确；
    # §5.2.5 的混合设备 BackendError 语义待算子 throws 通道扩展（v2）
    Tensor _tagOut( Tensor r )
    {
        if this._device != null
        {
            r._device = this._device
            r._hostDirty = true
        }
        ret r
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
        # 设备分支（§5.2.4）：同设备 D2D（P5，不过主机），出口 S2
        if this.onGpu() && this._devBlock != 0
        {
            if CudaBackend.stageOut( this )
            {
                Int64 cbBytes = this._data.length * 4
                Int64 cb = CudaBackend.allocDevRaw( cbBytes, this._device )
                if cb != 0
                {
                    Cuda.libDeviceSet( this._device.id )
                    if Cuda.libMemcpyD2D( cb, this._devBlock, cbBytes )
                    {
                        ret CudaBackend.deviceTensor( this._shape.clone(), this._device, cb )
                    }
                    CudaBackend.freeDevRaw( cb, cbBytes, this._device )
                }
            }
        }
        this.ensureHostFresh()
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
        # 设备分支（§5.2.4）：双侧同 GPU 同形 → D2D（P5），出口 S2
        if this.onGpu() && this._devBlock != 0 && src != null
        {
            if src.onGpu() && this._device.sameDevice( src._device )
            {
                if this._data.length == src._data.length
                {
                    if CudaBackend.stageOut( src )
                    {
                        Int64 cpBytes = this._data.length * 4
                        Cuda.libDeviceSet( this._device.id )
                        if Cuda.libMemcpyD2D( this._devBlock, src._devBlock, cpBytes )
                        {
                            this._hostDirty = false
                            this._devDirty = true
                            ret
                        }
                    }
                }
            }
        }
        this.ensureHostFresh()
        src.ensureHostFresh()
        for i = 0, i < this._data.length, i++
        {
            this._data[i] = src._data[i]
        }
        this._hostDirty = true
    }

    void fillValue( Float32 value )
    {
        # 设备分支（§5.2.4）：纯写不 stageOut——整块覆写后主机侧自然
        # 过期；0 值走 memset8（P5），非 0 走 TFILL kernel；出口 S2
        if this.onGpu() && this._devBlock != 0
        {
            if value == 0.0f
            {
                Int64 zb = this._data.length * 4
                Cuda.libDeviceSet( this._device.id )
                if Cuda.libMemset8( this._devBlock, 0, zb )
                {
                    this._hostDirty = false
                    this._devDirty = true
                    ret
                }
            }
            else
            {
                if CudaBackend.fillGpu( this, value )
                {
                    this._hostDirty = false
                    this._devDirty = true
                    ret
                }
            }
        }
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
        # 设备分支（§6.2 EADD）：out 形状==本侧、b 同形/行向量/标量
        # → kernel 内 gid % blen 广播映射（§5.2.6）
        if this.sameGpuDevice( b ) && this._dtype == EDtype.F32 && b._dtype == EDtype.F32
        {
            if broad.size() == this._data.length
            {
                Int32 blen = b._data.length
                bool okShape = blen == this._data.length
                if !okShape
                {
                    if blen == 1
                    {
                        okShape = true
                    }
                }
                if !okShape
                {
                    if b.rank() == 2
                    {
                        if b.rows() == 1
                        {
                            okShape = true
                        }
                    }
                }
                if okShape
                {
                    Tensor g = CudaBackend.elemwise( this, b, 0, blen )
                    if g != null
                    {
                        ret g
                    }
                }
            }
        }
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, this.pick( idx ) + b.pick( idx ) )
        }
        ret this._tagOut( r )
    }

    Tensor sub( Tensor b )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        # 设备分支（§6.2 ESUB）：同 add 的形态判定（op=1）
        if this.sameGpuDevice( b ) && this._dtype == EDtype.F32 && b._dtype == EDtype.F32
        {
            if broad.size() == this._data.length
            {
                Int32 blen = b._data.length
                bool okShape = blen == this._data.length
                if !okShape
                {
                    if blen == 1
                    {
                        okShape = true
                    }
                }
                if !okShape
                {
                    if b.rank() == 2
                    {
                        if b.rows() == 1
                        {
                            okShape = true
                        }
                    }
                }
                if okShape
                {
                    Tensor g = CudaBackend.elemwise( this, b, 1, blen )
                    if g != null
                    {
                        ret g
                    }
                }
            }
        }
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, this.pick( idx ) - b.pick( idx ) )
        }
        ret this._tagOut( r )
    }

    Tensor mul( Tensor b )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        # 设备分支（§6.2 EMUL）：同 add 的形态判定（op=2）
        if this.sameGpuDevice( b ) && this._dtype == EDtype.F32 && b._dtype == EDtype.F32
        {
            if broad.size() == this._data.length
            {
                Int32 blen = b._data.length
                bool okShape = blen == this._data.length
                if !okShape
                {
                    if blen == 1
                    {
                        okShape = true
                    }
                }
                if !okShape
                {
                    if b.rank() == 2
                    {
                        if b.rows() == 1
                        {
                            okShape = true
                        }
                    }
                }
                if okShape
                {
                    Tensor g = CudaBackend.elemwise( this, b, 2, blen )
                    if g != null
                    {
                        ret g
                    }
                }
            }
        }
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, this.pick( idx ) * b.pick( idx ) )
        }
        ret this._tagOut( r )
    }

    Tensor div( Tensor b )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        # 设备分支（§6.2 EDIV）：同 add 的形态判定（op=3）
        if this.sameGpuDevice( b ) && this._dtype == EDtype.F32 && b._dtype == EDtype.F32
        {
            if broad.size() == this._data.length
            {
                Int32 blen = b._data.length
                bool okShape = blen == this._data.length
                if !okShape
                {
                    if blen == 1
                    {
                        okShape = true
                    }
                }
                if !okShape
                {
                    if b.rank() == 2
                    {
                        if b.rows() == 1
                        {
                            okShape = true
                        }
                    }
                }
                if okShape
                {
                    Tensor g = CudaBackend.elemwise( this, b, 3, blen )
                    if g != null
                    {
                        ret g
                    }
                }
            }
        }
        Tensor r = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, this.pick( idx ) / b.pick( idx ) )
        }
        ret this._tagOut( r )
    }

    Tensor scale( Float32 k )
    {
        # 设备分支（§6.2 ESCALE）
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.scaleGpu( this, k )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = this._data[i] * k
        }
        ret this._tagOut( r )
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
        # 设备分支（§6.2 MMUL）：每线程一输出、p 序标量累加（禁 fma）
        # → 与 L0 逐位一致
        if this.sameGpuDevice( b ) && this._dtype == EDtype.F32 && b._dtype == EDtype.F32
        {
            if this.rank() == 2 && b.rank() == 2
            {
                Tensor g = CudaBackend.matmulGpu( this, b, m, k, n )
                if g != null
                {
                    ret g
                }
            }
        }
        # L1 SIMD 分派（§6.1.1）：CPU 稠密 f32 且规模过阈值走原生
        # kernel（Tier-1 位级一致）；未启用 / 失败回落下方 L0 循环
        if this._device == null && this._dtype == EDtype.F32
        {
            if b._device == null && b._dtype == EDtype.F32
            {
                if this.rank() == 2 && b.rank() == 2
                {
                    if Backends.simdMatmulOn( m, k, n )
                    {
                        Array<Float32> rd = Backends.simdMatmulArray( this._data, b._data, m, n, k )
                        if rd != null
                        {
                            Tensor t = Tensor()
                            t._shape = Shape.matrix( m, n )
                            t._strides = t._shape.strides()
                            t._data = rd
                            ret t
                        }
                    }
                }
            }
        }
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
        ret this._tagOut( r )
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
        # 设备原地分支（§5.2.4）：stageOut 先行（S1→S0）→ ESCALE
        # dst==src → 出口 S2，不过主机
        if this.onGpu() && this._dtype == EDtype.F32
        {
            if CudaBackend.scaleInPlaceGpu( this, k )
            {
                ret
            }
        }
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
        # 设备分支（§6.2 RSUM）：单线程标量序累加 → 与 L0 逐位一致
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Array<Float32> rd = CudaBackend.sumGpu( this )
            if rd != null
            {
                ret rd[0]
            }
        }
        this.ensureHostFresh()
        # L1 SIMD 分派（§6.1.1）：CPU f32 且元素数过阈值走原生 kernel
        # （标量序 C 循环，Tier-1 位级一致）；失败回落下方 L0 循环
        if this._device == null && this._dtype == EDtype.F32
        {
            if Backends.simdSumOn( this._data.length )
            {
                Array<Float32> rd = Backends.simdSumArray( this._data )
                if rd != null
                {
                    ret rd[0]
                }
            }
        }
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
        # 设备分支（§6.2 t_unary op=3；GPU 无 CRT expf → 容差验收）
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 3 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.exp( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor log()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.safeLog( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor sqrt()
    {
        # 设备分支（§6.2 t_unary op=5，逐位 sqrt.rn）
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 5 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.sqrt( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor abs()
    {
        # 设备分支（§6.2 t_unary op=9，位级一致：符号位清零）
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 9 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.abs( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor pow( Float32 p )
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.pow( this._data[i], p )
        }
        ret this._tagOut( r )
    }

    Tensor clamp( Float32 lo, Float32 hi )
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.clamp( this._data[i], lo, hi )
        }
        ret this._tagOut( r )
    }

    # ── 基础逐元素补全（PyTorch ElementwiseOps 对齐，P2 期）──────
    # GPU 分支走 t_unary op 表（CudaBackend.sl ptxUnary 注释对齐）；
    # 低频函数（sin/cos/…/fmod/激活补充）v1 仅 L0，GPU 驻留张量经
    # ensureHostFresh 读迫同步后在主机算，出口 _tagOut 保持设备语义。

    # 1/x（CPU：0 → 0 防 VM 除零；GPU op4 div.rn：0 → +inf。
    # 非零值两路逐位一致，仅 x=0 边缘有此差异——测试避开 0 输入）
    Tensor reciprocal()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 4 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.reciprocal( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # 1/√x（approx 容差）
    Tensor rsqrt()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 6 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.rsqrt( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # x²
    Tensor square()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 15 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.square( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # 2^x
    Tensor exp2()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 8 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.exp2( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # log₂x（approx 容差）
    Tensor log2()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 7 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.log2( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # ⌊x⌋（逐位）
    Tensor floor()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 11 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.floor( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # ⌈x⌉（逐位）
    Tensor ceil()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 12 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.ceil( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # 四舍五入（逐位）
    Tensor round()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 13 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.round( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # 符号（-1/0/1；逐位）
    Tensor sign()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 14 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.sign( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # x - ⌊x⌋
    Tensor frac()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.fract( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # e^x - 1
    Tensor expm1()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.expm1( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # ln(1+x)
    Tensor log1p()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.log1p( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # 浮点取余 this mod b（广播；结果符号随被除数，同 C fmod）
    Tensor fmod( Tensor b )
    {
        Shape broad = Shape.broadcastShape( this._shape, b.shape() )
        Tensor r = Tensor( broad )
        this.ensureHostFresh()
        b.ensureHostFresh()
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            r.setAt( f, TensorMath.fmod( this.pick( idx ), b.pick( idx ) ) )
        }
        ret this._tagOut( r )
    }

    # ── 三角 / 双曲（L0； Mathf 同名直通）─────────────────
    Tensor sin()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.sin( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor cos()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.cos( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor tan()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.tan( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor sinh()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.sinh( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor cosh()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = Mathf.cosh( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # ── 激活补充（gelu/silu 带 GPU；其余 L0）──────────────

    # SiLU / Swish：x·sigmoid(x)
    Tensor silu()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 16 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.silu( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # GELU（tanh 近似式，同 L0 TensorMath.gelu）
    Tensor gelu()
    {
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 17 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.gelu( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor softplus()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.softplus( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor leakyRelu( Float32 alpha )
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.leakyRelu( this._data[i], alpha )
        }
        ret this._tagOut( r )
    }

    Tensor elu( Float32 alpha )
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.elu( this._data[i], alpha )
        }
        ret this._tagOut( r )
    }

    Tensor mish()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.mish( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor relu()
    {
        # 设备分支（§6.2 t_unary op=0；纯比较语义 → 逐位一致）
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 0 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.relu( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor sigmoid()
    {
        # 设备分支（§6.2 t_unary op=1；容差验收）
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 1 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.sigmoid( this._data[i] )
        }
        ret this._tagOut( r )
    }

    Tensor tanh()
    {
        # 设备分支（§6.2 t_unary op=2；容差验收）
        if this.onGpu() && this._dtype == EDtype.F32
        {
            Tensor g = CudaBackend.unaryGpu( this, 2 )
            if g != null
            {
                ret g
            }
        }
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        for i = 0, i < this._data.length, i++
        {
            r._data[i] = TensorMath.tanh( this._data[i] )
        }
        ret this._tagOut( r )
    }

    # 对最后一维做 softmax（逐行）
    Tensor softmax()
    {
        # 设备分支（§6.2 SMAX）：每线程一行，max→exp-sum→归一三遍
        # 标量序（与 L0 同算法结构；exp 容差验收）
        if this.onGpu() && this._dtype == EDtype.F32
        {
            if this.rank() == 2
            {
                int gm = this._shape.dims[0]
                int gn = this.cols()
                Tensor g = CudaBackend.softmaxGpu( this, gm, gn )
                if g != null
                {
                    ret g
                }
            }
        }
        # L1 SIMD 分派（§6.1.1）：CPU 稠密 f32 2D 且规模过阈值走原生
        # kernel（exp 同 CRT expf，Tier-1 位级一致）；失败回落下方 L0
        if this._device == null && this._dtype == EDtype.F32
        {
            if this.rank() == 2
            {
                int sm = this._shape.dims[0]
                int sn = this.cols()
                if Backends.simdSoftmaxOn( sm, sn )
                {
                    Array<Float32> rd = Backends.simdSoftmaxArray( this._data, sm, sn )
                    if rd != null
                    {
                        Tensor t = Tensor()
                        t._shape = Shape.matrix( sm, sn )
                        t._strides = t._shape.strides()
                        t._data = rd
                        ret t
                    }
                }
            }
        }
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
        ret this._tagOut( r )
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
        # 设备分支（§6.2 t_max，op=5；NaN 语义与 L0 同：取非 NaN 侧）
        if this.sameGpuDevice( b ) && this._dtype == EDtype.F32 && b._dtype == EDtype.F32
        {
            Shape broad = Shape.broadcastShape( this._shape, b.shape() )
            if broad != null
            {
                if broad.size() == this._data.length
                {
                    Int32 blen = b._data.length
                    bool okShape = blen == this._data.length
                    if !okShape
                    {
                        if blen == 1
                        {
                            okShape = true
                        }
                    }
                    if !okShape
                    {
                        if b.rank() == 2
                        {
                            if b.rows() == 1
                            {
                                okShape = true
                            }
                        }
                    }
                    if okShape
                    {
                        Tensor g = CudaBackend.elemwise( this, b, 5, blen )
                        if g != null
                        {
                            ret g
                        }
                    }
                }
            }
        }
        ret this._compareWith( b, 6 )
    }

    Tensor minimum( Tensor b )
    {
        # 设备分支（§6.2 t_min，op=4）
        if this.sameGpuDevice( b ) && this._dtype == EDtype.F32 && b._dtype == EDtype.F32
        {
            Shape broad = Shape.broadcastShape( this._shape, b.shape() )
            if broad != null
            {
                if broad.size() == this._data.length
                {
                    Int32 blen = b._data.length
                    bool okShape = blen == this._data.length
                    if !okShape
                    {
                        if blen == 1
                        {
                            okShape = true
                        }
                    }
                    if !okShape
                    {
                        if b.rank() == 2
                        {
                            if b.rows() == 1
                            {
                                okShape = true
                            }
                        }
                    }
                    if okShape
                    {
                        Tensor g = CudaBackend.elemwise( this, b, 4, blen )
                        if g != null
                        {
                            ret g
                        }
                    }
                }
            }
        }
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

    # ── 归约扩展（PyTorch ReductionOps 对齐，L0）──────────
    # （全局 argmax/argmin 已有上方 int 版本，此处不重复）

    # 累积乘（扁平序）：r[i] = x[0]*x[1]*…*x[i]
    Tensor cumprod()
    {
        this.ensureHostFresh()
        Tensor r = Tensor( this._shape.clone() )
        if this._data.length == 0
        {
            ret r
        }
        Float32 acc = 1.0f
        for i = 0, i < this._data.length, i++
        {
            acc = acc * this._data[i]
            r._data[i] = acc
        }
        ret this._tagOut( r )
    }

    # 沿 axis 累积乘（keepdim 形态同 sumAlong）
    Tensor cumprodAlong( Int32 axis )
    {
        this.ensureHostFresh()
        Int32 m = this._shape.dims[0]
        Int32 n = this.cols()
        if axis == 1 && this.rank() == 2
        {
            Tensor r = Tensor( m, n )
            for i = 0, i < m, i++
            {
                Float32 acc = 1.0f
                for j = 0, j < n, j++
                {
                    acc = acc * this.at( i, j )
                    r.setAt( i, j, acc )
                }
            }
            ret this._tagOut( r )
        }
        if axis == 0 && this.rank() == 2
        {
            Tensor r = Tensor( m, n )
            for j = 0, j < n, j++
            {
                Float32 acc = 1.0f
                for i = 0, i < m, i++
                {
                    acc = acc * this.at( i, j )
                    r.setAt( i, j, acc )
                }
            }
            ret this._tagOut( r )
        }
        ret this.cumprod()
    }

    # 非零元素计数
    Int32 countNonZero()
    {
        this.ensureHostFresh()
        Int32 c = 0
        for i = 0, i < this._data.length, i++
        {
            if this._data[i] != 0.0f
            {
                c += 1
            }
        }
        ret c
    }

    # ── 代数（L0）──────────────────────────────────────────

    # 向量点积（1D；长度须一致）
    Float32 dot( Tensor b )
    {
        this.ensureHostFresh()
        b.ensureHostFresh()
        if this._data.length != b._data.length
        {
            ret 0.0f
        }
        Float32 acc = 0.0f
        for i = 0, i < this._data.length, i++
        {
            acc = acc + this._data[i] * b._data[i]
        }
        ret acc
    }

    # 外积：this[n] × b[m] -> [n,m]
    Tensor outer( Tensor b )
    {
        this.ensureHostFresh()
        b.ensureHostFresh()
        Int32 n = this._data.length
        Int32 m = b._data.length
        Tensor r = Tensor( n, m )
        for i = 0, i < n, i++
        {
            for j = 0, j < m, j++
            {
                r.setAt( i, j, this._data[i] * b._data[j] )
            }
        }
        ret r
    }

    # ── 形状操作补全（L0）──────────────────────────────────

    # 去除 axis 维（须为 1）
    Tensor squeeze( Int32 axis )
    {
        Int32 r = this.rank()
        if axis < 0 || axis >= r
        {
            ret null
        }
        if this._shape.dims[axis] != 1
        {
            ret null
        }
        Array<Int32> nd = Array<Int32>( r - 1 )
        Int32 k = 0
        for i = 0, i < r, i++
        {
            if i != axis
            {
                nd[k] = this._shape.dims[i]
                k += 1
            }
        }
        this.ensureHostFresh()
        Tensor t = Tensor( Shape( nd ) )
        for i = 0, i < this._data.length, i++
        {
            t._data[i] = this._data[i]
        }
        ret t
    }

    # 在 axis 处插入长度 1 维
    Tensor unsqueeze( Int32 axis )
    {
        Int32 r = this.rank()
        if axis < 0 || axis > r
        {
            ret null
        }
        Array<Int32> nd = Array<Int32>( r + 1 )
        Int32 k = 0
        for i = 0, i < r + 1, i++
        {
            if i == axis
            {
                nd[k] = 1
            }
            else
            {
                if i < axis
                {
                    nd[k] = this._shape.dims[i]
                }
                else
                {
                    nd[k] = this._shape.dims[i - 1]
                }
            }
            k += 1
        }
        this.ensureHostFresh()
        Tensor t = Tensor( Shape( nd ) )
        for i = 0, i < this._data.length, i++
        {
            t._data[i] = this._data[i]
        }
        ret t
    }

    # 沿 axis 维反转（2D：axis 0 上下翻 / axis 1 左右翻）
    Tensor flip( Int32 axis )
    {
        this.ensureHostFresh()
        if this.rank() != 2
        {
            ret null
        }
        Int32 m = this._shape.dims[0]
        Int32 n = this.cols()
        Tensor r = Tensor( m, n )
        if axis == 0
        {
            for i = 0, i < m, i++
            {
                for j = 0, j < n, j++
                {
                    r.setAt( i, j, this.at( m - 1 - i, j ) )
                }
            }
        }
        else
        {
            if axis == 1
            {
                for i = 0, i < m, i++
                {
                    for j = 0, j < n, j++
                    {
                        r.setAt( i, j, this.at( i, n - 1 - j ) )
                    }
                }
            }
            else
            {
                ret null
            }
        }
        ret this._tagOut( r )
    }

    # torch.cat：张量序列沿 axis 拼接（1D axis 0；2D axis 0/1）
    static Tensor cat( Array<Tensor> ts, Int32 axis )
    {
        if ts == null || ts.length == 0
        {
            ret null
        }
        Int32 n = ts.length
        # 1D
        if ts[0].rank() == 1
        {
            if axis != 0
            {
                ret null
            }
            Int32 total = 0
            for k = 0, k < n, k++
            {
                if ts[k].rank() != 1
                {
                    ret null
                }
                total += ts[k]._data.length
            }
            Tensor r1 = Tensor( Shape.vector( total ) )
            Int32 off = 0
            for k = 0, k < n, k++
            {
                ts[k].ensureHostFresh()
                for i = 0, i < ts[k]._data.length, i++
                {
                    r1._data[off + i] = ts[k]._data[i]
                }
                off += ts[k]._data.length
            }
        ret r1
        }
        # 2D
        if ts[0].rank() == 2
        {
            if axis == 0
            {
                Int32 nr = 0
                Int32 nc = ts[0].cols()
                for k = 0, k < n, k++
                {
                    if ts[k].rank() != 2 || ts[k].cols() != nc
                    {
                        ret null
                    }
                    nr += ts[k].rows()
                }
                Tensor r2 = Tensor( nr, nc )
                Int32 off = 0
                for k = 0, k < n, k++
                {
                    ts[k].ensureHostFresh()
                    for i = 0, i < ts[k].rows(), i++
                    {
                        for j = 0, j < nc, j++
                        {
                            r2.setAt( off + i, j, ts[k].at( i, j ) )
                        }
                    }
                    off += ts[k].rows()
                }
        ret r2
            }
            if axis == 1
            {
                Int32 nr = ts[0].rows()
                Int32 nc = 0
                for k = 0, k < n, k++
                {
                    if ts[k].rank() != 2 || ts[k].rows() != nr
                    {
                        ret null
                    }
                    nc += ts[k].cols()
                }
                Tensor r3 = Tensor( nr, nc )
                Int32 off = 0
                for k = 0, k < n, k++
                {
                    ts[k].ensureHostFresh()
                    for i = 0, i < nr, i++
                    {
                        for j = 0, j < ts[k].cols(), j++
                        {
                            r3.setAt( i, off + j, ts[k].at( i, j ) )
                        }
                    }
                    off += ts[k].cols()
                }
        ret r3
            }
        }
        ret null
    }

    # ── 构造器补全（torch.arange / linspace / eye）─────────

    # [0, n) 步长 1
    public static Tensor arange( Int32 n )
    {
        Tensor t = Tensor( Shape.vector( n ) )
        for i = 0, i < n, i++
        {
            t._data[i] = SystemConvertFloat32( i )
        }
        ret t
    }

    # [start, end) 步长 step（step 不可为 0）
    public static Tensor arange( Int32 start, Int32 end, Int32 step )
    {
        if step == 0
        {
            ret null
        }
        Int32 cnt = 0
        if step > 0
        {
            cnt = ( end - start + step - 1 ) / step
        }
        else
        {
            cnt = ( start - end - step - 1 ) / ( -step )
        }
        if cnt <= 0
        {
            ret Tensor( Shape.vector( 0 ) )
        }
        Tensor t = Tensor( Shape.vector( cnt ) )
        Int32 v = start
        for i = 0, i < cnt, i++
        {
            t._data[i] = SystemConvertFloat32( v )
            v += step
        }
        ret t
    }

    # [start, end] 等分 steps 段（含两端）
    public static Tensor linspace( Float32 start, Float32 end, Int32 steps )
    {
        if steps <= 0
        {
            ret null
        }
        Tensor t = Tensor( Shape.vector( steps ) )
        if steps == 1
        {
            t._data[0] = start
            ret t
        }
        Float32 dv = ( end - start ) / SystemConvertFloat32( steps - 1 )
        for i = 0, i < steps, i++
        {
            t._data[i] = start + dv * SystemConvertFloat32( i )
        }
        t._data[steps - 1] = end
        ret t
    }

    # n×n 单位矩阵
    public static Tensor eye( Int32 n )
    {
        Tensor t = Tensor( n, n )
        for i = 0, i < n, i++
        {
            t.setAt( i, i, 1.0f )
        }
        ret t
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
