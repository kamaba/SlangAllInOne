import Std;
import Math;
# Feature.sl —— P2 Feature 机制（HDRP CustomPass / Volume 等价物）
#
# 对应 Unity HDRP Runtime 机制：
#   CustomPass   不改管线代码即可插入的渲染逻辑（本文件 RenderFeature/CustomPass）
#   InjectionPoint 执行注入点（Opaque/Transparent/Post 三对前后隙）
#   Volume       参数化全局覆盖（VolumeProfile 参数结构体 + VolumeStack
#                固定容量 8 层全局覆盖栈，栈顶 enabled 者生效）
#
# 执行链（P1 之上零新增提交路径）：
#   SRP 草稿链（submitPasses 注入点遍历）已移除；Feature 命令预录
#   （preRecord/replayInto）与 Volume 栈消费保持不变
#   （==/!= 整型派发）；Feature.execute 把命令录进 P1 的共享命令流——C 侧
#   slr_cmd_execute_stream 单流整包回放，统计口径与单流直提完全一致
#   （sl_cmd.c 帧级前置 memset：PerDraw 槽/描述符表每次调用重置，全部命令
#   必须同一条流，故 Feature 不单独提交，只往共享流追加）。
#
# 派发约定（同 RenderPass.passType / ECommandOpcode 教训）：不用 virtual
# 重写——子类构造不调 this._init_()（运行期递归地雷），完全手动设字段；
# 基类 execute 按 featureType 字段走 exec* 私有方法；文件级 enum 一律
# 禁用（成员访问解析为「最近类」静态槽地雷），注入点用 Int32 静态常量类。

# EInjectionPoint —— 注入点值表（Int32 静态常量类，非 enum）
public class EInjectionPoint
{
    public static Int32 BeforeOpaque      = 0
    public static Int32 AfterOpaque       = 1
    public static Int32 BeforeTransparent  = 2
    public static Int32 AfterTransparent   = 3
    public static Int32 BeforePost         = 4
    public static Int32 AfterPost          = 5
}

# ============================================================================
# VolumeProfile —— Feature 参数集（Volume 思想的参数结构体，命名 float 槽）
# ============================================================================
public class VolumeProfile
{
    public static Int32 CAP_PARAMS = 8

    public string name = "profile"
    public bool enabled = true
    public Int32 paramCount = 0
    Array<string> _names = null
    Array<Float32> _values = null

    public void _init_()
    {
        this.name = "profile"
        this.enabled = true
        this.paramCount = 0
        this._names = Array<string>( VolumeProfile.CAP_PARAMS )
        this._values = Array<Float32>( VolumeProfile.CAP_PARAMS )
    }

    # setParamFloat(name, value) —— 写参数（存在则更新，不存在则追加；槽满 false）
    public bool setParamFloat( string pname, Float32 value )
    {
        Int32 i = 0
        while i < this.paramCount
        {
            if this._names[ i ] == pname
            {
                this._values[ i ] = value
                ret true
            }
            i = i + 1
        }
        if this.paramCount >= VolumeProfile.CAP_PARAMS
        {
            ret false
        }
        Int32 idx = this.paramCount
        this._names[ idx ] = pname
        this._values[ idx ] = value
        this.paramCount = idx + 1
        ret true
    }

    # getParamFloat(name, defValue) —— 按名取参数（未命中返回默认值）
    public Float32 getParamFloat( string pname, Float32 defValue )
    {
        Int32 i = 0
        while i < this.paramCount
        {
            if this._names[ i ] == pname
            {
                ret this._values[ i ]
            }
            i = i + 1
        }
        ret defValue
    }

    public bool hasParam( string pname )
    {
        Int32 i = 0
        while i < this.paramCount
        {
            if this._names[ i ] == pname
            {
                ret true
            }
            i = i + 1
        }
        ret false
    }

    override string toString()
    {
        ret "VolumeProfile(" + this.name + ", params=" + this.paramCount.toString() + ")"
    }
}

# ============================================================================
# VolumeStack —— 全局参数覆盖栈（固定容量 8 层；栈顶 enabled 的 Profile 生效）
# ----------------------------------------------------------------------------
# 单例实例模式（SL 静态字段可靠
# 形态是「静态自类型引用」，静态 Array 无先例不用）；对外静态转发。
# ============================================================================
public class VolumeStack
{
    public static Int32 CAP_LAYERS = 8

    static VolumeStack _instance = null
    Array<VolumeProfile> _stack = null
    Int32 _top = 0

