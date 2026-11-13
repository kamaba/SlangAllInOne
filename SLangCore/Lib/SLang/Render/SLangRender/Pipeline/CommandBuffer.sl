import Std;
import Math;
# CommandBuffer —— GPU 命令录制（D1 真录制，doc/03 §4.7 + doc/04 §3.6）
#
# 与 Unity CommandBuffer / DX12 GraphicsCommandList 同思路：
#   1) 录制：把命令录进缓冲（setRenderTargets / setPerDraw / drawItem ...），
#      录制期零后端调用——本类只做「参数组织与顺序记账」；
#   2) 整理：sortDrawItems() 对连续 DrawItem 段排序（不透明 queue→z→材质
#      键，透明 queue→z 降序，与 C 侧 sort_items 键序一致）；
#   3) 提交渲染：SLang.RenderPipeline.executeCommandBuffer(cb) 按 SLMC 布局
#      打包（magic|version|count|argOffset|floatOffset|opcodes|args|floats），
#      经 slr_cmd_execute_stream 整包提交，C 侧逐 opcode 回放到 RHI 后端。
#
# 录制结构 = 三段式扁平数组 + 命令条目表（固定容量 + used 游标，禁止每帧
# 增长——doc/05 §3.1 规则 4）：
#   _opcodes[i]     条目 i 的 opcode（ECommandOpcode）
#   _argStart/_argCount/_floatStart/_floatCount[i]   条目 i 的数据区间
#   _args/_floats   参数扁平流（各命令按录入顺序追加）
# 排序只交换条目五元组，不动 _args/_floats 数据；pack 按条目序逐段拷出。
#
# 硬契约：每个 opcode 的 args/floats 消费数为固定值（C 侧 sl_cmd.c 的
# CMD_ARGS/CMD_FLOATS 表），录制方法必须恰好压入表定数量。
#
# 命令集分两段：
#   0..24  doc/03 §4.7 标准 opcode（M0+ 资源世界：PSO/顶点缓冲/计算...，
#          当前后端回放记账跳过，前向兼容）
#   25..29 桥接扩展（13 阶段管线整数槽位世界，C 侧可执行）：
#          SetPerDraw / DrawItem / PostProcess / Blit / Readback

# ECommandOpcode —— 命令 opcode 值表（Int32 静态常量类，非 enum）
#
# 2026-11-13 修复：原文件级 enum 的成员访问（Int32 op = ECommandOpcode.X）
# 被编译器解析为「最近类」静态槽索引 —— IR 实证：ECommandOpcode.SetViewport
# -> LoadStaticField index:1 实际命中 CommandBuffer.CAP_ARGS(2048)；
# SetScissor -> CAP_FLOATS(8192)；SetRenderTargets -> QUEUE_TRANSPARENT_MIN
# (2500)；DrawItem -> index:26 越界（CommandBuffer 仅 4 个静态槽）读垃圾。
# 录制 opcode 全坏 -> sortDrawItems 0 命中 + C 侧回放无法分发。
# 改用模块既有约定（RenderPipeline.MESH_*/PROG_* 同源）的 Int32 静态常量类
# （类静态通路经 Phase ENV 实证完好：CAP_COMMANDS 256 / CAP_ARGS 2048 /
# CAP_FLOATS 8192 输出正确）。值与 C 侧 sl_cmd.c 的 SLR_CMD_* 逐值一致，
# 勿改动。调用点语法不变（ECommandOpcode.X）。
public class ECommandOpcode
{
    public static Int32 Nop = 0
    public static Int32 SetViewport = 1
    public static Int32 SetScissor = 2
    public static Int32 SetRenderTargets = 3
    public static Int32 Clear = 4
    public static Int32 SetPipelineState = 5
    public static Int32 SetComputePipelineState = 6
    public static Int32 SetRootSignature = 7
    public static Int32 SetDescriptorSet = 8
    public static Int32 SetVertexBuffer = 9
    public static Int32 SetIndexBuffer = 10
    public static Int32 SetConstantBuffer = 11
    public static Int32 SetTexture = 12
    public static Int32 SetSampler = 13
    public static Int32 Draw = 14
    public static Int32 DrawIndexed = 15
    public static Int32 DrawProcedural = 16
    public static Int32 DrawMesh = 17
    public static Int32 Dispatch = 18
    public static Int32 ResourceBarrier = 19
    public static Int32 CopyBuffer = 20
    public static Int32 CopyTexture = 21
    public static Int32 ResolveTexture = 22
    public static Int32 BeginEvent = 23
    public static Int32 EndEvent = 24
    # ---- 桥接扩展（13 阶段管线整数槽位世界，C 侧可执行）----
    public static Int32 SetPerDraw = 25
    public static Int32 DrawItem = 26
    public static Int32 PostProcess = 27
    public static Int32 Blit = 28
    public static Int32 Readback = 29
}

