# =========================================================================
# RenderEnvironment —— 渲染环境查询类（render module 视角，根级类）
#
# 与 Core.Environment.Render（平台层 §12.14，CVM 探测的 renderApi/
# shaderModel/renderFlags...）互补：本类查明【渲染库本体】的运行环境——
#   - 支持渲染的情况：sl_render_lib.dll 绑定是否生效（available）、
#     后端已初始化（initialized）、支持的后端列表（backends）；
#   - 当前选择的渲染：当前 RHI 后端名（backend，"gl" / "d3d11" / ...）；
#   - 硬件条件：GPU 渲染器名（gpuRenderer = GL_RENDERER）与
#     GL 版本 + 驱动（gpuVersion = GL_VERSION）；
#   - 资源：全局注册表占用计数（context / pipeline / texture，C 侧
#     slr_*_count）与上限；
#   - 当前渲染配置：命令缓冲容量（CommandBuffer.CAP_*）、透明渲染
#     队列分界（QUEUE_TRANSPARENT_MIN），toString() 汇总显示。
#
# 类为根级（不嵌 namespace Environment）：Core 模块已导出同名
# Core.Environment.Render（裸名解析先命中 Core），跨模块同名冲突，
# 故取独立根级名 RenderEnvironment（同 GfxBackend/CommandBuffer 根级先例）。
#
# 用法（Unity SystemInfo + GraphicsSettings 思路，快照式）：
#   SLang.Render.initialize()                     # 先初始化（可选）
#   RenderEnvironment env = RenderEnvironment.query()
#   Console.writeLine( env.toString() )           # 汇总显示
#   if RenderEnvironment.isBackendSupported( "d3d11" ) { ... }
#
# 数据链：静态即时查询直连 SLang.Render 门面（Render.sl 既有绑定）与
# RenderFFI（新增后端调用单点）；query() 一次采集全部字段成快照，
# 之后只读不再触原生层。
# =========================================================================

public class RenderEnvironment
{
    # ── 支持情况 ────────────────────────────────────────────
    # sl_render_lib.dll 静态绑定是否生效（FFI 兜底降级判别）
    public bool available = false
    # 后端是否已初始化（initialize / initializeBackend 成功）
    public bool initialized = false
    # 支持的后端名列表（C 侧 slr_backend_list 拆分）
    public Array<string> backends = null

    # ── 当前选择 ────────────────────────────────────────────
    # 当前 RHI 后端名（未初始化为 "none"）
    public string backend = "none"

    # ── 硬件条件 ────────────────────────────────────────────
    # GPU 渲染器名（GL_RENDERER，如 "NVIDIA GeForce RTX ..."）
    public string gpuRenderer = "unknown"
    # GL 版本 + 驱动（GL_VERSION，如 "4.6.0 NVIDIA 566.36"）
    public string gpuVersion = "unknown"

    # ── 资源占用（C 侧全局注册表 used 计数 / 上限）──────────
    public Int32 contextCount = 0
    public Int32 contextCapacity = 16     # SLR_MAX_CTX
    public Int32 pipelineCount = 0
    public Int32 pipelineCapacity = 32    # SLR_MAX_PIPES
    public Int32 textureCount = 0
    public Int32 textureCapacity = 64     # SLR_MAX_TEX

    # ── 当前渲染配置（引擎侧常量，CommandBuffer 同源）───────
    # 命令缓冲容量：命令条数 / 整数参数槽 / 浮点参数槽
    public Int32 commandCapacity = 256    # CommandBuffer.CAP_COMMANDS
    public Int32 argCapacity = 2048       # CommandBuffer.CAP_ARGS
    public Int32 floatCapacity = 8192     # CommandBuffer.CAP_FLOATS
    # 透明渲染队列分界（queue >= 该值走透明序：queue 升序 -> z 降序）
    public Int32 transparentQueueMin = 2500

    # ── P4 帧级统计（最近一次 submitPasses 的 Pass/Feature 计数；
    #    ScriptableRenderContext 静态记录，query() 快照）────────
    public Int32 passCount = 0
    public Int32 featureCount = 0

    # ── 诊断 ────────────────────────────────────────────────
    # 最近一次原生调用的错误文本（"ok" = 无错）
    public string lastErrorText = "ok"

    public void _init_()
    {
        this.available = false
        this.initialized = false
        this.backends = Array<string>( 0 )
        this.backend = "none"
        this.gpuRenderer = "unknown"
        this.gpuVersion = "unknown"
        this.contextCount = 0
        this.contextCapacity = 16
        this.pipelineCount = 0
        this.pipelineCapacity = 32
        this.textureCount = 0
        this.textureCapacity = 64
        this.commandCapacity = 256
        this.argCapacity = 2048
        this.floatCapacity = 8192
        this.transparentQueueMin = 2500
        this.passCount = 0
        this.featureCount = 0
        this.lastErrorText = "ok"
    }

    # ── 静态即时查询（每次直连原生层）────────────────────────

    # DLL 绑定是否生效：errorStringOf(0) 真库返回 "ok"，
    # FFI 兜底体返回 "sl_render_lib not available"（可判别）
    public static bool isAvailable()
    {
        ret SLang.Render.errorStringOf( 0 ) == "ok"
    }

    # 支持的后端列表原文（逗号分隔，如 "gl,d3d11"）
    public static string backendList()
    {
        ret SLang.Render.backendList()
    }