    public void _init_()
    {
        this._stack = Array<VolumeProfile>( VolumeStack.CAP_LAYERS )
        this._top = 0
    }

    # inst() —— 单例取用
    static VolumeStack inst()
    {
        if VolumeStack._instance == null
        {
            VolumeStack._instance = VolumeStack()
        }
        ret VolumeStack._instance
    }

    # push(profile) —— 压入覆盖层（容量满返回 false）
    public static bool push( VolumeProfile p )
    {
        VolumeStack s = VolumeStack.inst()
        if p == null
        {
            ret false
        }
        if s._top >= VolumeStack.CAP_LAYERS
        {
            ret false
        }
        Int32 idx = s._top
        s._stack[ idx ] = p
        s._top = idx + 1
        ret true
    }

    # pop() —— 弹出栈顶（空栈返回 null）
    public static VolumeProfile pop()
    {
        VolumeStack s = VolumeStack.inst()
        if s._top <= 0
        {
            ret null
        }
        Int32 idx = s._top - 1
        VolumeProfile p = s._stack[ idx ]
        s._top = idx
        ret p
    }

    # resolve() —— 从栈顶向下找首个 enabled 的 Profile（Unity Volume
    # 优先级思想：越晚压栈越优先；全空返回 null）
    public static VolumeProfile resolve()
    {
        VolumeStack s = VolumeStack.inst()
        Int32 i = s._top - 1
        while i >= 0
        {
            VolumeProfile p = s._stack[ i ]
            if p != null
            {
                if p.enabled
                {
                    ret p
                }
            }
            i = i - 1
        }
        ret null
    }

    public static void clear()
    {
        VolumeStack s = VolumeStack.inst()
        s._top = 0
    }

    public static Int32 depth()
    {
        VolumeStack s = VolumeStack.inst()
        ret s._top
    }
}

# ============================================================================
# RenderFeature —— 注入式渲染特性基类（HDRP CustomPass 思想）
# ============================================================================
# 派发与数据全在基类（同 RenderPass 约定：ctx 表内 RenderFeature 引用调
# execute 必须静态命中基类实现，按 featureType 字段内部分派）。
public class RenderFeature
{
    # ── Feature 类型常量（execute 派发键）─────────────────
    public static Int32 TYPE_BASE          = 0
    public static Int32 TYPE_COLOR_OVERLAY = 1

    public string name = "RenderFeature"
    public Int32 featureType = 0
    public bool enabled = true
    # 注入点（EInjectionPoint.*；默认 Opaque 前）
    public Int32 injectionPoint = 0

    # ── 执行体参数（CustomPass 语义；声明在基类——type 派发约定）──
    # 参数 Volume（Volume 思想：全局栈 resolve 覆盖，否则自身 profile）
    public VolumeProfile profile = null
    # 自身命令缓冲（preRecord 产出的命令账目；单流约束下 execute 时
    # replayInto 共享命令流，不单独提交）
    public CommandBuffer record = null
    # PerDraw 槽位（默认 63 = C 侧 SLR_MAX_OBJECTS-1，避开场景物体槽）
    public Int32 perDrawSlot = 63

    public void _init_()
    {
        this.name = "RenderFeature"
        this.featureType = RenderFeature.TYPE_BASE
        this.enabled = true
        this.injectionPoint = EInjectionPoint.BeforeOpaque
        this.profile = null
        this.record = null
        this.perDrawSlot = 63
    }

    # execute —— 按 featureType 派发（命令录进共享命令流 cmd；
    # 2026-11-18：SRP 草稿链移除后 execute 只消费 CommandBuffer）
    public void execute( CommandBuffer cmd )
    {
        if this.featureType == RenderFeature.TYPE_COLOR_OVERLAY
        {
            this.executeColorOverlay( cmd )
        }
        # TYPE_BASE：无操作（用户自定义类型在此扩展派发分支）
    }

    # preRecord() —— 把本 Feature 的命令预录进自身命令缓冲（返回是否有命令）
    public bool preRecord()
    {
        if this.record == null
        {
            this.record = CommandBuffer()
        }
        this.record.begin()
        if this.featureType == RenderFeature.TYPE_COLOR_OVERLAY
        {
            this.recordColorOverlay()
        }
        this.record.end()
        ret this.record.commandCount > 0
    }

