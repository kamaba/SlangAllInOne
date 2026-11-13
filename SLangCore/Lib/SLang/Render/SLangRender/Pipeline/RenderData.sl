# ============================================================================
# RenderData.sl —— P0 数据层三类（纯数据快照，零 FFI）
# ----------------------------------------------------------------------------
# SRP「数据与流程分离」第一步（AIPrompt.md P0）：
#   CullingData —— 可视物体快照（CommandBuffer.sortDrawItems 排序后产出，
#                 列与 drawItem 七元组逐一对齐：prog/slot/mesh/texDesc/
#                 transparent/queue + z；P1 剔除阶段直灌本表）
#   FrameData   —— 一帧渲染上下文（时间 / 相机 viewProj / 目标 RT / 清除色 /
#                 环境快照；Pipeline.buildFrameData 采集，P1+ Pass 体系消费；
#                 P3 扩展：culling/perDraw/纹理/后处理参数 —— 帧数据完备后
#                 CameraRenderPipeline.Render(FrameData) 即可独立驱动一帧）
#   PassData    —— 单个 Pass 的数据描述（输入 / 输出 RT 引用 + 预留参数槽；
#                 P1 RenderPass.execute 填充）
#   PerDrawData —— P3 新增：PerDraw 槽常量表（mvp16 + color4，固定容量 16 槽；
#                 FrameData 携带，CameraRenderPipeline 预录 setPerDraw 消费）
#   FrameSettings —— P4 新增：帧渲染配置（后处理开关 / 透明排序策略 / 目标
#                 尺寸缩放百分比），挂 Camera（每相机）与 RenderPipelineAsset
#                 （管线默认），CameraRenderPipeline 渲染时消费
# 三类 + 两扩展均为根级类（同 RenderEnvironment 先例，jsonc struct 段注册）；
# 除 Math/Std 模块引用（Float32_4x4 / Color）外零依赖，不依赖 Render /
# Pipeline（被 Pipeline.sl / CommandBuffer.sl 消费，priority 0 先于
# Pipeline(2) / CommandBuffer(22) / Camera(14) 编译）。
# ============================================================================

