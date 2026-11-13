# ============================================================================
# RenderData.sl —— P0 数据层三类（纯数据快照，零 FFI 零依赖）
# ----------------------------------------------------------------------------
# SRP「数据与流程分离」第一步（AIPrompt.md P0）：
#   CullingData —— 可视物体快照（CommandBuffer.sortDrawItems 排序后产出，
#                 列与 drawItem 七元组逐一对齐：prog/slot/mesh/texDesc/
#                 transparent/queue + z；P1 剔除阶段直灌本表）
#   FrameData   —— 一帧渲染上下文（时间 / 相机 viewProj / 目标 RT / 清除色 /
#                 环境快照；Pipeline.buildFrameData 采集，P1+ Pass 体系消费）
#   PassData    —— 单个 Pass 的数据描述（输入 / 输出 RT 引用 + 预留参数槽；
#                 P1 RenderPass.execute 填充）
# 三类均为根级类（同 RenderEnvironment 先例，jsonc struct 段注册）；
# 无 import、无 FFI、不依赖 Render / Pipeline（被 Pipeline.sl / CommandBuffer.sl
# 消费，priority 0 先于 Pipeline(2) / CommandBuffer(22) 编译）。
# ============================================================================

# ============================================================================
# CullingData —— 可视物体快照（排序后的 DrawItem 列表，固定容量 + 游标）
# ============================================================================
public class CullingData
{
    # 容量上限（静态常量类风格，同 CommandBuffer.CAP_COMMANDS）
    public static Int32 CAP_ITEMS = 32

    # ── 条目表（与 drawItem 七元组逐列对齐，排序段直灌）──────────
    Array<Int64> _itemProg = null
    Array<Int64> _itemSlot = null
    Array<Int64> _itemMesh = null
    Array<Int64> _itemTex = null
    Array<Int64> _itemTransp = null
    Array<Int64> _itemQueue = null
    Array<Float32> _itemZ = null
    Int32 _count = 0

    public void _init_()
    {
        this._itemProg = Array<Int64>( CullingData.CAP_ITEMS )
        this._itemSlot = Array<Int64>( CullingData.CAP_ITEMS )
        this._itemMesh = Array<Int64>( CullingData.CAP_ITEMS )
        this._itemTex = Array<Int64>( CullingData.CAP_ITEMS )
        this._itemTransp = Array<Int64>( CullingData.CAP_ITEMS )
        this._itemQueue = Array<Int64>( CullingData.CAP_ITEMS )
        this._itemZ = Array<Float32>( CullingData.CAP_ITEMS )
        this._count = 0
    }

    # clear() —— 清空快照（容量保留，只回退游标）
    public void clear()
    {
        this._count = 0
    }

    # addItem(prog, slot, mesh, texDesc, transparent, queue, z) —— 追加一条
    # 可视物体记录（列与 drawItem 七元组一致；容量满返回 false）
    public bool addItem( Int64 prog, Int64 slot, Int64 mesh, Int64 texDesc, Int64 transparent, Int64 queue, Float32 z )
    {
        if this._count >= CullingData.CAP_ITEMS
        {
            ret false
        }
        Int32 i = this._count
        this._itemProg[ i ] = prog
        this._itemSlot[ i ] = slot
        this._itemMesh[ i ] = mesh
        this._itemTex[ i ] = texDesc
        this._itemTransp[ i ] = transparent
        this._itemQueue[ i ] = queue
        this._itemZ[ i ] = z
        this._count = i + 1
        ret true
    }

    # count() —— 当前条目数
    public Int32 count()
    {
        ret this._count
    }

    # ── 列读取（越界防御返回 0）──────────────────────────────────
    public Int64 getProg( Int32 i )
    {
        if i < 0 || i >= this._count
        {
            ret 0
        }
        ret this._itemProg[ i ]
    }

    public Int64 getSlot( Int32 i )
    {
        if i < 0 || i >= this._count
        {
            ret 0
        }
        ret this._itemSlot[ i ]
    }

    public Int64 getMesh( Int32 i )
    {
        if i < 0 || i >= this._count
        {
            ret 0
        }
        ret this._itemMesh[ i ]
    }

    public Int64 getTex( Int32 i )
    {
        if i < 0 || i >= this._count
        {
            ret 0
        }
        ret this._itemTex[ i ]
    }

    public Int64 getTransp( Int32 i )
    {
        if i < 0 || i >= this._count
        {
            ret 0
        }
        ret this._itemTransp[ i ]
    }

    public Int64 getQueue( Int32 i )
    {
        if i < 0 || i >= this._count
        {
            ret 0
        }
        ret this._itemQueue[ i ]
    }

    public Float32 getZ( Int32 i )
    {
        if i < 0 || i >= this._count
        {
            ret 0.0f
        }
        ret this._itemZ[ i ]
    }

    # opaqueCount() —— 不透明条目数（queue < 2500，Geometry 段）
    public Int32 opaqueCount()
    {
        Int32 n = 0
        Int32 i = 0
        while i < this._count
        {
            Int64 qMin = 2500
            if this._itemQueue[ i ] < qMin
            {
                n = n + 1
            }
            i = i + 1
        }
        ret n
    }

    # transparentCount() —— 透明条目数（queue >= 2500，Transparent 段）
    public Int32 transparentCount()
    {
        Int32 n = 0
        Int32 i = 0
        while i < this._count
        {
            Int64 qMin = 2500
            if this._itemQueue[ i ] >= qMin
            {
                n = n + 1
            }
            i = i + 1
        }
        ret n
    }
}

