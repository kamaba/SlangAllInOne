# =========================================================================
# Pipeline.sl —— 13 阶段渲染管线 SL 门面（薄绑定，逻辑全在 C 层）
# ----------------------------------------------------------------------------
# 对应 C 实现：Render/cvm_render_lib/sl_render_lib.c（slr_pipeline_* 导出）。
# 每个公开方法 1:1 对应一个 slr_* FFI 函数；本层不含渲染逻辑。
#
# 一帧的完整流程（renderFrame / runStages 等价，仿 Unity 底层机制）：
#   1  beginFrame            渲染开始（绑定场景 FBO、清屏、帧计数）
#   2  prepareMaterials      准备物料（着色器/采样器就绪）
#   3  earlyUpdate           提前更新（对象动画，如色相循环）
#   4  cullLayers            渲染层分层（cullingMask + 视域剔除）
#   5  assembleLayerData     渲染层整理数据（排序绘制列表 + MVP + 分块）
#   6  uploadRenderData      向 GPU 层传入渲染数据（PerDraw CBUFFER/UBO）
#   7  renderShaderChunks    shader 分块渲染（不透明段，按 shader 合批）
#   8  updateCoreTime        核心更新时间（帧间隔 dt 推进）
#   9  renderShaderSegments  shader 分段渲染（透明段，后→前混合）
#   10 assembleRenderedLayers 整理渲染后的图层（图层位掩码/状态复位）
#   10.5 taaResolve          v3.7 TAA 时域累积（速度重投影 + 邻域 clamp）
#   10.6 motionBlur          v3.8 动态模糊（速度方向对称快门采样）
#   11 postProcess           后处理（亮度/饱和度/暗角全屏 pass）
#   12 integrateLayers       层级的逻辑整合（合成到最终 renderTexture）
#   13 outputRenderTexture   输出最终渲染 renderTexture（RGBA8 回读）
#
# 用法（renderTexture 通道，QT QLabel.setPixmapRgba 对接）：
#   SLang.Render.initialize()
#   SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
#   SLang.RenderObject tri = pipe.addObject( pipe.MESH_TRIANGLE )
#   tri.setAnimated( pipe.ANIM_HUE_CYCLE, 0.05f )
#   Int64 pixels = Memory.alloc( 256 * 256 * 4 )
#   pipe.renderFrame( 0.0f, pixels )          # 或 pipe.runStages( t, pixels )
#   label.setPixmapRgba( pixels, 256, 256 )
#
# 注意：所有类型必须是 namespace 下的顶级类型；含 ptr 形参的绑定手写 sig。
# =========================================================================

namespace SLang
{
    # ===================================================================
    # RenderPipeline —— 13 阶段管线门面
    # ===================================================================
    public class RenderPipeline
    {
        # ── 阶段常量（stat STAT_LAST_STAGE 取值）──────────────────
        public static Int32 STAGE_BEGIN_FRAME            = 1
        public static Int32 STAGE_PREPARE_MATERIALS      = 2
        public static Int32 STAGE_EARLY_UPDATE          = 3
        public static Int32 STAGE_CULL_LAYERS            = 4
        public static Int32 STAGE_ASSEMBLE_LAYER_DATA   = 5
        public static Int32 STAGE_UPLOAD_RENDER_DATA    = 6
        public static Int32 STAGE_RENDER_SHADER_CHUNKS  = 7
        public static Int32 STAGE_UPDATE_CORE_TIME      = 8
        public static Int32 STAGE_RENDER_SHADER_SEGMENTS = 9
        public static Int32 STAGE_ASSEMBLE_RENDERED_LAYERS = 10
        public static Int32 STAGE_POST_PROCESS           = 11
        public static Int32 STAGE_INTEGRATE_LAYERS      = 12
        public static Int32 STAGE_OUTPUT_RENDER_TEXTURE = 13

