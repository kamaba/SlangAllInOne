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
    # RenderObject —— 场景对象门面（网格/材质参数/变换/层级）
    # ===================================================================
    public class RenderObject
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
            ret RenderObject.ffiSetVisible( this._pipe, this._id, visible )
        }

        public bool setLayer( Int32 layer )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetLayer( this._pipe, this._id, layer )
        }

        # setQueue —— 渲染队列（<2500 不透明，>=2500 透明）
        public bool setQueue( Int32 queue )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetQueue( this._pipe, this._id, queue )
        }

        public bool setPosition( Float32 x, Float32 y, Float32 z )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetPosition( this._pipe, this._id, x, y, z )
        }

        public bool setRotationZ( Float32 rz )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetRotationZ( this._pipe, this._id, rz )
        }

        public bool setScale( Float32 sx, Float32 sy )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetScale( this._pipe, this._id, sx, sy )
        }

        public bool setColor( Float32 r, Float32 g, Float32 b, Float32 a )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetColor( this._pipe, this._id, r, g, b, a )
        }

        public bool setTexture( RenderTexture tex )
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
            ret RenderObject.ffiSetTexture( this._pipe, this._id, h )
        }

        public bool setAnimated( Int32 mode, Float32 speed )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetAnimated( this._pipe, this._id, mode, speed )
        }

        # v3.4：材质模型 —— MATERIAL_LAMBERT(0)=v3.3 光照，MATERIAL_PHONG(1)=
        # 追加伪 3D 高光（ambient+diffuse+specular），阶段 5 自动选程序槽。
        public bool setMaterial( Int32 material )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetMaterial( this._pipe, this._id, material )
        }

        # v3.4：Phong 高光参数（strength 高光强度 0..8，shininess 光泽度 1..256）。
        public bool setSpecular( Float32 strength, Float32 shininess )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetSpecular( this._pipe, this._id, strength, shininess )
        }

        # v3.4：投影阴影开关 —— 1 = 生成 2D 投影阴影绘制项（透明段黑 0.35，
        # 沿背离光源方向偏移；直射光方向优先，否则按聚光位置逐物体定向，
        # 聚光摇晃时阴影跟随）。无光源时不生成。
        public bool setShadow( Int32 castShadow )
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            ret RenderObject.ffiSetShadow( this._pipe, this._id, castShadow )
        }

        public bool destroy()
        {
            if this._pipe == 0 || this._id == 0
            {
                ret false
            }
            bool ok = RenderObject.ffiObjectDestroy( this._pipe, this._id )
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

        @DllStaticImport( "sl_render_lib", "slr_object_set_material", "i64,i64,i32->bool" )
        static bool ffiSetMaterial( Int64 p, Int64 obj, Int32 material )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_specular", "i64,i64,f32,f32->bool" )
        static bool ffiSetSpecular( Int64 p, Int64 obj, Float32 strength, Float32 shininess )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_set_shadow", "i64,i64,i32->bool" )
        static bool ffiSetShadow( Int64 p, Int64 obj, Int32 castShadow )
        {
            ret false
        }

        @DllStaticImport( "sl_render_lib", "slr_object_destroy", "i64,i64->bool" )
        static bool ffiObjectDestroy( Int64 p, Int64 obj )
        {
            ret false
        }
    }
}