public class CommandBuffer
{
    # ── 容量 / 排序常量 ────────────────────────────────────
    public static Int32 CAP_COMMANDS = 256
    public static Int32 CAP_ARGS     = 2048
    public static Int32 CAP_FLOATS   = 8192
    # 透明分界（与 C 侧 sort_items 一致：queue >= 2500 走透明序）
    public static Int32 QUEUE_TRANSPARENT_MIN = 2500

    public string name = "cmd"
    public Int32 handle = 0        # 预留：显式 API 后端的命令列表句柄
    public bool isRecording = false
    public Int32 commandCount = 0  # 已录制命令数（= 条目数，随录制同步）

    # 透明段排序策略（P4 FrameSettings.transparentSortBackToFront 消费）：
    # true = 远→近（z 降序，默认，保混合次序）；false = 近→远（z 升序）。
    # 仅 sortDrawItems 消费；clear() 不重置（配置项非游标）。
    public bool transparentDescending = true

    # P0 数据层：可视物体快照（sortDrawItems 排序后产出，CullingData）
    public CullingData culling = null

    # ── 录制三段式 + 条目表（见文件头注释）─────────────────
    Array<Int32> _opcodes = null
    Array<Int64> _args = null
    Array<Float32> _floats = null
    Array<Int32> _argStart = null
    Array<Int32> _argCount = null
    Array<Int32> _floatStart = null
    Array<Int32> _floatCount = null
    Int32 _cmdUsed = 0
    Int32 _argUsed = 0
    Int32 _floatUsed = 0
    Int32 _overflow = 0

    # 录制中的条目（beginCmd .. endCmd 之间有效）
    Int32 _curEntry = 0
    Int32 _curArgStart = 0
    Int32 _curFloatStart = 0
    bool _curActive = false

    public void _init_()
    {
        this.name = "cmd"
        this.handle = 0
        this.isRecording = false
        this.commandCount = 0
        this._opcodes = Array<Int32>( CommandBuffer.CAP_COMMANDS )
        this._args = Array<Int64>( CommandBuffer.CAP_ARGS )
        this._floats = Array<Float32>( CommandBuffer.CAP_FLOATS )
        this._argStart = Array<Int32>( CommandBuffer.CAP_COMMANDS )
        this._argCount = Array<Int32>( CommandBuffer.CAP_COMMANDS )
        this._floatStart = Array<Int32>( CommandBuffer.CAP_COMMANDS )
        this._floatCount = Array<Int32>( CommandBuffer.CAP_COMMANDS )
        this._cmdUsed = 0
        this._argUsed = 0
        this._floatUsed = 0
        this._overflow = 0
        this._curActive = false
        this.transparentDescending = true
        this.culling = CullingData()
    }

    public void _init_( string _name )
    {
        this._init_()
        this.name = _name
    }

    # ── 录制生命周期 ───────────────────────────────────────
    public void begin()
    {
        this.clear()
        this.isRecording = true
    }

    public void end()
    {
        this.isRecording = false
    }

    # 游标归零（池化复用入口；数组容量保留）
    public void clear()
    {
        this._cmdUsed = 0
        this._argUsed = 0
        this._floatUsed = 0
        this._overflow = 0
        this._curActive = false
        this.commandCount = 0
        this.culling.clear()
    }

    public get int overflowCount()
    {
        ret this._overflow
    }

    # ── 录制内核：条目登记 + 参数追加 ──────────────────────
    void beginCmd( Int32 op )
    {
        if this._cmdUsed >= CommandBuffer.CAP_COMMANDS
        {
            this._overflow = this._overflow + 1
            this._curActive = false
            ret
        }
        Int32 e = this._cmdUsed
        this._cmdUsed = e + 1
        this._opcodes[ e ] = op
        this._curArgStart = this._argUsed
        this._curFloatStart = this._floatUsed
        this._curEntry = e
        this._curActive = true
        this.commandCount = this._cmdUsed
    }

