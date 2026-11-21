# =========================================================================
# Mem —— Tensora 跨平台内存管理（cpu ↔ gpu / 其它硬件平台数据传递）
#
# 设计目标（用户需求原文）：
#   1) 速度要快：批量搬运全走 C 原生（slm_memcpy / slc_* DMA），经
#      OQ-1 pin 指针直连 SL 数组——零逐元素 SL 循环（h2d_bench：P1/P4
#      逐元素路径 1024² ~3.3s → pin 直搬毫秒级）；
#   2) 查看数据方便：inspect 系（打印首尾切片 + 形状 + 汇总统计，不用
#      全量遍历），hostRead / hostReadI（按裸指针单点读）；
#   3) 手动管理：move（转移所有权）/ copy（拷贝）/ free（删除）显式
#      语义，互不混淆——设备块记账（Device.bytesUsed）随操作即时更新。
#
# 三层数据视图（同 §5.0 存储分层，操作面收口到本类）：
#   - SL 数组（A）：Tensora Tensor._data；pin 得裸指针
#   - 主机原生块（B）：Memory.alloc 系；slm_memcpy 批量拷
#   - 设备显存（C）：CUDA（slc_*，未来 ROCm/NPU/TPU 同构分派）
#
# 用法：
#   Int64 h = Mem.pin( t._data )                  # A 裸指针（勿 free）
#   Mem.copyHost( h, h2, bytes )                  # B/A 间批量拷（C memcpy）
#   Int64 d = Mem.copyToDevice( t, dev )          # A → C（分配+DMA，记账）
#   Mem.copyToHost( d, t2._data )                 # C → A（DMA 直写数组）
#   Mem.copyDevice( d2, d, bytes, dev )           # C → C（D2D，不过主机）
#   Int64 moved = Mem.moveToDevice( t, dev )      # 转移：源释放、块直交
#   Mem.free( d, bytes, dev )                      # 删除：释放+记账回收
#   Mem.inspect( t, "w0" )                        # 查看张量（切片+统计）
#
# 命名空间由 Tensora.jsonc struct 树定义（namespace Tensora / class Mem），
# 文件内不声明 namespace 块（同工程其余文件约定一致）。
# =========================================================================

public class Mem
{
    # ── 低层绑定（sl_mem.c slm_*；函数体 = DLL 不可用兜底）──

    # 主机块批量拷贝（memcpy 语义，重叠区域行为未定义——同 CUDA API）
    @DllStaticImport( "sl_tensora_lib", "slm_memcpy", "i64,i64,i64->i32" )
    public static Int32 libMemcpy( Int64 dst, Int64 src, Int64 bytes )
    {
        ret 0
    }

    # ── A：SL 数组视图 ──────────────────────────────────────

    # 数组裸数据指针（OQ-1：VMArray.data@48；生命周期随数组——勿 free、
    # 勿在数组回收后使用；布局防漂移断言见 CudaBackendTest）
    public static Int64 pin( Array<Float32> values )
    {
        ret Cpu_x64.pinF32( values )
    }

    # ── B：主机原生块操作 ──────────────────────────────────

    # 主机侧批量拷贝（一次 C 调用；dst/src 为数组 pin 指针或 Memory 块）
    public static bool copyHost( Int64 dst, Int64 src, Int64 bytes )
    {
        ret Mem.libMemcpy( dst, src, bytes ) != 0
    }

    # 数组 → 数组批量拷（同长 f32；Tensor.copyFrom 的显式底层形态）
    public static bool copyArray( Array<Float32> dst, Array<Float32> src )
    {
        if dst == null || src == null || dst.length != src.length || dst.length == 0
        {
            ret false
        }
        ret Mem.copyHost( Mem.pin( dst ), Mem.pin( src ), dst.length * 4 )
    }

    # ── C：设备显存操作（CUDA；未来平台经 dev.kind 同构分派）──

    # A → C：分配设备块 + 数组 pin 直传 DMA（分配预检 + Device.bytesUsed
    # 记账；返回 0 = 失败）。张量仍持有主机数据（与 to() 的 S2 语义互补：
    # 本族返回裸块句柄，供手动管理场景使用）。
    public static Int64 copyToDevice( Array<Float32> values, Device dev )
    {
        if values == null || values.length == 0 || dev == null || dev.isCpu()
        {
            ret 0
        }
        Int64 bytes = values.length * 4
        Int64 dst = CudaBackend.allocDevRaw( bytes, dev )
        if dst == 0
        {
            ret 0
        }
        if !CudaBackend.uploadInto( dst, values, values.length * 4 )
        {
            CudaBackend.freeDevRaw( dst, bytes, dev )
            ret 0
        }
        ret dst
    }

    # C → A：DMA 直写数组 data 缓冲（返回 false = 失败）。全同步语义：
    # 内部先 ctx sync（见 CudaBackend.downloadFlow 同约定）。
    public static bool copyToHost( Int64 devPtr, Array<Float32> dst, Device dev )
    {
        if devPtr == 0 || dst == null || dst.length == 0 || dev == null
        {
            ret false
        }
        Cuda.libDeviceSet( dev.id )
        Cuda.libCtxSync()
        Int64 p = Mem.pin( dst )
        if p == 0
        {
            ret false
        }
        ret Cuda.libMemcpyD2H( p, devPtr, dst.length * 4 )
    }