        # ── 统计项（stat(id)）────────────────────────────────────
        public static Int32 STAT_FRAME             = 0
        public static Int32 STAT_VISIBLE           = 1
        public static Int32 STAT_CULLED            = 2
        public static Int32 STAT_DRAW_CALLS        = 3
        public static Int32 STAT_OPAQUE_DRAWS      = 4
        public static Int32 STAT_TRANSPARENT_DRAWS = 5
        public static Int32 STAT_POST_ENABLED       = 6
        public static Int32 STAT_LAST_STAGE         = 7
        public static Int32 STAT_OBJECT_COUNT       = 8
        public static Int32 STAT_CHUNK_COUNT        = 9
        public static Int32 STAT_LAYERS_MASK       = 10
        public static Int32 STAT_UPLOAD_COUNT       = 11
        public static Int32 STAT_TIME_MS           = 12
        public static Int32 STAT_DT_MS              = 13
        public static Int32 STAT_TEXTURE_COUNT      = 14
        public static Int32 STAT_PROGRAM_SWITCHES   = 15
        public static Int32 STAT_CAMERA_COUNT       = 16
        public static Int32 STAT_INSTANCE_COUNT    = 17
        # v3.6 AA + MotionVectors
        public static Int32 STAT_MV_ENABLED        = 18
        public static Int32 STAT_MSAA_SAMPLES      = 19
        public static Int32 STAT_FXAA              = 20
        # v3.7 TAA（实际生效：0 = 后端不支持/关）
        public static Int32 STAT_TAA               = 21
        # v3.8 Motion Blur（实际生效：0 = 后端不支持/关）
        public static Int32 STAT_MOTION_BLUR       = 22

        # ── 相机清屏标志位（clearFlags）──────────────────────────
        public static Int32 CLEAR_COLOR = 1
        public static Int32 CLEAR_DEPTH = 2

        # ── 网格 / 动画常量 ────────────────────────────────────────
        public static Int32 MESH_TRIANGLE    = 0
        public static Int32 MESH_QUAD        = 1
        # 动态网格槽（4..7）：meshKind = MESH_CUSTOM + slot，
        # 顶点由 uploadMesh(slot, ptr, count) 上传（每帧可重传）
        public static Int32 MESH_CUSTOM      = 4
        public static Int32 MESH_CUSTOM_MAX  = 4
        public static Int32 CUSTOM_MAX_VERTS = 4096
        public static Int32 ANIM_NONE        = 0
        public static Int32 ANIM_HUE_CYCLE   = 1

        # ── 着色器程序槽（C 侧 SLR_PROG_* 逐值一致；命令流 drawItem 的
        #    prog 参数取值。0..8 内建槽 + 9..18 v3.5 固化编译槽）────
        public static Int32 PROG_FLAT       = 0    # v1：MVP/Color uniform
        public static Int32 PROG_TEX        = 1    # v1：MVP/Color + 纹理
        public static Int32 PROG_PFLAT      = 2    # 管线：PerDraw + 纯色
        public static Int32 PROG_PTEX       = 3    # 管线：PerDraw + 纹理
        public static Int32 PROG_BLIT       = 4    # 全屏拷贝
        public static Int32 PROG_POST       = 5    # 后处理（v3.6 内嵌 FXAA）
        public static Int32 PROG_PHONG_FLAT = 6    # Phong 光照 + 纯色
        public static Int32 PROG_PHONG_TEX  = 7    # Phong 光照 + 纹理
        public static Int32 PROG_MOTION     = 8    # v3.6 MotionVectors 速度 pass
        public static Int32 PROG_GEN_BASE   = 9    # 固化槽基（effect*2+variant）

        # ── 命令流渲染目标 id（executeCommandBuffer 桥接的目标表）────
        public static Int32 TARGET_SCENE    = 0    # rt_scene（场景，带深度）
        public static Int32 TARGET_POST     = 1    # rt_post（后处理中间）
        public static Int32 TARGET_FINAL    = 2    # rt_final（回读源）

        Int64 _handle = 0
        Int32 _width = 0
        Int32 _height = 0

        _init_( Int64 handle, Int32 width, Int32 height )
        {
            this._handle = handle
            this._width = width
            this._height = height
        }

        get Int64 handle()
        {
            ret this._handle
        }

        get Int32 width()
        {
            ret this._width
        }

        get Int32 height()
        {
            ret this._height
        }

        get bool isValid()
        {
            ret this._handle != 0
        }

        # ── 创建 / 释放 ───────────────────────────────────────────