    void endCmd()
    {
        if !this._curActive
        {
            ret
        }
        Int32 e = this._curEntry
        # 2026-11-13 修复：条目起点必须在此落表（原实现只写 count，
        # _argStart/_floatStart 全 0 -> pack 每条目都从头拷 _args[0..]，
        # 三个 DrawItem 全读到 setRT 参数块 [0,0,0,256,256,3]：
        # transp=3、opaque=0、readback dst=0 不回读）
        this._argStart[ e ] = this._curArgStart
        this._floatStart[ e ] = this._curFloatStart
        this._argCount[ e ] = this._argUsed - this._curArgStart
        this._floatCount[ e ] = this._floatUsed - this._curFloatStart
        this._curActive = false
    }

    # 整数参数（Int32 -> Int64 宽化在助手内完成）
    void arg( Int32 v )
    {
        if !this._curActive
        {
            ret
        }
        Int32 a = this._argUsed
        if a < CommandBuffer.CAP_ARGS
        {
            Int64 w = SystemConvertInt64( v )
            this._args[ a ] = w
        }
        else
        {
            this._overflow = this._overflow + 1
        }
        # 溢出也推进游标：保持每 opcode 固定消费数（C 侧游标不脱同步）
        this._argUsed = a + 1
    }

    # 64 位参数（句柄 / 原生指针）
    void arg64( Int64 v )
    {
        if !this._curActive
        {
            ret
        }
        Int32 a = this._argUsed
        if a < CommandBuffer.CAP_ARGS
        {
            this._args[ a ] = v
        }
        else
        {
            this._overflow = this._overflow + 1
        }
        this._argUsed = a + 1
    }

    void flt( Float32 v )
    {
        if !this._curActive
        {
            ret
        }
        Int32 f = this._floatUsed
        if f < CommandBuffer.CAP_FLOATS
        {
            this._floats[ f ] = v
        }
        else
        {
            this._overflow = this._overflow + 1
        }
        this._floatUsed = f + 1
    }

    # 矩阵入 floats 段（列主序：block[col*4+row] = M(row,col)，与 GL
    # std140 / HLSL cbuffer 的 PerDraw 布局一致）
    void pushMat( Float32_4x4 m )
    {
        Int32 col = 0
        while col < 4
        {
            Int32 row = 0
            while row < 4
            {
                this.flt( m.getValue( row, col ) )
                row = row + 1
            }
            col = col + 1
        }
    }

    void pushColor( Color col )
    {
        this.flt( col.r )
        this.flt( col.g )
        this.flt( col.b )
        this.flt( col.a )
    }

    # ── 状态（doc 标准 opcode；后端记账跳过）──────────────
    public void setViewport( Int32 x, Int32 y, Int32 width, Int32 height )
    {
        Int32 op = ECommandOpcode.SetViewport
        this.beginCmd( op )
        this.arg( x )
        this.arg( y )
        this.arg( width )
        this.arg( height )
        this.endCmd()
    }

    public void setScissorRect( Int32 x, Int32 y, Int32 width, Int32 height )
    {
        Int32 op = ECommandOpcode.SetScissor
        this.beginCmd( op )
        this.arg( x )
        this.arg( y )
        this.arg( width )
        this.arg( height )
        this.endCmd()
    }

    # ── 渲染目标 ─────────────────────────────────────────
    # 草稿层（GpuTexture 世界）：固定 6 args + 4 floats 记账，后端跳过
    public void setRenderTarget( RenderTargetBinding binding )
    {
        if binding == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetRenderTargets
        this.beginCmd( op )
        this.arg( binding.colorCount )
        this.arg( 0 )
        this.arg( 0 )
        this.arg( 0 )
        this.arg( 0 )
        this.arg( 0 )
        this.flt( 0.0f )
        this.flt( 0.0f )
        this.flt( 0.0f )
        this.flt( 0.0f )
        this.endCmd()
    }

    public void setRenderTarget( RenderTargetIdentifier color, RenderTargetIdentifier depth )
    {
        RenderTargetBinding b = RenderTargetBinding( color, depth )
        this.setRenderTarget( b )
    }