    # C → C：设备内拷贝（D2D，不过主机；未来平台走各自等价原语）
    public static bool copyDevice( Int64 dstPtr, Int64 srcPtr, Int64 bytes, Device dev )
    {
        if dstPtr == 0 || srcPtr == 0 || bytes <= 0 || dev == null
        {
            ret false
        }
        Cuda.libDeviceSet( dev.id )
        ret Cuda.libMemcpyD2D( dstPtr, srcPtr, bytes )
    }

    # ── 手动管理：move / free（转移 / 删除）─────────────────

    # 转移（move）：张量的设备块所有权转交裸句柄形态——源张量回到纯
    # CPU 态（_device=null / devBlock=0 / S1，数据仍在 _data），块由调用
    # 方后续经 Mem.free( ptr, bytes, dev ) 显式释放。to() + freeDevice 的
    # 组合语义一次到位（省一次重传）。返回 0 = 该张量无设备块。
    public static Int64 moveFromDevice( Tensor t )
    {
        if t == null || t._devBlock == 0
        {
            ret 0
        }
        Int64 ptr = t._devBlock
        t._devBlock = 0
        t._devDirty = false
        t._hostDirty = true
        t._device = null
        ret ptr
    }

    # 转移（move）：主机数组 → 设备块（= copyToDevice；块的生命周期
    # 从 SL 数组语义剥离，归调用方手动管理）。别名仅为调用点语义清晰。
    public static Int64 moveToDevice( Array<Float32> values, Device dev )
    {
        ret Mem.copyToDevice( values, dev )
    }

    # 删除（free）：释放设备块 + Device.bytesUsed 记账回收（Mem 族
    # 手动管理块的唯一释放口；Tensor.freeDevice 为张量语义对应物）。
    public static bool free( Int64 devPtr, Int64 bytes, Device dev )
    {
        if devPtr == 0
        {
            ret false
        }
        CudaBackend.freeDevRaw( devPtr, bytes, dev )
        ret true
    }

    # 主机原生块释放（Memory.alloc 系块的删除口；pin 指针勿调！）
    public static bool freeHost( Int64 addr )
    {
        if addr == 0
        {
            ret false
        }
        Memory.free( addr )
        ret true
    }

    # ── 查看数据（inspect 系）──────────────────────────────

    # 按裸指针单点读（f32；i 为元素下标）。C 层 Onnx dataPtr / 任意
    # 主机块指针的查看通路。
    public static Float32 hostRead( Int64 ptr, Int32 i )
    {
        ret Memory.readFloat32( ptr, i * 4 )
    }

    # 按裸指针单点读（i32 位模式；调试 / 位级对照用）
    public static Int32 hostReadI( Int64 ptr, Int32 byteOffset )
    {
        ret SystemPtrReadInt32( ptr, byteOffset )
    }

    # 张量速览：形状 + 首尾 head 个元素 + min/max/mean（不全量打印）。
    # 设备张量自动读迫同步后查看（S2 → S0，一次 DMA）。
    public static void inspect( Tensor t, string tag, Int32 head )
    {
        if t == null
        {
            SystemPrintln( "[" + tag + "] (null tensor)" )
            ret
        }
        t.ensureHostFresh()
        string s = "[" + tag + "] shape=("
        for a = 0, a < t.rank(), a++
        {
            if a > 0
            {
                s = s + ","
            }
            s = s + t._shape.dims[a].toString()
        }
        s = s + ") dtype=f32 head=["
        Int32 n = t._data.length
        Int32 h = head
        if h > n
        {
            h = n
        }
        for i = 0, i < h, i++
        {
            if i > 0
            {
                s = s + ", "
            }
            s = s + t._data[i].toString()
        }
        if n > h
        {
            s = s + ", ..., " + t._data[n - 1].toString()
        }
        s = s + "]"
        Float32 mn = 0.0f
        Float32 mx = 0.0f
        Float32 sm = 0.0f
        if n > 0
        {
            mn = t._data[0]
            mx = t._data[0]
            for i = 0, i < n, i++
            {
                if t._data[i] < mn
                {
                    mn = t._data[i]
                }
                if t._data[i] > mx
                {
                    mx = t._data[i]
                }
                sm = sm + t._data[i]
            }
        }
        s = s + " min=" + mn.toString() + " max=" + mx.toString() + " mean=" + ( sm / SystemConvertFloat32( n ) ).toString()
        SystemPrintln( s )
    }

    # 张量速览（默认头 6 元素）
    public static void inspect( Tensor t, string tag )
    {
        Mem.inspect( t, tag, 6 )
    }

    # 设备块速览：DMA 拷回前 head 个元素查看（手动管理块的检查口，
    # 不物化整个张量）。dev 块指针 + 元素数。
    public static void inspectDevice( Int64 devPtr, Int32 count, Device dev, string tag )
    {
        Int32 h = 6
        if h > count
        {
            h = count
        }
        Array<Float32> tmp = Array<Float32>( h )
        Cuda.libDeviceSet( dev.id )
        Cuda.libCtxSync()
        Int64 p = Mem.pin( tmp )
        if p == 0
        {
            SystemPrintln( "[" + tag + "] (pin failed)" )
            ret
        }
        if !Cuda.libMemcpyD2H( p, devPtr, h * 4 )
        {
            SystemPrintln( "[" + tag + "] (d2h failed)" )
            ret
        }
        string s = "[" + tag + "] dev=" + dev.name + " count=" + count.toString() + " head=["
        for i = 0, i < h, i++
        {
            if i > 0
            {
                s = s + ", "
            }
            s = s + tmp[i].toString()
        }
        s = s + "]"
        SystemPrintln( s )
    }
}