        public static RenderPipeline create( Int32 width, Int32 height )
        {
            Int64 h = RenderPipeline.ffiPipelineCreate( width, height )
            if h == 0
            {
                ret null
            }
            ret RenderPipeline( h, width, height )
        }

        public bool destroy()
        {
            if this._handle == 0
            {
                ret false
            }
            bool ok = RenderPipeline.ffiPipelineDestroy( this._handle )
            if ok
            {
                this._handle = 0
            }
            ret ok
        }

        public bool resize( Int32 width, Int32 height )
        {
            if this._handle == 0 || width <= 0 || height <= 0
            {
                ret false
            }
            if RenderPipeline.ffiPipelineResize( this._handle, width, height ) == false
            {
                ret false
            }
            this._width = width
            this._height = height
            ret true
        }

        public Int64 frameCount()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret RenderPipeline.ffiPipelineFrameCount( this._handle )
        }

        # ── 相机 / 清屏 / 后处理 ─────────────────────────────────

        # setCamera(cullMask, l, r, b, t) —— 正交视域 + 剔除掩码
        #   兼容 v2：写默认相机（槽 0）。
        #   cullMask：按位对应 layer 0..31（-1 = 全部可见）
        public bool setCamera( Int32 cullMask, Float32 l, Float32 r, Float32 b, Float32 t )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetCamera( this._handle, cullMask, l, r, b, t )
        }

        # ── 多相机（槽 0 为默认相机；渲染按 depth 升序逐相机执行）──

        # addCamera(depth) —— 新建相机槽，返回 RenderCamera
        public RenderCamera addCamera( Int32 depth )
        {
            if this._handle == 0
            {
                ret null
            }
            Int64 id = RenderPipeline.ffiCameraCreate( this._handle, depth )
            if id == 0
            {
                ret null
            }
            ret RenderCamera( this._handle, id )
        }

        public bool removeCamera( RenderCamera cam )
        {
            if this._handle == 0 || cam == null || cam.isValid == false
            {
                ret false
            }
            ret RenderPipeline.ffiCameraDestroy( this._handle, cam.handle )
        }

        public Int32 cameraCount()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret RenderPipeline.ffiCameraCount( this._handle )
        }

        public bool setClearColor( Float32 r, Float32 g, Float32 b, Float32 a )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetClearColor( this._handle, r, g, b, a )
        }

        # ── P6 渐变天空背景 ─────────────────────────────────────
        # 顶/底 RGB（0..1）；每相机清屏（COLOR 位）后画全屏渐变 quad，
        # 物体随后正常覆盖（无深度写入）。默认关——setSkyEnabled(1) 开。
        # 生效端为 C 管线 slr_pipeline_set_sky_color/set_sky_on。
        public bool setSkyColor( Float32 topR, Float32 topG, Float32 topB,
            Float32 bottomR, Float32 bottomG, Float32 bottomB )
        {
            if this._handle == 0
            {
                ret false
            }
            bool ok1 = RenderPipeline.ffiSetSkyTop( this._handle, topR, topG, topB )
            bool ok2 = RenderPipeline.ffiSetSkyBottom( this._handle, bottomR, bottomG, bottomB )
            bool both = ok1 && ok2
            ret both
        }

        public bool setSkyEnabled( Int32 on )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetSkyOn( this._handle, on )
        }

        # setSkyCube(texHandle) —— cubemap 天空纹理句柄（doc/13 §2.1 第二步；
        # 非 0 且 GL/GLES 后端时阶段 7 天空绘制改走 cube 采样，0 回退渐变）。
        # texHandle 用 RenderTexture.createCubeTexture 产物的 handle。
        public bool setSkyCube( Int64 texHandle )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetSkyCube( this._handle, texHandle )
        }

        # setSkyCubeCam(camPtr) —— cube 天空采样基向量（doc/13 §2.1 透视相机
        # 专项）：camPtr 11 float [fwd3/right3/up3/tanX/tanY]；0 指针 = 恢复
        # 默认（正交 -Z 公式，向后兼容）。
        public bool setSkyCubeCam( Int64 camPtr )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetSkyCubeCam( this._handle, camPtr )
        }

        # setPostEffect(enable, brightness, saturation, vignette)
        #   enable=0 纯拷贝；vignette 0..1 暗角强度
        public bool setPostEffect( Int32 enable, Float32 brightness, Float32 saturation, Float32 vignette )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetPost( this._handle, enable, brightness, saturation, vignette )
        }

        # setPostParams(prmPtr) —— 后处理参数块 v2（Unity Color Adjustments 风，
        # doc/14 v1.1）：prm 指向 13 float 块
        #   [0]enable [1]brightness [2]contrast [3]saturation [4]vignette
        #   [5]vigSmooth [6]hueShift(deg) [7]grain [8]grainSeed [9]tonemap(0/1)
        #   [10..12]colorFilter RGB
        # 中性值 = 旧三参行为逐位一致；GL/GLES 全量消费，VK/D3D11 只吃
        # enable/brightness/saturation/vignette（doc/14 §5 兼容表）
        public bool setPostParams( Int64 prmPtr )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetPostParams( this._handle, prmPtr )
        }

        # setAa(msaa, fxaaOn, fxaaSpan) —— v3.6 抗锯齿（FXAA + MSAA）：
        #   msaa ∈ {0,1}=关，否则钳 [2,8]（非 2/4/8 按 4）——rt_scene 改建
        #   多采样目标，阶段 11 先 resolve 再后处理；后端不支持（vk）或创建
        #   失败自动回退单采样。
        #   fxaaOn = FS_POST 内嵌 FXAA 前段开关（0 = 关，输出与旧版逐位一致）；
        #   fxaaSpan = 采样延伸上限（默认 8）。
        #   返回值 = 后端实际生效 MSAA 采样数（0 = 单采样）——调用方可用它
        #   判断回退（stat STAT_MSAA_SAMPLES 同源）。
        public Int32 setAa( Int32 msaa, Int32 fxaaOn, Float32 fxaaSpan )
        {
            if this._handle == 0
            {
                ret 0
            }
            ret RenderPipeline.ffiSetAa( this._handle, msaa, fxaaOn, fxaaSpan )
        }

        # setMotionVectors(on) —— v3.6 速度 RT 开关：阶段 9 尾逐相机以
        # PROG_MOTION 重绘全部绘制项（上帧 MVP 经 PerDrawPrev 块下发），
        # 输出 top-down RGBA8（RG = 速度*0.5+0.5，0.5 = 静止）。
        # 后端无 upload_perdraw_prev（vk/d3d11）时开关无效（stat 读 0）。
        public bool setMotionVectors( Int32 on )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetMotion( this._handle, on )
        }

        # outputMotionTexture(dstPtr) —— 回读速度 RT（w*h*4 RGBA8 块，
        # top-down 行序；RG 通道 = 速度*0.5+0.5 编码）。
        # motion 未启用或尚未渲染任何帧（RT 未创建）返回 false。
        public bool outputMotionTexture( Int64 dstPtr )
        {
            if this._handle == 0 || dstPtr == 0
            {
                ret false
            }
            ret RenderPipeline.ffiOutputMotion( this._handle, dstPtr )
        }

        # setTaa(on, blend) —— v3.7 TAA 时域抗锯齿（on=1 开，自动开 motion
        # 取速度图；blend = 当前帧权重 0..1，默认 0.1，越小平滑越重）。
        # 内部：重投影历史帧（velocity RG）+ 3x3 邻域 clamp 防鬼影 +
        # mix(hist, cur, blend)；history ping-pong 双 RT，首帧/切换时
        # reset 忽略旧历史。后端不支持（vk / 无 motion 的 d3d11）返回 false。
        public bool setTaa( Int32 on, Float32 blend )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetTaa( this._handle, on, blend )
        }

        # setMotionBlur(on, scale, samples) —— v3.8 动态模糊（后处理链
        # 第一环）：on=1 自动打开 motion，沿速度方向对称快门采样平均；
        # scale=速度倍率（默认 1.0，钳 0..4）；samples=采样数（默认 8，
        # 钳 4..16）。速度 0 的像素输出原色（静止画面零模糊）。
        # 后端无 motion_blur / 无速度图（VK/D3D11）返回 false。
        public bool setMotionBlur( Int32 on, Float32 scale, Int32 samples )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiSetMotionBlur( this._handle, on, scale, samples )
        }

        # ── 场景对象 ─────────────────────────────────────────────

        public RenderObject addObject( Int32 meshKind )
        {
            if this._handle == 0
            {
                ret null
            }
            Int64 id = RenderPipeline.ffiObjectCreate( this._handle, meshKind )
            if id == 0
            {
                ret null
            }
            ret RenderObject( this._handle, id )
        }

        # uploadMesh(slot, vertsPtr, vertCount) —— 上传动态网格（3D/程序化
        # 几何通道）：vertsPtr 指向三角形列表（pos2+uv2 交错，stride 16B，
        # SL 侧 Memory.writeF32 填充）。对象 meshKind = MESH_CUSTOM + slot
        # 引用该槽；每帧可重复调用实现顶点动画。
        public bool uploadMesh( Int32 slot, Int64 vertsPtr, Int32 vertCount )
        {
            ret RenderPipeline.ffiMeshUpload( slot, vertsPtr, vertCount )
        }

        # ── 命令流提交（D1 真录制：SLangRender.CommandBuffer）────
        # Unity 的 context.ExecuteCommandBuffer 对应物。三段式的最后一环：
        #   cb.begin() -> 录制命令（setRenderTargets/setTexture/setPerDraw/
        #   drawItem...，录制期零后端调用）-> cb.sortDrawItems() 整理排序
        #   -> 本方法提交：按 SLMC 布局（doc/04 §3.6）打包 cb 的
        #   opcode/args/floats 三段数组，经 slr_cmd_execute_stream 整包
        #   传入，C 侧逐 opcode 回放到当前 RHI 后端（四后端同效果）。
        # 约束：cb 须已 end()；本帧用完的命令流不被引用（提交后即回放或
        #   入队自拷，cb 可 clear 后复用）。
        # N3 双缓冲：pack 到 cb 内部轮换槽（pack 帧 N+1 与执行帧 N 的块
        #   交替，容量只增）；同步路径提交即回放、async 路径 C 侧入队时
        #   自拷到队列槽——两种路径块返回后即可复用。
        public bool executeCommandBuffer( CommandBuffer cb )
        {
            if this._handle == 0 || cb == null
            {
                ret false
            }
            if cb.isRecording
            {
                ret false
            }
            if cb.commandCount <= 0
            {
                ret false
            }
            Int32 bytes = cb.streamBytes()
            if bytes <= 0
            {
                ret false
            }
            Int64 ptr = cb.packToSlot()
            if ptr == 0
            {
                ret false
            }
            ret RenderFFI.ffiCmdExecuteStream( this._handle, ptr, cb.commandCount )
        }

        public bool removeObject( RenderObject obj )
        {
            if this._handle == 0 || obj == null || obj.isValid == false
            {
                ret false
            }
            ret RenderPipeline.ffiObjectDestroy( this._handle, obj.handle )
        }

        public Int32 objectCount()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret RenderPipeline.ffiObjectCount( this._handle )
        }

        # ── 光照（管线光照槽表；高层入口见 RenderLight.applyTo）──────
        # 每管线 MAX_LIGHTS 个光照槽，着色器消费首个启用的平行光 +
        # 首个聚光（2D 世界系逐像素：直射光按物体朝向 ndl、聚光按
        # 世界坐标锥角 + 距离衰减）。默认无光照 + ambient=1.0 时
        # 输出与无光照版逐字节一致（向后兼容）。
        public static Int32 LIGHT_DIRECTIONAL = 0
        public static Int32 LIGHT_POINT       = 1
        public static Int32 LIGHT_SPOT        = 2
        public static Int32 MAX_LIGHTS        = 8

        # setLightParams(slot, type, paramsPtr) —— 低层 FFI 直通：
        # paramsPtr 指向 float 参数块（Memory.writeF32 填充，
        # 布局见 vm_sl_render.h v3.3 注释；RenderLight.applyTo 封装）
        public bool setLightParams( Int32 slot, Int32 type, Int64 paramsPtr )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiLightSet( this._handle, slot, type, paramsPtr )
        }

        # clearLight(slot) —— 清除光照槽
        public bool clearLight( Int32 slot )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiLightClear( this._handle, slot )
        }

        # lightCount() —— 已启用的光照槽数
        public Int32 lightCount()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret RenderPipeline.ffiLightCount( this._handle )
        }

        # setAmbient(intensity) —— 环境光强度 [0,1]（默认 1.0 = 无光照效果）
        public bool setAmbient( Float32 intensity )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiLightSetAmbient( this._handle, intensity )
        }

        # ── 13 阶段（逐阶段驱动）────────────────────────────────

        public bool beginFrame( Float32 time )
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiBeginFrame( this._handle, time )
        }

        public bool prepareMaterials()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiPrepareMaterials( this._handle )
        }

        public bool earlyUpdate()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiEarlyUpdate( this._handle )
        }

        public bool cullLayers()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiCullLayers( this._handle )
        }

        public bool assembleLayerData()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiAssembleLayerData( this._handle )
        }

        public bool uploadRenderData()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiUploadRenderData( this._handle )
        }

        public bool renderShaderChunks()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiRenderShaderChunks( this._handle )
        }

        public bool updateCoreTime()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiUpdateCoreTime( this._handle )
        }

        public bool renderShaderSegments()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiRenderShaderSegments( this._handle )
        }

        public bool assembleRenderedLayers()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiAssembleRenderedLayers( this._handle )
        }

        # v3.7 TAA 阶段（10.5：MSAA resolve 之后、后处理之前的全屏
        # 时域累积 pass；未开启时 C 侧空操作返回 true）
        public bool taaResolve()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiTaa( this._handle )
        }

        # v3.8 Motion Blur 阶段（10.6：TAA 之后、FXAA/调色之前的
        # 全屏速度方向采样；未开启时 C 侧空操作返回 true）
        public bool motionBlur()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiMotionBlur( this._handle )
        }

        public bool postProcess()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiPostProcess( this._handle )
        }

        public bool integrateLayers()
        {
            if this._handle == 0
            {
                ret false
            }
            ret RenderPipeline.ffiIntegrateLayers( this._handle )
        }

        public bool outputRenderTexture( Int64 dstPtr )
        {
            if this._handle == 0 || dstPtr == 0
            {
                ret false
            }
            ret RenderPipeline.ffiOutputRenderTexture( this._handle, dstPtr )
        }

        # renderFrame —— 一键全流程（C 层依序执行 1..13）
        public bool renderFrame( Float32 time, Int64 dstPtr )
        {
            if this._handle == 0 || dstPtr == 0
            {
                ret false
            }
            ret RenderPipeline.ffiRenderFrame( this._handle, time, dstPtr )
        }

        # runStages —— SL 侧逐阶段驱动 1..13（与 renderFrame 等价，
        # 用于验证完整流程可由上层逐段编排）
        public bool runStages( Float32 time, Int64 dstPtr )
        {
            if this._handle == 0 || dstPtr == 0
            {
                ret false
            }
            bool ok = true
            ok = this.beginFrame( time )
            if ok
            {
                ok = this.prepareMaterials()
            }
            if ok
            {
                ok = this.earlyUpdate()
            }
            if ok
            {
                ok = this.cullLayers()
            }
            if ok
            {
                ok = this.assembleLayerData()
            }
            if ok
            {
                ok = this.uploadRenderData()
            }
            if ok
            {
                ok = this.renderShaderChunks()
            }
            if ok
            {
                ok = this.updateCoreTime()
            }
            if ok
            {
                ok = this.renderShaderSegments()
            }
            if ok
            {
                ok = this.assembleRenderedLayers()
            }
            if ok
            {
                ok = this.taaResolve()
            }
            if ok
            {
                ok = this.motionBlur()
            }
            if ok
            {
                ok = this.postProcess()
            }
            if ok
            {
                ok = this.integrateLayers()
            }
            if ok
            {
                ok = this.outputRenderTexture( dstPtr )
            }
            ret ok
        }

        # ── P0 数据层：FrameData 构建 / 相机场景渲染（数据与流程分离）──

        # buildFrameData(time, dstPixels) —— 采集一帧渲染上下文成 FrameData
        # （P0 为数据快照；P1+ Pass 体系将消费这些字段）
        public FrameData buildFrameData( Float32 time, Int64 dstPixels )
        {
            FrameData fd = FrameData()
            fd.time = time
            fd.dstPixels = dstPixels
            fd.targetHandle = RenderPipeline.TARGET_SCENE
            fd.targetW = this._width
            fd.targetH = this._height
            fd.envBackend = Render.currentBackend()
            fd.envRenderer = Render.rendererInfo()
            fd.envVersion = Render.versionInfo()
            ret fd
        }

        # renderCameraScene(fd) —— 以 FrameData 驱动一帧（P0 转发 runStages；
        # 2026-11-18：SRP 草稿链（CameraRenderPipeline 资产层路由）已整体
        # 移除，本方法恒走 13 阶段 runStages，语义 = FrameData 快照驱动）
        public bool renderCameraScene( FrameData fd )
        {
            if this._handle == 0
            {
                ret false
            }
            if fd == null
            {
                ret false
            }
            if fd.dstPixels == 0
            {
                ret false
            }
            ret this.runStages( fd.time, fd.dstPixels )
        }

        # stat(id) —— 管线统计（STAT_* 常量）
        public Int32 stat( Int32 id )
        {
            if this._handle == 0
            {
                ret 0
            }
            ret RenderPipeline.ffiStat( this._handle, id )
        }

        override string toString()
        {
            ret "RenderPipeline(" + this._width.toString() + "x" + this._height.toString() + ")"
        }

        # ── FFI 绑定（sl_render_lib.dll，函数体为兜底返回）─────────

        @DllStaticImport( "sl_render_lib", "slr_pipeline_create", "i32,i32->i64" )
        static Int64 ffiPipelineCreate( Int32 w, Int32 h )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_destroy", "i64->bool" )
        static bool ffiPipelineDestroy( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_resize", "i64,i32,i32->bool" )
        static bool ffiPipelineResize( Int64 p, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_frame_count", "i64->i64" )
        static Int64 ffiPipelineFrameCount( Int64 p )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_camera", "i64,i32,f32,f32,f32,f32->bool" )
        static bool ffiSetCamera( Int64 p, Int32 mask, Float32 l, Float32 r, Float32 b, Float32 t )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_clear_color", "i64,f32,f32,f32,f32->bool" )
        static bool ffiSetClearColor( Int64 p, Float32 r, Float32 g, Float32 b, Float32 a )

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_sky_top", "i64,f32,f32,f32->bool" )
        static bool ffiSetSkyTop( Int64 p, Float32 r, Float32 g, Float32 b )

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_sky_bottom", "i64,f32,f32,f32->bool" )
        static bool ffiSetSkyBottom( Int64 p, Float32 r, Float32 g, Float32 b )

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_sky_on", "i64,i32->bool" )
        static bool ffiSetSkyOn( Int64 p, Int32 on )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_sky_cube", "i64,i64->i32" )
        static Int32 ffiSetSkyCube( Int64 p, Int64 tex )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_sky_cube_cam", "i64,ptr->i32" )
        static Int32 ffiSetSkyCubeCam( Int64 p, Int64 camPtr )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_sky_last_mode", "i64->i32" )
        static Int32 ffiSkyLastMode( Int64 pipe )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_sky_draw_diag", "i64->i32" )
        static Int32 ffiSkyDrawDiag( Int64 pipe )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_sky_prog_handle", "i64->i32" )
        static Int32 ffiSkyProgHandle( Int64 pipe )
        {
            ret 0
        }

        # skyDrawDiag(pipe) —— 诊断：最近一次 draw_sky_cube 的 glGetError
        # （-1 = 未调用过；带 pipe 形参规避零参绑定）
        public Int32 skyDrawDiag( Int64 pipe )
        {
            ret RenderPipeline.ffiSkyDrawDiag( pipe )
        }

        # skyProgHandle(pipe) —— 诊断：SKY_CUBE 程序句柄（0 = 创建失败）
        public Int32 skyProgHandle( Int64 pipe )
        {
            ret RenderPipeline.ffiSkyProgHandle( pipe )
        }

        # skyLastMode(pipe) —— 诊断：最近一帧天空绘制模式（0=未画 1=渐变
        # 2=cube；零参 DllStaticImport 无先例会静默丢成员——带 pipe 形参）
        public Int32 skyLastMode( Int64 pipe )
        {
            ret RenderPipeline.ffiSkyLastMode( pipe )
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_post", "i64,i32,f32,f32,f32->bool" )
        static bool ffiSetPost( Int64 p, Int32 enable, Float32 brightness, Float32 saturation, Float32 vignette )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_post_params", "i64,ptr->bool" )
        static bool ffiSetPostParams( Int64 p, Int64 prmPtr )
        {
            ret false
        }

        # v3.6 AA + MotionVectors FFI
        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_aa", "i64,i32,i32,f32->i32" )
        static Int32 ffiSetAa( Int64 p, Int32 msaa, Int32 fxaaOn, Float32 fxaaSpan )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_motion", "i64,i32->bool" )
        static bool ffiSetMotion( Int64 p, Int32 on )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_output_motion_texture", "i64,i64->bool" )
        static bool ffiOutputMotion( Int64 p, Int64 dstPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_taa", "i64,i32,f32->bool" )
        static bool ffiSetTaa( Int64 p, Int32 on, Float32 blend )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_motion_blur", "i64,i32,f32,i32->bool" )
        static bool ffiSetMotionBlur( Int64 p, Int32 on, Float32 scale, Int32 samples )
        {
            ret false
        }

        # ── 多相机 FFI ────────────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_camera_create", "i64,i32->i64" )
        static Int64 ffiCameraCreate( Int64 p, Int32 depth )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_destroy", "i64,i64->bool" )
        static bool ffiCameraDestroy( Int64 p, Int64 cam )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_count", "i64->i32" )
        static Int32 ffiCameraCount( Int64 p )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_object_create", "i64,i32->i64" )
        static Int64 ffiObjectCreate( Int64 p, Int32 meshKind )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_object_destroy", "i64,i64->bool" )
        static bool ffiObjectDestroy( Int64 p, Int64 obj )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_mesh_upload", "i32,ptr,i32->bool" )
        static bool ffiMeshUpload( Int32 slot, Int64 vertsPtr, Int32 vertCount )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_count", "i64->i32" )
        static Int32 ffiObjectCount( Int64 p )
        {
            ret 0
        }

        # ── 光照 FFI ────────────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_light_set", "i64,i32,i32,ptr->bool" )
        static bool ffiLightSet( Int64 p, Int32 slot, Int32 type, Int64 paramsPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_light_clear", "i64,i32->bool" )
        static bool ffiLightClear( Int64 p, Int32 slot )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_light_count", "i64->i32" )
        static Int32 ffiLightCount( Int64 p )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_light_set_ambient", "i64,f32->bool" )
        static bool ffiLightSetAmbient( Int64 p, Float32 ambient )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_begin_frame", "i64,f32->bool" )
        static bool ffiBeginFrame( Int64 p, Float32 time )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_prepare_materials", "i64->bool" )
        static bool ffiPrepareMaterials( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_early_update", "i64->bool" )
        static bool ffiEarlyUpdate( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_cull_layers", "i64->bool" )
        static bool ffiCullLayers( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_assemble_layer_data", "i64->bool" )
        static bool ffiAssembleLayerData( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_upload_render_data", "i64->bool" )
        static bool ffiUploadRenderData( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_render_shader_chunks", "i64->bool" )
        static bool ffiRenderShaderChunks( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_update_core_time", "i64->bool" )
        static bool ffiUpdateCoreTime( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_render_shader_segments", "i64->bool" )
        static bool ffiRenderShaderSegments( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_assemble_rendered_layers", "i64->bool" )
        static bool ffiAssembleRenderedLayers( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_taa", "i64->bool" )
        static bool ffiTaa( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_motion_blur", "i64->bool" )
        static bool ffiMotionBlur( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_post_process", "i64->bool" )
        static bool ffiPostProcess( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_integrate_layers", "i64->bool" )
        static bool ffiIntegrateLayers( Int64 p )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_output_render_texture", "i64,ptr->bool" )
        static bool ffiOutputRenderTexture( Int64 p, Int64 dstPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_render_frame", "i64,f32,ptr->bool" )
        static bool ffiRenderFrame( Int64 p, Float32 time, Int64 dstPtr )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_stat", "i64,i32->i32" )
        static Int32 ffiStat( Int64 p, Int32 id )
        {
            ret 0
        }
    }
}