    # 桥接（可执行）：绑定管线渲染目标 + 视口 + 可选清屏
    #   targetId  0=场景(带深度) 1=后处理中间 2=最终输出（SLang.RenderPipeline
    #   的 rt_scene / rt_post / rt_final）；坐标 GL 约定（原点左下）
    #   clearFlags 位：1=清颜色 2=清深度（RenderPipeline.CLEAR_*）
    public void setRenderTargets( Int32 targetId, Int32 x, Int32 y, Int32 width, Int32 height,
                                  Int32 clearFlags, Color col )
    {
        Int32 op = ECommandOpcode.SetRenderTargets
        this.beginCmd( op )
        this.arg( targetId )
        this.arg( x )
        this.arg( y )
        this.arg( width )
        this.arg( height )
        this.arg( clearFlags )
        this.pushColor( col )
        this.endCmd()
    }

    # 桥接（可执行）：当前目标按已存视口再清
    public void clearTarget( Int32 clearFlags, Color col )
    {
        Int32 op = ECommandOpcode.Clear
        this.beginCmd( op )
        this.arg( clearFlags )
        this.pushColor( col )
        this.endCmd()
    }

    # 草稿层：清屏（bool 语义转 clearFlags 位）
    public void clearRenderTarget( bool clearColor, bool clearDepth, Color col )
    {
        Int32 flags = 0
        if clearColor
        {
            flags = flags + 1
        }
        if clearDepth
        {
            flags = flags + 2
        }
        Int32 op = ECommandOpcode.Clear
        this.beginCmd( op )
        this.arg( flags )
        this.pushColor( col )
        this.endCmd()
    }

    # ── 管线 / 绑定（doc 标准 opcode；后端记账跳过）────────
    public void setPipelineState( GraphicsPipelineState pso )
    {
        if pso == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetPipelineState
        this.beginCmd( op )
        this.arg( pso.handle )
        this.endCmd()
    }

    public void setComputePipelineState( ComputePipelineState pso )
    {
        if pso == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetComputePipelineState
        this.beginCmd( op )
        this.arg( pso.handle )
        this.endCmd()
    }

    public void setRootSignature( RootSignature sig )
    {
        if sig == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetRootSignature
        this.beginCmd( op )
        this.arg( sig.handle )
        this.endCmd()
    }

    public void setDescriptorSet( DescriptorSet descSet )
    {
        if descSet == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetDescriptorSet
        this.beginCmd( op )
        this.arg( 0 )
        this.endCmd()
    }

    public void setVertexBuffer( VertexBuffer vb )
    {
        if vb == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetVertexBuffer
        this.beginCmd( op )
        this.arg( vb.handle )
        this.arg( vb.stride )
        this.endCmd()
    }

    public void setIndexBuffer( IndexBuffer ib )
    {
        if ib == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetIndexBuffer
        Int32 u32 = 0
        if ib.use32Bit
        {
            u32 = 1
        }
        this.beginCmd( op )
        this.arg( ib.handle )
        this.arg( u32 )
        this.endCmd()
    }

    public void setConstantBuffer( Int32 slot, ConstantBuffer cb )
    {
        if cb == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetConstantBuffer
        this.beginCmd( op )
        this.arg( slot )
        this.arg( cb.handle )
        this.endCmd()
    }

    # 草稿层（GpuTextureView 世界）
    public void setTexture( Int32 slot, GpuTextureView view )
    {
        if view == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetTexture
        this.beginCmd( op )
        this.arg( slot )
        this.arg( view.descriptorIndex )
        this.endCmd()
    }

    # 桥接（可执行）：纹理资源写入帧级描述符槽（绑定与绘制分离，
    # DrawItem.texDesc 引用本槽；texHandle = RenderTexture.handle）
    public void setTexture( Int32 slot, Int64 texHandle )
    {
        Int32 op = ECommandOpcode.SetTexture
        this.beginCmd( op )
        this.arg( slot )
        this.arg64( texHandle )
        this.endCmd()
    }

    public void setSampler( Int32 slot, Sampler s )
    {
        if s == null
        {
            ret
        }
        Int32 op = ECommandOpcode.SetSampler
        this.beginCmd( op )
        this.arg( slot )
        this.arg( s.descriptorIndex )
        this.endCmd()
    }