# ============================================================================
# FrameData —— 一帧渲染上下文（buildFrameData 采集，renderCameraScene 消费）
# ============================================================================
public class FrameData
{
    # ── 帧时间与输出目标 ─────────────────────────────────────────
    Float32 time = 0.0f
    Int64 dstPixels = 0

    # ── 相机（P1+ 剔除与 MVP 消费）───────────────────────────────
    bool hasViewProj = false
    Array<Float32> viewProj = null
    Int32 cameraDepth = 0
    Int32 cameraCullMask = -1

    # ── 视口 / 清除 / 渲染目标 ───────────────────────────────────
    Int32 viewportX = 0
    Int32 viewportY = 0
    Int32 viewportW = 0
    Int32 viewportH = 0
    Int32 clearFlags = 3
    Int32 targetHandle = 0
    Int32 targetW = 0
    Int32 targetH = 0
    Float32 clearR = 0.0f
    Float32 clearG = 0.0f
    Float32 clearB = 0.0f
    Float32 clearA = 1.0f

    # ── 环境快照（RenderEnvironment 同源信息）────────────────────
    string envBackend = "none"
    string envRenderer = "unknown"
    string envVersion = "unknown"

    public void _init_()
    {
        this.time = 0.0f
        this.dstPixels = 0
        this.hasViewProj = false
        this.viewProj = Array<Float32>( 16 )
        this.cameraDepth = 0
        this.cameraCullMask = -1
        this.viewportX = 0
        this.viewportY = 0
        this.viewportW = 0
        this.viewportH = 0
        this.clearFlags = 3
        this.targetHandle = 0
        this.targetW = 0
        this.targetH = 0
        this.clearR = 0.0f
        this.clearG = 0.0f
        this.clearB = 0.0f
        this.clearA = 1.0f
        this.envBackend = "none"
        this.envRenderer = "unknown"
        this.envVersion = "unknown"
    }

    # setViewProj(m16) —— 写入 4x4 view-projection（16 元素行/列主序随调用方）
    public bool setViewProj( Array<Float32> m16 )
    {
        if m16 == null
        {
            ret false
        }
        if m16.length < 16
        {
            ret false
        }
        Int32 i = 0
        while i < 16
        {
            this.viewProj[ i ] = m16[ i ]
            i = i + 1
        }
        this.hasViewProj = true
        ret true
    }

    # setViewport(x, y, w, h) —— 视口矩形
    public void setViewport( Int32 x, Int32 y, Int32 w, Int32 h )
    {
        this.viewportX = x
        this.viewportY = y
        this.viewportW = w
        this.viewportH = h
    }

    # setClearColor(r, g, b, a) —— 清除色
    public void setClearColor( Float32 r, Float32 g, Float32 b, Float32 a )
    {
        this.clearR = r
        this.clearG = g
        this.clearB = b
        this.clearA = a
    }

    # setTarget(handle, w, h) —— 渲染目标 RT 引用与尺寸
    public void setTarget( Int32 handle, Int32 w, Int32 h )
    {
        this.targetHandle = handle
        this.targetW = w
        this.targetH = h
    }
}

# ============================================================================
# PassData —— 单个 Pass 的数据描述（输入/输出 RT + 参数槽）
# ============================================================================
public class PassData
{
    # 参数槽容量上限
    public static Int32 CAP_PARAMS = 8

    string name = "pass"
    string inputName = ""
    string outputName = ""
    Int32 passEvent = 0
    Int32 inputHandle = 0
    Int32 outputHandle = 0
    Int32 paramCount = 0
    Array<string> paramName = null
    Array<Float32> paramValue = null

    public void _init_()
    {
        this.name = "pass"
        this.inputName = ""
        this.outputName = ""
        this.passEvent = 0
        this.inputHandle = 0
        this.outputHandle = 0
        this.paramCount = 0
        this.paramName = Array<string>( PassData.CAP_PARAMS )
        this.paramValue = Array<Float32>( PassData.CAP_PARAMS )
    }

    # begin(name, passEvent) —— 开始一次 Pass 数据填写（重置全字段，
    # 参数槽容量保留）
    public void begin( string _name, Int32 _passEvent )
    {
        this.name = _name
        this.inputName = ""
        this.outputName = ""
        this.passEvent = _passEvent
        this.inputHandle = 0
        this.outputHandle = 0
        this.paramCount = 0
    }

    # setInput(name, handle) —— 输入 RT 引用
    public void setInput( string _name, Int32 handle )
    {
        this.inputName = _name
        this.inputHandle = handle
    }

    # setOutput(name, handle) —— 输出 RT 引用
    public void setOutput( string _name, Int32 handle )
    {
        this.outputName = _name
        this.outputHandle = handle
    }

    # setParamFloat(name, value) —— 追加一个 float 参数（槽满返回 false）
    public bool setParamFloat( string _name, Float32 value )
    {
        if this.paramCount >= PassData.CAP_PARAMS
        {
            ret false
        }
        Int32 i = this.paramCount
        this.paramName[ i ] = _name
        this.paramValue[ i ] = value
        this.paramCount = i + 1
        ret true
    }

    # getParamValue(name) —— 按名取 float 参数（未命中返回 0.0f）
    public Float32 getParamValue( string _name )
    {
        Int32 i = 0
        while i < this.paramCount
        {
            if this.paramName[ i ] == _name
            {
                ret this.paramValue[ i ]
            }
            i = i + 1
        }
        ret 0.0f
    }
}