    # ── 色块覆盖 Feature（全屏半透明色块；AfterPost 典例）─────
    # 命令布局（2 条）：setPerDraw(自身槽, 全屏 MVP, 覆盖色) + drawItem
    # (PFLAT, 自身槽, QUAD, -1, 透明, queue 3000, z 0.1)。
    # 回放位置：注入点决定（AfterPost = postProcess 之后、blit 之前，
    # 画进 rt_post 后随 blit 进 final——「后处理之后再覆盖」语义）。
    void executeColorOverlay( CommandBuffer cmd )
    {
        # 每次 execute 重录（Volume 栈内容可逐帧变化，不缓存参数）
        this.preRecord()
        if this.record == null
        {
            ret
        }
        if cmd == null
        {
            ret
        }
        this.record.replayInto( cmd )
    }

    void recordColorOverlay()
    {
        # 参数解析：全局 VolumeStack 栈顶 enabled 覆盖，否则自身 profile
        VolumeProfile p = VolumeStack.resolve()
        if p == null
        {
            p = this.profile
        }
        Float32 r = 1.0f
        Float32 g = 0.0f
        Float32 b = 0.0f
        Float32 a = 0.35f
        if p != null
        {
            r = p.getParamFloat( "r", 1.0f )
            g = p.getParamFloat( "g", 0.0f )
            b = p.getParamFloat( "b", 0.0f )
            a = p.getParamFloat( "a", 0.35f )
        }
        # 全屏 quad：MESH_QUAD 单位半宽（[-0.5..0.5]）放大 2 倍覆盖 NDC
        Float32_4x4 mvp = Float32_4x4( 2.0f, 0.0f, 0.0f, 0.0f,
                                        0.0f, 2.0f, 0.0f, 0.0f,
                                        0.0f, 0.0f, 1.0f, 0.0f,
                                        0.0f, 0.0f, 0.0f, 1.0f )
        Color col = Color( r, g, b, a )
        this.record.setPerDraw( this.perDrawSlot, mvp, col )
        # 透明序 z=0.1（最近）：若注入透明段（Before/AfterTransparent），
        # 与场景透明项合并排序时最后画（覆盖语义）
        this.record.drawItem( SLang.RenderPipeline.PROG_PFLAT, this.perDrawSlot,
                              SLang.RenderPipeline.MESH_QUAD, -1, 1, 3000, 0.1f )
    }
}

# ============================================================================
# CustomPass —— Feature 的执行体（持有自身 CommandBuffer 与参数 Volume）
# ============================================================================
# 无新增字段（profile/record/perDrawSlot 在基类——type 派发约定）；构造
# 给出默认覆盖参数集与 AfterPost 注入点。完全手动设字段，不调 this._init_()。
public class CustomPass extends RenderFeature
{
    public void _init_()
    {
        this.name = "CustomPass"
        this.featureType = RenderFeature.TYPE_COLOR_OVERLAY
        this.enabled = true
        this.injectionPoint = EInjectionPoint.AfterPost
        VolumeProfile p = VolumeProfile()
        p.name = "overlay"
        p.setParamFloat( "r", 1.0f )
        p.setParamFloat( "g", 0.0f )
        p.setParamFloat( "b", 0.0f )
        p.setParamFloat( "a", 0.35f )
        this.profile = p
        this.record = null
        this.perDrawSlot = 63
    }
}

# ============================================================================
# ColorOverlayFeature —— 示例 Feature（AIPrompt P2：全屏色块，PFLAT 实现）
# ============================================================================
# 用法（AfterPost 覆盖，HDRP CustomPass 注入点思想的最小可验示例）：
#   ColorOverlayFeature f = ColorOverlayFeature()
#   f.injectionPoint = EInjectionPoint.AfterPost
#   f.perDrawSlot = 3                       # 避开场景 PerDraw 槽
#   feature.preRecord() 后经 CommandBuffer.replayInto 并流提交
#   ctx.submitPasses()                      # Pass 间隙自动执行
# 参数可被全局 Volume 覆盖：VolumeProfile vp = ...; VolumeStack.push( vp )
public class ColorOverlayFeature extends CustomPass
{
    public void _init_()
    {
        this.name = "ColorOverlayFeature"
        this.featureType = RenderFeature.TYPE_COLOR_OVERLAY
        this.enabled = true
        this.injectionPoint = EInjectionPoint.AfterPost
        VolumeProfile p = VolumeProfile()
        p.name = "color-overlay"
        p.setParamFloat( "r", 1.0f )
        p.setParamFloat( "g", 0.0f )
        p.setParamFloat( "b", 0.0f )
        p.setParamFloat( "a", 0.35f )
        this.profile = p
        this.record = null
        this.perDrawSlot = 63
    }
}