    # ── 绘制（doc 标准 opcode；后端记账跳过）──────────────
    public void draw( Int32 vertexCount, Int32 instanceCount, Int32 startVertex )
    {
        Int32 op = ECommandOpcode.Draw
        this.beginCmd( op )
        this.arg( vertexCount )
        this.arg( instanceCount )
        this.arg( startVertex )
        this.endCmd()
    }

    public void drawIndexed( Int32 indexCount, Int32 instanceCount, Int32 startIndex, Int32 baseVertex )
    {
        Int32 op = ECommandOpcode.DrawIndexed
        this.beginCmd( op )
        this.arg( indexCount )
        this.arg( instanceCount )
        this.arg( startIndex )
        this.arg( baseVertex )
        this.endCmd()
    }

    # 无顶点缓冲绘制（全屏三角 / 程序化几何）
    public void drawProcedural( Int32 vertexCount, Int32 instanceCount )
    {
        Int32 op = ECommandOpcode.DrawProcedural
        this.beginCmd( op )
        this.arg( vertexCount )
        this.arg( instanceCount )
        this.endCmd()
    }

    # 便捷接口（对象直传；兼容 opcode，仅迁移期使用——矩阵走 floats 段）
    public void drawMesh( SLang.Mesh mesh, Material material, Float32_4x4 model, Float32_4x4 viewProjection )
    {
        if mesh == null || material == null
        {
            ret
        }
        Int32 op = ECommandOpcode.DrawMesh
        this.beginCmd( op )
        this.arg( mesh.vertexCount )
        this.arg( 0 )
        this.pushMat( model )
        this.pushMat( viewProjection )
        this.pushColor( material.color )
        this.endCmd()
    }

    public void dispatch( Int32 groupX, Int32 groupY, Int32 groupZ )
    {
        Int32 op = ECommandOpcode.Dispatch
        this.beginCmd( op )
        this.arg( groupX )
        this.arg( groupY )
        this.arg( groupZ )
        this.endCmd()
    }

    # ── 资源屏障 / 拷贝（doc 标准 opcode；后端记账跳过）─────
    public void resourceBarrier( GpuResource res, EResourceState before, EResourceState after )
    {
        if res == null
        {
            ret
        }
        Int32 bi = before
        Int32 ai2 = after
        Int32 op = ECommandOpcode.ResourceBarrier
        this.beginCmd( op )
        this.arg( res.handle )
        this.arg( bi )
        this.arg( ai2 )
        res.state = after
        this.endCmd()
    }

    public void copyBuffer( GpuBuffer src, GpuBuffer dst )
    {
        if src == null || dst == null
        {
            ret
        }
        Int32 op = ECommandOpcode.CopyBuffer
        this.beginCmd( op )
        this.arg( src.handle )
        this.arg( dst.handle )
        this.endCmd()
    }

    public void copyTexture( GpuTexture src, GpuTexture dst )
    {
        if src == null || dst == null
        {
            ret
        }
        Int32 op = ECommandOpcode.CopyTexture
        this.beginCmd( op )
        this.arg( src.handle )
        this.arg( dst.handle )
        this.endCmd()
    }

    # MSAA 解析（doc 03 §4.6/4.7：opaque pass 末尾 msaa -> resolved）
    public void resolveTexture( GpuTexture msaaSrc, GpuTexture dst )
    {
        if msaaSrc == null || dst == null
        {
            ret
        }
        Int32 op = ECommandOpcode.ResolveTexture
        this.beginCmd( op )
        this.arg( msaaSrc.handle )
        this.arg( dst.handle )
        this.endCmd()
    }

    # ── 桥接（可执行）：PerDraw 槽 + 自包含绘制项 ──────────
    # setPerDraw(slot, mvp, color) —— 写 PerDraw 常量缓冲槽（mvp16 列主序
    # + color4；wmat/spec 置零 = 无光照/高光参与，ambient=1 时输出纯色）。
    # slot = 绘制项的 PerDraw 槽位（0..63，与 drawItem 的 slot 对应）。
    public void setPerDraw( Int32 slot, Float32_4x4 mvp, Color color )
    {
        Int32 op = ECommandOpcode.SetPerDraw
        this.beginCmd( op )
        this.arg( slot )
        this.pushMat( mvp )
        this.pushColor( color )
        Int32 k = 0
        while k < 12
        {
            this.flt( 0.0f )
            k = k + 1
        }
        this.endCmd()
    }

