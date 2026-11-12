# =========================================================================
# UnityPipeline —— Unity 风格渲染管线 SL 门面（薄绑定，逻辑全在 C 层）
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
#   11 postProcess           后处理（亮度/饱和度/暗角全屏 pass）
#   12 integrateLayers       层级的逻辑整合（合成到最终 renderTexture）
#   13 outputRenderTexture   输出最终渲染 renderTexture（RGBA8 回读）
#
# 用法（renderTexture 通道，QT QLabel.setPixmapRgba 对接）：
#   SLang.Render.initialize()
#   SLang.UnityRenderPipeline pipe = SLang.UnityRenderPipeline.create( 256, 256 )
#   SLang.UnityRenderObject tri = pipe.addObject( pipe.MESH_TRIANGLE )
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
    # UnityRenderPipeline —— 13 阶段管线门面
    # ===================================================================
    public class UnityRenderPipeline
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

        public static UnityRenderPipeline create( Int32 width, Int32 height )
        {
            Int64 h = UnityRenderPipeline.ffiPipelineCreate( width, height )
            if h == 0
            {
                ret null
            }
            ret UnityRenderPipeline( h, width, height )
        }

        public bool destroy()
        {
            if this._handle == 0
            {
                ret false
            }
            bool ok = UnityRenderPipeline.ffiPipelineDestroy( this._handle )
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
            if UnityRenderPipeline.ffiPipelineResize( this._handle, width, height ) == false
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
            ret UnityRenderPipeline.ffiPipelineFrameCount( this._handle )
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
            ret UnityRenderPipeline.ffiSetCamera( this._handle, cullMask, l, r, b, t )
        }

        # ── 多相机（槽 0 为默认相机；渲染按 depth 升序逐相机执行）──

        # addCamera(depth) —— 新建相机槽，返回 UnityRenderCamera
        public UnityRenderCamera addCamera( Int32 depth )
        {
            if this._handle == 0
            {
                ret null
            }
            Int64 id = UnityRenderPipeline.ffiCameraCreate( this._handle, depth )
            if id == 0
            {
                ret null
            }
            ret UnityRenderCamera( this._handle, id )
        }

        public bool removeCamera( UnityRenderCamera cam )
        {
            if this._handle == 0 || cam == null || cam.isValid == false
            {
                ret false
            }
            ret UnityRenderPipeline.ffiCameraDestroy( this._handle, cam.handle )
        }

        public Int32 cameraCount()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret UnityRenderPipeline.ffiCameraCount( this._handle )
        }

        public bool setClearColor( Float32 r, Float32 g, Float32 b, Float32 a )
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiSetClearColor( this._handle, r, g, b, a )
        }

        # setPostEffect(enable, brightness, saturation, vignette)
        #   enable=0 纯拷贝；vignette 0..1 暗角强度
        public bool setPostEffect( Int32 enable, Float32 brightness, Float32 saturation, Float32 vignette )
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiSetPost( this._handle, enable, brightness, saturation, vignette )
        }

        # ── 场景对象 ─────────────────────────────────────────────

        public UnityRenderObject addObject( Int32 meshKind )
        {
            if this._handle == 0
            {
                ret null
            }
            Int64 id = UnityRenderPipeline.ffiObjectCreate( this._handle, meshKind )
            if id == 0
            {
                ret null
            }
            ret UnityRenderObject( this._handle, id )
        }

        # uploadMesh(slot, vertsPtr, vertCount) —— 上传动态网格（3D/程序化
        # 几何通道）：vertsPtr 指向三角形列表（pos2+uv2 交错，stride 16B，
        # SL 侧 Memory.writeF32 填充）。对象 meshKind = MESH_CUSTOM + slot
        # 引用该槽；每帧可重复调用实现顶点动画。
        public bool uploadMesh( Int32 slot, Int64 vertsPtr, Int32 vertCount )
        {
            ret UnityRenderPipeline.ffiMeshUpload( slot, vertsPtr, vertCount )
        }

        public bool removeObject( UnityRenderObject obj )
        {
            if this._handle == 0 || obj == null || obj.isValid == false
            {
                ret false
            }
            ret UnityRenderPipeline.ffiObjectDestroy( this._handle, obj.handle )
        }

        public Int32 objectCount()
        {
            if this._handle == 0
            {
                ret 0
            }
            ret UnityRenderPipeline.ffiObjectCount( this._handle )
        }

        # ── 13 阶段（逐阶段驱动）────────────────────────────────

        public bool beginFrame( Float32 time )
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiBeginFrame( this._handle, time )
        }

        public bool prepareMaterials()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiPrepareMaterials( this._handle )
        }

        public bool earlyUpdate()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiEarlyUpdate( this._handle )
        }

        public bool cullLayers()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiCullLayers( this._handle )
        }

        public bool assembleLayerData()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiAssembleLayerData( this._handle )
        }

        public bool uploadRenderData()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiUploadRenderData( this._handle )
        }

        public bool renderShaderChunks()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiRenderShaderChunks( this._handle )
        }

        public bool updateCoreTime()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiUpdateCoreTime( this._handle )
        }

        public bool renderShaderSegments()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiRenderShaderSegments( this._handle )
        }

        public bool assembleRenderedLayers()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiAssembleRenderedLayers( this._handle )
        }

        public bool postProcess()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiPostProcess( this._handle )
        }

        public bool integrateLayers()
        {
            if this._handle == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiIntegrateLayers( this._handle )
        }

        public bool outputRenderTexture( Int64 dstPtr )
        {
            if this._handle == 0 || dstPtr == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiOutputRenderTexture( this._handle, dstPtr )
        }

        # renderFrame —— 一键全流程（C 层依序执行 1..13）
        public bool renderFrame( Float32 time, Int64 dstPtr )
        {
            if this._handle == 0 || dstPtr == 0
            {
                ret false
            }
            ret UnityRenderPipeline.ffiRenderFrame( this._handle, time, dstPtr )
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

        # stat(id) —— 管线统计（STAT_* 常量）
        public Int32 stat( Int32 id )
        {
            if this._handle == 0
            {
                ret 0
            }
            ret UnityRenderPipeline.ffiStat( this._handle, id )
        }

        override string toString()
        {
            ret "UnityRenderPipeline(" + this._width.toString() + "x" + this._height.toString() + ")"
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
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_pipeline_set_post", "i64,i32,f32,f32,f32->bool" )
        static bool ffiSetPost( Int64 p, Int32 enable, Float32 brightness, Float32 saturation, Float32 vignette )
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

    # ===================================================================
    # UnityRenderObject —— 场景对象门面（网格/材质参数/变换/层级）
    # ===================================================================
    public class UnityRenderObject
    {
        Int64 _pipe = 0
        Int64 _id = 0

        _init_( Int64 pipe, Int64 id )
        {
            this._pipe = pipe
            this._id = id
        }

        get Int64 handle()
        {
            ret this._id
        }

        get bool isValid()
        {
            ret this._id != 0
        }

        public bool setVisible( Int32 visible )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret UnityRenderObject.ffiSetVisible( this._pipe, this._id, visible )
        }

        public bool setLayer( Int32 layer )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret UnityRenderObject.ffiSetLayer( this._pipe, this._id, layer )
        }

        # setQueue —— 渲染队列（<2500 不透明，>=2500 透明）
        public bool setQueue( Int32 queue )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret UnityRenderObject.ffiSetQueue( this._pipe, this._id, queue )
        }

        public bool setPosition( Float32 x, Float32 y, Float32 z )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret UnityRenderObject.ffiSetPosition( this._pipe, this._id, x, y, z )
        }

        public bool setRotationZ( Float32 rz )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret UnityRenderObject.ffiSetRotationZ( this._pipe, this._id, rz )
        }

        public bool setScale( Float32 sx, Float32 sy )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret UnityRenderObject.ffiSetScale( this._pipe, this._id, sx, sy )
        }

        public bool setColor( Float32 r, Float32 g, Float32 b, Float32 a )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret UnityRenderObject.ffiSetColor( this._pipe, this._id, r, g, b, a )
        }

        public bool setTexture( UnityRenderTexture tex )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            Int64 h = 0
            if tex != null
            {
                h = tex.handle
            }
            ret UnityRenderObject.ffiSetTexture( this._pipe, this._id, h )
        }

        public bool setAnimated( Int32 mode, Float32 speed )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret UnityRenderObject.ffiSetAnimated( this._pipe, this._id, mode, speed )
        }

        public bool destroy()
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            bool ok = UnityRenderObject.ffiObjectDestroy( this._pipe, this._id )
            if ok
            {
                this._id = 0
            }
            ret ok
        }

        # ── FFI 绑定 ──────────────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_object_set_visible", "i64,i64,i32->bool" )
        static bool ffiSetVisible( Int64 p, Int64 obj, Int32 visible )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_layer", "i64,i64,i32->bool" )
        static bool ffiSetLayer( Int64 p, Int64 obj, Int32 layer )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_queue", "i64,i64,i32->bool" )
        static bool ffiSetQueue( Int64 p, Int64 obj, Int32 queue )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_position", "i64,i64,f32,f32,f32->bool" )
        static bool ffiSetPosition( Int64 p, Int64 obj, Float32 x, Float32 y, Float32 z )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_rotation_z", "i64,i64,f32->bool" )
        static bool ffiSetRotationZ( Int64 p, Int64 obj, Float32 rz )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_scale", "i64,i64,f32,f32->bool" )
        static bool ffiSetScale( Int64 p, Int64 obj, Float32 sx, Float32 sy )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_color", "i64,i64,f32,f32,f32,f32->bool" )
        static bool ffiSetColor( Int64 p, Int64 obj, Float32 r, Float32 g, Float32 b, Float32 a )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_texture", "i64,i64,i64->bool" )
        static bool ffiSetTexture( Int64 p, Int64 obj, Int64 tex )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_animated", "i64,i64,i32,f32->bool" )
        static bool ffiSetAnimated( Int64 p, Int64 obj, Int32 mode, Float32 speed )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_destroy", "i64,i64->bool" )
        static bool ffiObjectDestroy( Int64 p, Int64 obj )
        {
            ret false
        }
    }

    # ===================================================================
    # UnityRenderTexture —— 贴图门面（top-down RGBA8 上传）
    # ===================================================================
    public class UnityRenderTexture
    {
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

        # createRgba(ptr, w, h) —— ptr 为 Memory.alloc 的 RGBA8 像素块
        #（行主序、顶行在前；C 层内部翻行为 GL bottom-up）
        public static UnityRenderTexture createRgba( Int64 ptr, Int32 width, Int32 height )
        {
            if ptr == 0 || width <= 0 || height <= 0
            {
                ret null
            }
            Int64 h = UnityRenderTexture.ffiTextureCreateRgba( width, height, ptr )
            if h == 0
            {
                ret null
            }
            ret UnityRenderTexture( h, width, height )
        }

        # loadFile(path) —— 从图片文件创建纹理（C 层 WIC 解码，
        # 支持 PNG/JPEG/BMP/TIFF 等；path 为 UTF-8）
        public static UnityRenderTexture loadFile( string path )
        {
            if path == null || path.length() == 0
            {
                ret null
            }
            Int64 h = UnityRenderTexture.ffiTextureLoadFile( path )
            if h == 0
            {
                ret null
            }
            # 尺寸由 C 层注册表管理；门面仅记录句柄，宽高留 0
            ret UnityRenderTexture( h, 0, 0 )
        }

        public bool destroy()
        {
            if this._handle == 0
            {
                ret false
            }
            bool ok = UnityRenderTexture.ffiTextureDestroy( this._handle )
            if ok
            {
                this._handle = 0
            }
            ret ok
        }

        override string toString()
        {
            ret "UnityRenderTexture(" + this._width.toString() + "x" + this._height.toString() + ")"
        }

        # ── FFI 绑定 ──────────────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_texture_create_rgba", "i32,i32,ptr->i64" )
        static Int64 ffiTextureCreateRgba( Int32 w, Int32 h, Int64 dataPtr )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_texture_load_file", "utf8->i64" )
        static Int64 ffiTextureLoadFile( string path )
        {
            ret 0
        }

        @DllStaticImport( "sl_render_lib", "slr_texture_destroy", "i64->bool" )
        static bool ffiTextureDestroy( Int64 tex )
        {
            ret false
        }
    }

    # ===================================================================
    # UnityRenderCamera —— 管线相机门面（多相机渲染）
    # ----------------------------------------------------------------------------
    # 槽 0 为默认相机（UnityRenderPipeline.setCamera 写入，不经过本类）。
    # 新建相机经 UnityRenderPipeline.addCamera(depth)：depth 升序决定
    # 绘制次序（小 depth 先画）。每相机独立：
    #   cullingMask  —— 按位对应 layer 0..31（-1 = 全部）
    #   extents      —— 正交视域（NDC 前的世界系包围盒）
    #   viewport     —— 输出目标内像素视口
    #   clearColor   —— 本相机清屏色
    #   clearFlags   —— 位 1 = 清颜色、位 2 = 清深度（叠加相机可清 0）
    # ===================================================================
    public class UnityRenderCamera
    {
        Int64 _pipe = 0
        Int64 _id = 0

        _init_( Int64 pipe, Int64 id )
        {
            this._pipe = pipe
            this._id = id
        }

        get Int64 handle()
        {
            ret this._id
        }

        get bool isValid()
        {
            ret this._id != 0 && this._pipe != 0
        }

        public bool setEnabled( bool enabled )
        {
            if this.isValid == false
            {
                ret false
            }
            ret UnityRenderCamera.ffiCameraSetEnabled( this._pipe, this._id, enabled ? 1 : 0 )
        }

        public bool setDepth( Int32 depth )
        {
            if this.isValid == false
            {
                ret false
            }
            ret UnityRenderCamera.ffiCameraSetDepth( this._pipe, this._id, depth )
        }

        public bool setCullMask( Int32 mask )
        {
            if this.isValid == false
            {
                ret false
            }
            ret UnityRenderCamera.ffiCameraSetCullMask( this._pipe, this._id, mask )
        }

        # setExtents(l, r, b, t) —— 正交视域
        public bool setExtents( Float32 l, Float32 r, Float32 b, Float32 t )
        {
            if this.isValid == false
            {
                ret false
            }
            ret UnityRenderCamera.ffiCameraSetExtents( this._pipe, this._id, l, r, b, t )
        }

        # setViewport(x, y, w, h) —— 输出目标内像素视口
        public bool setViewport( Int32 x, Int32 y, Int32 w, Int32 h )
        {
            if this.isValid == false
            {
                ret false
            }
            ret UnityRenderCamera.ffiCameraSetViewport( this._pipe, this._id, x, y, w, h )
        }

        public bool setClearColor( Float32 r, Float32 g, Float32 b, Float32 a )
        {
            if this.isValid == false
            {
                ret false
            }
            ret UnityRenderCamera.ffiCameraSetClearColor( this._pipe, this._id, r, g, b, a )
        }

        # setClearFlags(flags) —— 位 1 = 清颜色，位 2 = 清深度
        public bool setClearFlags( Int32 flags )
        {
            if this.isValid == false
            {
                ret false
            }
            ret UnityRenderCamera.ffiCameraSetClearFlags( this._pipe, this._id, flags )
        }

        public bool destroy()
        {
            if this.isValid == false
            {
                ret false
            }
            bool ok = UnityRenderCamera.ffiCameraDestroy( this._pipe, this._id )
            if ok
            {
                this._id = 0
            }
            ret ok
        }

        # ── FFI 绑定 ──────────────────────────────────────────────

        @DllStaticImport( "sl_render_lib", "slr_camera_set_enabled", "i64,i64,i32->bool" )
        static bool ffiCameraSetEnabled( Int64 p, Int64 cam, Int32 enabled )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_depth", "i64,i64,i32->bool" )
        static bool ffiCameraSetDepth( Int64 p, Int64 cam, Int32 depth )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_cull_mask", "i64,i64,i32->bool" )
        static bool ffiCameraSetCullMask( Int64 p, Int64 cam, Int32 mask )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_extents", "i64,i64,f32,f32,f32,f32->bool" )
        static bool ffiCameraSetExtents( Int64 p, Int64 cam, Float32 l, Float32 r, Float32 b, Float32 t )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_viewport", "i64,i64,i32,i32,i32,i32->bool" )
        static bool ffiCameraSetViewport( Int64 p, Int64 cam, Int32 x, Int32 y, Int32 w, Int32 h )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_clear_color", "i64,i64,f32,f32,f32,f32->bool" )
        static bool ffiCameraSetClearColor( Int64 p, Int64 cam, Float32 r, Float32 g, Float32 b, Float32 a )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_set_clear_flags", "i64,i64,i32->bool" )
        static bool ffiCameraSetClearFlags( Int64 p, Int64 cam, Int32 flags )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_camera_destroy", "i64,i64->bool" )
        static bool ffiCameraDestroy( Int64 p, Int64 cam )
        {
            ret false
        }
    }
}