import Std;
import Math;

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

    # ── P3 帧数据完备扩展（CameraRenderPipeline.Render 消费）──────
    # 可视物体快照（null 或空表 = 无命令流场景，走 legacy runStages）
    public CullingData culling = null
    # PerDraw 槽常量表（mvp16 + color4；槽号与 culling 条目 slot 列对应）
    public PerDrawData perDraw = null
    # 帧级纹理（desc 槽 + RenderTexture 句柄；hasTexture=false 跳过 setTexture）
    public bool hasTexture = false
    public Int32 texSlot = 0
    public Int64 texHandle = 0
    # 后处理参数（与 FrameSettings.postEnabled 相与后生效；enabled=0 纯拷贝）
    public bool postEnabled = false
    public Float32 postBrightness = 1.0f
    public Float32 postSaturation = 1.0f
    public Float32 postVignette = 1.0f

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
        # P3 扩展
        this.culling = CullingData()
        this.perDraw = PerDrawData()
        this.hasTexture = false
        this.texSlot = 0
        this.texHandle = 0
        this.postEnabled = false
        this.postBrightness = 1.0f
        this.postSaturation = 1.0f
        this.postVignette = 1.0f
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

    # setTexture(slot, handle) —— 帧级纹理（P3：CameraRenderPipeline 预录
    # setTexture 消费；slot = 描述符槽，handle = RenderTexture.handle）
    public void setTexture( Int32 slot, Int64 handle )
    {
        this.texSlot = slot
        this.texHandle = handle
        this.hasTexture = handle != 0
    }

    # setPost(enabled, brightness, saturation, vignette) —— 后处理参数
    #（enabled=false 纯拷贝；与 FrameSettings.postEnabled 相与后生效）
    public void setPost( bool enabled, Float32 brightness, Float32 saturation, Float32 vignette )
    {
        this.postEnabled = enabled
        this.postBrightness = brightness
        this.postSaturation = saturation
        this.postVignette = vignette
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

# ============================================================================
# PerDrawData —— PerDraw 槽常量表（P3：FrameData 携带的槽位常量快照）
# ----------------------------------------------------------------------------
# 与 C 侧 SlrPerDraw 槽位世界对齐（mvp16 列主序 + color4；wmat/spec 置零 =
# 无光照参与）。固定容量 16 槽 + used 标记表（游标式，不逐帧增长）；
# CameraRenderPipeline 渲染前预录：used 槽逐个 setPerDraw 进共享命令流，
# DrawItem 经 slot 列引用本槽。默认 mvp=identity / color=white。
# ============================================================================
public class PerDrawData
{
    public static Int32 CAP_SLOTS = 16

    Array<Float32_4x4> _mvp = null
    Array<Color> _color = null
    Array<Int32> _used = null
    Int32 _usedCount = 0

    public void _init_()
    {
        this._mvp = Array<Float32_4x4>( PerDrawData.CAP_SLOTS )
        this._color = Array<Color>( PerDrawData.CAP_SLOTS )
        this._used = Array<Int32>( PerDrawData.CAP_SLOTS )
        Int32 i = 0
        while i < PerDrawData.CAP_SLOTS
        {
            this._mvp[ i ] = Float32_4x4.identity()
            this._color[ i ] = Color.white()
            this._used[ i ] = 0
            i = i + 1
        }
        this._usedCount = 0
    }

    # clear() —— 清空槽表（容量与槽内容保留，只回退 used 标记）
    public void clear()
    {
        Int32 i = 0
        while i < PerDrawData.CAP_SLOTS
        {
            this._used[ i ] = 0
            i = i + 1
        }
        this._usedCount = 0
    }

    # setSlot(slot, mvp, color) —— 写一个 PerDraw 槽（越界返回 false）
    public bool setSlot( Int32 slot, Float32_4x4 mvp, Color color )
    {
        if slot < 0 || slot >= PerDrawData.CAP_SLOTS
        {
            ret false
        }
        if mvp == null
        {
            ret false
        }
        Color c = color
        if c == null
        {
            c = Color.white()
        }
        Int32 idx = slot
        if this._used[ idx ] == 0
        {
            this._usedCount = this._usedCount + 1
        }
        this._mvp[ idx ] = mvp
        this._color[ idx ] = c
        this._used[ idx ] = 1
        ret true
    }

    # isUsed(slot) —— 槽是否已写（越界返回 false）
    public bool isUsed( Int32 slot )
    {
        if slot < 0 || slot >= PerDrawData.CAP_SLOTS
        {
            ret false
        }
        Int32 idx = slot
        ret this._used[ idx ] != 0
    }

    # getMvp(slot) —— 槽 MVP（未写槽返回 identity）
    public Float32_4x4 getMvp( Int32 slot )
    {
        if slot < 0 || slot >= PerDrawData.CAP_SLOTS
        {
            ret Float32_4x4.identity()
        }
        Int32 idx = slot
        ret this._mvp[ idx ]
    }

    # getColor(slot) —— 槽颜色（未写槽返回 white）
    public Color getColor( Int32 slot )
    {
        if slot < 0 || slot >= PerDrawData.CAP_SLOTS
        {
            ret Color.white()
        }
        Int32 idx = slot
        ret this._color[ idx ]
    }

    # usedCount() —— 已写槽数
    public Int32 usedCount()
    {
        ret this._usedCount
    }

    override string toString()
    {
        ret "PerDrawData(slots=" + this._usedCount.toString() + "/" + PerDrawData.CAP_SLOTS.toString() + ")"
    }
}

# ============================================================================
# FrameSettings —— 帧渲染配置（P4：每相机/管线级开关，Unity FrameSettings）
# ----------------------------------------------------------------------------
# 纯数据类（无方法副作用），消费方：
#   Camera.sl        —— 每相机挂一份（camera.frameSettings）
#   RenderPipelineAsset —— 管线默认配置（asset.frameSettings）
#   CameraRenderPipeline —— 渲染时应用：
#     postEnabled                false -> PostProcessPass 走纯拷贝（enabled=0）；
#                                 注意不能整段跳过 Post Pass——C 侧 Blit 固定
#                                 post->final、Readback 固定 final，跳过会读到
#                                 陈旧 rt_post（与 AIPrompt P4 验收 draws=3 的
#                                 预期不同，实现按链路正确性偏离并记录）
#     transparentSortBackToFront false -> CommandBuffer.transparentDescending=
#                                 false，透明段改近->远（z 升序）
#     renderScalePercent         100 -> 全尺寸；50 -> 视口宽高减半（目标 RT
#                                 尺寸缩放；用整数百分比，避免浮点取整 FFI）
#     clearOnBegin               OpaquePass 是否清屏（默认 true）
# ============================================================================
public class FrameSettings
{
    public bool postEnabled = true
    public bool transparentSortBackToFront = true
    public Int32 renderScalePercent = 100
    public bool clearOnBegin = true

    public void _init_()
    {
        this.postEnabled = true
        this.transparentSortBackToFront = true
        this.renderScalePercent = 100
        this.clearOnBegin = true
    }

    # clone() —— 复制一份（相机/资产各自持有时互不影响）
    public FrameSettings clone()
    {
        FrameSettings fs = FrameSettings()
        fs.postEnabled = this.postEnabled
        fs.transparentSortBackToFront = this.transparentSortBackToFront
        fs.renderScalePercent = this.renderScalePercent
        fs.clearOnBegin = this.clearOnBegin
        ret fs
    }

    override string toString()
    {
        string pe = "on"
        if this.postEnabled == false
        {
            pe = "off"
        }
        string so = "back-to-front"
        if this.transparentSortBackToFront == false
        {
            so = "front-to-back"
        }
        ret "FrameSettings(post=" + pe + ", transparent=" + so + ", scale=" + this.renderScalePercent.toString() + "%)"
    }
}