    # drawItem(prog, slot, mesh, texDesc, transparent, queue, z) —— 自包含
    # 绘制项（prog/纹理槽/状态全在命令里，排序重排安全）：
    #   prog       RenderPipeline.PROG_*（着色器程序槽）
    #   slot       PerDraw 槽位（setPerDraw 写过的槽）
    #   mesh       RenderPipeline.MESH_TRIANGLE/QUAD 或 MESH_CUSTOM+slot
    #   texDesc    纹理描述符槽（setTexture 写过的槽；-1 = 无纹理）
    #   transparent 0=不透明（深度测+写） 1=透明（混合、深度不写）
    #   queue      渲染队列（<2500 不透明 / >=2500 透明，排序键）
    #   z          深度排序键（不透明近→远升序；透明远→近降序；
    #              仅排序用，回放不消费）
    public void drawItem( Int32 prog, Int32 slot, Int32 mesh, Int32 texDesc,
                          Int32 transparent, Int32 queue, Float32 z )
    {
        Int32 op = ECommandOpcode.DrawItem
        this.beginCmd( op )
        this.arg( prog )
        this.arg( slot )
        this.arg( mesh )
        this.arg( texDesc )
        this.arg( transparent )
        this.arg( queue )
        this.flt( z )
        this.endCmd()
    }

    # ── 桥接（可执行）：后处理 / 全屏整合 / 回读 ────────────
    # enabled=0 走纯拷贝（scene -> post）
    public void postProcess( Int32 enabled, Float32 brightness, Float32 saturation, Float32 vignette )
    {
        Int32 op = ECommandOpcode.PostProcess
        this.beginCmd( op )
        this.arg( enabled )
        this.flt( brightness )
        this.flt( saturation )
        this.flt( vignette )
        this.endCmd()
    }

    # 全屏拷贝 post -> final
    public void blitFinal()
    {
        Int32 op = ECommandOpcode.Blit
        this.beginCmd( op )
        this.endCmd()
    }

    # 回读最终目标（top-down RGBA8 写入 dstPtr 指向的 w*h*4 块）
    public void readback( Int64 dstPtr )
    {
        Int32 op = ECommandOpcode.Readback
        this.beginCmd( op )
        this.arg64( dstPtr )
        this.endCmd()
    }

    # ── 调试标记（RenderDoc / PIX 显示；marker 不入流）─────
    public void beginEvent( string marker )
    {
        Int32 op = ECommandOpcode.BeginEvent
        this.beginCmd( op )
        this.endCmd()
    }

    public void endEvent()
    {
        Int32 op = ECommandOpcode.EndEvent
        this.beginCmd( op )
        this.endCmd()
    }

    # ── 整理：DrawItem 段内排序（Unity 渲染序）────────────
    # 扫描条目表，找连续 DrawItem 段（其余命令为段边界，视口/目标切换
    # 不可跨），段内插入排序——与 C 侧 sort_items 键序一致：
    #   不透明（queue < 2500）：queue 升序 -> z 升序（近→远，Early-Z）
    #                          -> prog 升序（同材质相邻，利于合批）
    #   透明（queue >= 2500）：queue 升序 -> z 降序（远→近，保混合次序）
    # 返回参与排序的 DrawItem 总数。DrawItem 自包含（prog/texDesc/state
    # 在命令里），重排不破坏语义；setPerDraw 是槽位写，不构成段边界
    # 亦可安全跨过（录制范式：先批量 setPerDraw，再批量 drawItem）。
    public Int32 sortDrawItems()
    {
        Int32 n = this._cmdUsed
        Int32 sorted = 0
        Int32 runStart = 0
        Int32 diOp = ECommandOpcode.DrawItem
        this.culling.clear()
        while runStart < n
        {
            Int32 opHere = this._opcodes[ runStart ]
            if opHere == diOp
            {
                # 找段尾 [runStart, runEnd)
                Int32 runEnd = runStart + 1
                bool scanning = runEnd < n
                while scanning
                {
                    Int32 op2 = this._opcodes[ runEnd ]
                    if op2 == diOp
                    {
                        runEnd = runEnd + 1
                        scanning = runEnd < n
                    }
                    else
                    {
                        scanning = false
                    }
                }
                this.sortRun( runStart, runEnd )
                # P0 数据层：排序后的段写入可视物体快照（culling）
                Int32 e = runStart
                while e < runEnd
                {
                    Int32 es = this._argStart[ e ]
                    Int32 ef = this._floatStart[ e ]
                    this.culling.addItem( this._args[ es ], this._args[ es + 1 ], this._args[ es + 2 ], this._args[ es + 3 ], this._args[ es + 4 ], this._args[ es + 5 ], this._floats[ ef ] )
                    e = e + 1
                }
                sorted = sorted + ( runEnd - runStart )
                runStart = runEnd
            }
            else
            {
                runStart = runStart + 1
            }
        }
        ret sorted
    }