    # 当前后端名（未初始化为 "none"）
    public static string currentBackend()
    {
        ret SLang.Render.currentBackend()
    }

    # 支持的后端名列表（逗号拆分；无后端返回空数组）
    public static Array<string> supportedBackends()
    {
        string list = SLang.Render.backendList()
        Int32 len = SystemStringLength( list )
        if len == 0
        {
            ret Array<string>( 0 )
        }
        # 逗号（44）计数 -> 元素数 = 计数 + 1，两遍扫描固定容量填充
        Int32 commas = 0
        Int32 i = 0
        while i < len
        {
            if SystemStringCharCodeAt( list, i ) == 44
            {
                commas = commas + 1
            }
            i = i + 1
        }
        Array<string> r = Array<string>( commas + 1 )
        Int32 idx = 0
        Int32 start = 0
        i = 0
        while i < len
        {
            if SystemStringCharCodeAt( list, i ) == 44
            {
                r[ idx ] = SystemStringRange( list, start, i )
                idx = idx + 1
                start = i + 1
            }
            i = i + 1
        }
        r[ idx ] = SystemStringRange( list, start, len )
        ret r
    }

    # 指定后端是否在支持列表（名字须与 C 侧注册名一致："gl"/"d3d11"...）
    public static bool isBackendSupported( string name )
    {
        if name == null
        {
            ret false
        }
        Array<string> list = RenderEnvironment.supportedBackends()
        Int32 i = 0
        while i < list.length
        {
            if list[ i ] == name
            {
                ret true
            }
            i = i + 1
        }
        ret false
    }

    # GPU 渲染器名（GL_RENDERER；未初始化为 "unknown"）
    public static string gpuName()
    {
        ret SLang.Render.rendererInfo()
    }

    # GL 版本 + 驱动（GL_VERSION；未初始化为 "unknown"）
    public static string gpuVersion()
    {
        ret SLang.Render.versionInfo()
    }

    # ── 快照采集 ────────────────────────────────────────────
    # 一次采集全部字段（之后只读，不再触原生层）
    public static RenderEnvironment query()
    {
        RenderEnvironment env = RenderEnvironment()
        # 支持情况 / 当前选择 / 硬件
        env.available = RenderEnvironment.isAvailable()
        env.backend = SLang.Render.currentBackend()
        env.initialized = env.backend != "none"
        env.backends = RenderEnvironment.supportedBackends()
        env.gpuRenderer = SLang.Render.rendererInfo()
        env.gpuVersion = SLang.Render.versionInfo()
        env.lastErrorText = SLang.Render.errorString()
        # 资源占用（C 侧注册表计数）
        env.contextCount = RenderFFI.ffiContextCount()
        env.pipelineCount = RenderFFI.ffiPipelineCount()
        env.textureCount = RenderFFI.ffiTextureCount()
        # 当前渲染配置（引擎侧常量同源）
        env.commandCapacity = CommandBuffer.CAP_COMMANDS
        env.argCapacity = CommandBuffer.CAP_ARGS
        env.floatCapacity = CommandBuffer.CAP_FLOATS
        env.transparentQueueMin = CommandBuffer.QUEUE_TRANSPARENT_MIN
        # P4 帧级统计（最近一次 submitPasses 的 Pass / Feature 执行数）
        env.passCount = ScriptableRenderContext.lastPassCount
        env.featureCount = ScriptableRenderContext.lastFeatureRunCount
        ret env
    }

    # ── 汇总显示 ────────────────────────────────────────────
    override string toString()
    {
        string avail = "false"
        if this.available
        {
            avail = "true"
        }
        string init = "false"
        if this.initialized
        {
            init = "true"
        }
        # 后端列表回拼（逗号分隔显示形）
        string bl = ""
        Int32 i = 0
        while i < this.backends.length
        {
            if i > 0
            {
                bl = bl + ","
            }
            bl = bl + this.backends[ i ]
            i = i + 1
        }
        # 长串拆成短表达式逐行增量拼接（BuildTst 链长限制）
        string s = "[RenderEnvironment]\n"
        s = s + "available     : " + avail + "\n"
        s = s + "initialized   : " + init + "\n"
        s = s + "backend       : " + this.backend + " (supported: " + bl + ")\n"
        s = s + "gpu renderer  : " + this.gpuRenderer + "\n"
        s = s + "gpu version   : " + this.gpuVersion + "\n"
        s = s + "resources     : context " + SystemConvertString( this.contextCount ) + "/" + SystemConvertString( this.contextCapacity )
        s = s + ", pipeline " + SystemConvertString( this.pipelineCount ) + "/" + SystemConvertString( this.pipelineCapacity )
        s = s + ", texture " + SystemConvertString( this.textureCount ) + "/" + SystemConvertString( this.textureCapacity ) + "\n"
        s = s + "commandbuffer : " + SystemConvertString( this.commandCapacity ) + " cmds / " + SystemConvertString( this.argCapacity ) + " args / "
        s = s + SystemConvertString( this.floatCapacity ) + " floats\n"
        s = s + "render queue  : transparent >= " + SystemConvertString( this.transparentQueueMin ) + "\n"
        s = s + "frame stats   : passes " + SystemConvertString( this.passCount ) + ", feature runs " + SystemConvertString( this.featureCount ) + "\n"
        s = s + "last error    : " + this.lastErrorText
        ret s
    }
}