    # 段内插入排序（key 条目五元组 + 排序键先落局部，右移腾位后放回）
    void sortRun( Int32 start, Int32 end )
    {
        Int32 i = start + 1
        while i < end
        {
            Int32 ks = this._argStart[ i ]
            Int32 kf = this._floatStart[ i ]
            Int64 kProg = this._args[ ks ]
            Int64 kQueue = this._args[ ks + 5 ]
            Float32 kZ = this._floats[ kf ]
            Int32 kOp = this._opcodes[ i ]
            Int32 kAc = this._argCount[ i ]
            Int32 kFc = this._floatCount[ i ]
            Int32 j = i - 1
            bool moving = j >= start
            while moving
            {
                if this.entryLess( kQueue, kZ, kProg, j )
                {
                    # 条目 j 右移一格（五元组，数据区间不动）
                    this._opcodes[ j + 1 ] = this._opcodes[ j ]
                    this._argStart[ j + 1 ] = this._argStart[ j ]
                    this._argCount[ j + 1 ] = this._argCount[ j ]
                    this._floatStart[ j + 1 ] = this._floatStart[ j ]
                    this._floatCount[ j + 1 ] = this._floatCount[ j ]
                    j = j - 1
                    moving = j >= start
                }
                else
                {
                    moving = false
                }
            }
            # 放回 key 条目
            this._opcodes[ j + 1 ] = kOp
            this._argStart[ j + 1 ] = ks
            this._argCount[ j + 1 ] = kAc
            this._floatStart[ j + 1 ] = kf
            this._floatCount[ j + 1 ] = kFc
            i = i + 1
        }
    }

    # key 是否应排在条目 j 之前（排序键：queue / z / prog，
    # DrawItem args = [prog, slot, mesh, texDesc, transparent, queue]，z 在 floats）
    bool entryLess( Int64 kQueue, Float32 kZ, Int64 kProg, Int32 j )
    {
        Int32 js = this._argStart[ j ]
        Int64 jQueue = this._args[ js + 5 ]
        if kQueue != jQueue
        {
            ret kQueue < jQueue
        }
        Int32 jf = this._floatStart[ j ]
        Float32 jZ = this._floats[ jf ]
        Int64 qMin = 2500
        if kQueue < qMin
        {
            # 不透明：z 升序 -> prog 升序（材质相邻成批）
            if kZ != jZ
            {
                ret kZ < jZ
            }
            Int64 jProg = this._args[ js ]
            ret kProg < jProg
        }
        # 透明：z 降序（远→近，保混合次序）或升序（策略开关，P4
        # FrameSettings.transparentSortBackToFront），不加材质键
        # （合批不得改混合次序）
        if this.transparentDescending
        {
            ret kZ > jZ
        }
        ret kZ < jZ
    }

    # ── P2 Feature 回放：把本缓冲录制的条目重放进目标缓冲 ──
    # 单流约束（P1 偏离记录）：Feature 持有的自身 CommandBuffer 经
    # preRecord 产出命令账目，execute 时经本方法重放进 P1 的共享命令流
    # （一帧全部命令必须同一条流提交）。逐条目按固定消费数拷贝 opcode +
    # args/floats 数据区间；目标须处于录制中（isRecording）。
    public bool replayInto( CommandBuffer dst )
    {
        if dst == null
        {
            ret false
        }
        if dst.isRecording == false
        {
            ret false
        }
        Int32 i = 0
        while i < this._cmdUsed
        {
            dst.beginCmd( this._opcodes[ i ] )
            Int32 k = 0
            while k < this._argCount[ i ]
            {
                Int32 srcArg = this._argStart[ i ] + k
                dst.arg64( this._args[ srcArg ] )
                k = k + 1
            }
            Int32 m = 0
            while m < this._floatCount[ i ]
            {
                Int32 srcFlt = this._floatStart[ i ] + m
                dst.flt( this._floats[ srcFlt ] )
                m = m + 1
            }
            dst.endCmd()
            i = i + 1
        }
        ret true
    }

    # ── 提交打包（SLMC 布局，doc/04 §3.6）─────────────────
    # 命令流总字节数（分配原生块用）
    public Int32 streamBytes()
    {
        Int32 opEnd = 24 + this._cmdUsed * 4
        Int32 argOff = ( opEnd + 7 ) / 8 * 8
        Int32 floatOff = argOff + this._argUsed * 8
        ret floatOff + this._floatUsed * 4
    }

    # 按 SLMC 布局写入 ptr 指向的原生块（条目序；args/floats 逐条目
    # 拷区间——排序后条目与数据区间错位，不能整段直拷）
    public bool pack( Int64 ptr )
    {
        if ptr == 0
        {
            ret false
        }
        Int32 n = this._cmdUsed
        Int32 opEnd = 24 + n * 4
        Int32 argOff = ( opEnd + 7 ) / 8 * 8
        Int32 floatOff = argOff + this._argUsed * 8
        Memory.writeI32( ptr, 0, 0x534C4D43 )     # magic 'SLMC'
        Memory.writeI32( ptr, 4, 1 )              # version
        Memory.writeI32( ptr, 8, n )              # commandCount
        Memory.writeI32( ptr, 12, argOff )
        Memory.writeI32( ptr, 16, floatOff )
        Int32 i = 0
        while i < n
        {
            Memory.writeI32( ptr, 24 + i * 4, this._opcodes[ i ] )
            i = i + 1
        }
        Int32 aw = argOff
        Int32 fw = floatOff
        i = 0
        while i < n
        {
            Int32 st = this._argStart[ i ]
            Int32 ac = this._argCount[ i ]
            Int32 k = 0
            while k < ac
            {
                Memory.writeI64( ptr, aw, this._args[ st + k ] )
                aw = aw + 8
                k = k + 1
            }
            Int32 fs = this._floatStart[ i ]
            Int32 fc = this._floatCount[ i ]
            k = 0
            while k < fc
            {
                Memory.writeF32( ptr, fw, this._floats[ fs + k ] )
                fw = fw + 4
                k = k + 1
            }
            i = i + 1
        }
        ret true
    }

    override string toString()
    {
        ret "CommandBuffer(" + this.name + ", cmds=" + this.commandCount.toString() + ")"
    }
}

# CommandBufferPool —— 复用命令缓冲，避免每帧新建（Unity 同名类）
public class CommandBufferPool
{
    Array<CommandBuffer> _pool = null
    Int32 _used = 0

    public void _init_()
    {
        this._pool = Array<CommandBuffer>( 0 )
        this._used = 0
    }

    # 说明：方法名不能用 get（getter 关键字，会导致解析器递归栈溢出）
    public CommandBuffer getBuffer( string name )
    {
        if this._used < this._pool.length
        {
            # 注：下标不能用成员访问（this._used 会触发 HandleVisit 断言），先落局部变量
            Int32 usedIdx = this._used
            CommandBuffer cb = this._pool[ usedIdx ]
            this._used = this._used + 1
            cb.name = name
            cb.clear()
            ret cb
        }
        # 说明：跨类带参构造调用会触发解析器合成异常函数并崩溃，
        # 改为无参构造 + 字段赋值（下同，RenderTarget/GpuTexture 处已同样处理）
        CommandBuffer ncb = CommandBuffer()
        ncb.name = name
        Int32 oldLen = this._pool.length
        Array<CommandBuffer> np = Array<CommandBuffer>( oldLen + 1 )
        int i = 0
        while i < oldLen
        {
            np[i] = this._pool[i]
            i++
        }
        np[ oldLen ] = ncb
        this._pool = np
        this._used = this._used + 1
        ret ncb
    }

    # 每帧结束调用：游标归零，池子本身保留
    public void releaseAll()
    {
        this._used = 0
    }

    public get int poolSize()
    {
        ret this._pool.length
    }
}
