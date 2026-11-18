import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# RenderSystem — 渲染系统总管（system/ 层，仿 Unity RenderPipeline 管理，
# doc/05 §3 Submit 段落地）
# ----------------------------------------------------------------------------
# 职责：持有 SLang.RenderPipeline（SLangRender 13 阶段管线门面），每个
# 渲染帧把引擎场景经 Batcher 聚组后提交为 RenderObject（直通路径：
# 内置网格 meshKind + RenderObject 字段变换，doc/05 §3.1 例外）。
# 烘焙组（BatchGroup.singleObject=false 的动态网格合批）v1 暂跳过并计数
# （需要 uploadMesh 显存交错顶点 + 相机投影专项，doc/05 §3 全量路径）。
# 跨模块消费形态（doc/10 §6 / §1.3）：
#   - 引用顺序规则：消费方 Core/Std/Math 必须在 references 最前；
#   - SLangRender 类型用 namespace 限定声明（`SLang.RenderPipeline`）；
#   - 实例方法调用可靠（addObject/setPosition/renderFrame 先例 RenderTest）。
# ============================================================================

public class RenderSystem
{
    public Batcher batcher = Batcher()
    public Int32 cullMask = 0x7FFFFFFF
    public Int32 bakedSkipped = 0
    public Int32 lastSubmitted = 0
    # v1 正交相机（doc/09 步骤 9 的简化形态）：世界坐标 → NDC =
    # (world - center) / viewSize（viewSize 为视口半宽，世界单位）
    public Float32_3 cameraCenter = Float32_3.zero()
    public Float32 viewSize = 10.0f
    # 渲染目标像素尺寸（Unity 式动态分辨率；resize() 同步维护）。
    # viewSize 语义 = 视口纵向半高（Unity orthographicSize），
    # 横向半宽 = viewSize × aspect（aspect = pixW / pixH）。
    Int32 pixW = 0
    Int32 pixH = 0

    SLang.RenderPipeline _pipe = null
    public string lastError = ""
    # 对象句柄池（**只存 Int64**——跨模块对象存 SL List 会污染实例字段，
    # destroy 静默失败：RenderSystem 烘焙组实测，QT 轮同族坑）
    List<Int64> _objIds = List<Int64>( 0 )

    # ── P7 2D（doc/15）────────────────────────────────────
    # 排序层 → queue 基值映射表（全局一份，消费方可 setBase 覆盖）
    public SortingLayers layers = SortingLayers()
    public Int32 lastSubmitted2D = 0
    # 精灵平行数组（collect2D 收集上下文一次读全；排序/提交只消费标量——
    # Batcher 同款架构约束，doc/10 §6）。pivot 偏移已在收集期计入 _spX/_spY。
    List<GameObject> _spGo = List<GameObject>( 16 )
    List<Int32> _spQueue = List<Int32>( 16 )
    List<Int32> _spLayer = List<Int32>( 16 )
    List<Float32> _spX = List<Float32>( 16 )
    List<Float32> _spY = List<Float32>( 16 )
    List<Float32> _spZ = List<Float32>( 16 )
    List<Float32> _spRot = List<Float32>( 16 )
    List<Float32> _spW = List<Float32>( 16 )
    List<Float32> _spH = List<Float32>( 16 )
    List<Float32_3> _spColor = List<Float32_3>( 16 )
    List<Float32> _spAlpha = List<Float32>( 16 )
    # 2D 独立对象句柄池（与 3D 分开回收——同帧 sync()+sync2D() 互不误杀）
    List<Int64> _objIds2D = List<Int64>( 16 )
    # 烘焙组 uploadMesh 槽位轮转（MESH_CUSTOM slot 0..3）
    Int32 _bakeCursor = 0

    # 初始化渲染管线（离屏 FBO 目标 w×h）。
    # 前置：SLang.Render.initialize()（FFI 库装载，幂等；Pipeline.sl 头注释约定）
    public bool init( Int32 width, Int32 height )
    {
        if this._pipe != null
        {
            ret true
        }
        SLang.Render.initialize()
        SLang.RenderPipeline p = SLang.RenderPipeline.create( width, height )
        if p == null
        {
            this.lastError = SLang.Render.errorString()
            ret false
        }
        this._pipe = p
        this.pixW = width
        this.pixH = height
        ret true
    }

    public bool ready()
    {
        ret this._pipe != null
    }

    # ── 窗口式动态分辨率（Unity OnResize 语义，2026-11-18）────
    # 转发 pipe.resize（slr_pipeline_resize：FBO/视口重建，RenderObject
    # 句柄全部保留）；像素尺寸字段同步供 aspect 修正消费。
    public bool resize( Int32 width, Int32 height )
    {
        if this._pipe == null || width < 16 || height < 16
        {
            ret false
        }
        bool ok = this._pipe.resize( width, height )
        if ok
        {
            this.pixW = width
            this.pixH = height
        }
        ret ok
    }

    # 视口宽高比（w/h；未初始化或退化值回退 1.0 = 方形旧行为；
    # 钳 [0.1, 10] 防极端窗口形状除零/爆值）
    Float32 aspectX()
    {
        if this.pixH < 1
        {
            ret 1.0f
        }
        Float32 a = this.pixW.toFloat32() / this.pixH.toFloat32()
        if a < 0.1f
        {
            ret 0.1f
        }
        if a > 10.0f
        {
            ret 10.0f
        }
        ret a
    }

    # ── P6 渐变天空背景 ─────────────────────────────────
    # 转发 SLang.RenderPipeline.setSkyColor/setSkyEnabled（每相机清屏后
    # 画全屏渐变 quad，物体随后覆盖；doc/13 §4 v0.1 背景层）。
    # top/bottom 为 RGB 0..1；enabled=false 关闭回到纯清屏色。
    public bool setSky( Float32_3 top, Float32_3 bottom )
    {
        if this._pipe == null
        {
            ret false
        }
        ret this._pipe.setSkyColor( top.x, top.y, top.z, bottom.x, bottom.y, bottom.z )
    }

    public bool setSkyEnabled( bool on )
    {
        if this._pipe == null
        {
            ret false
        }
        Int32 v = 0
        if on
        {
            v = 1
        }
        ret this._pipe.setSkyEnabled( v )
    }

    # 排序层基值设置（转发 layers.setBase；消费方跨模块 a.b() 链规避）
    public void setLayerBase( Int32 layer, Int32 baseValue )
    {
        this.layers.setBase( layer, baseValue )
    }

    # cubemap 天空（doc/13 §2.1 第二步）：转发 pipe.setSkyCube——
    # tex 用 RenderTexture.createCubeTexture 产物的 handle；非 0 且
    # GL/GLES 后端时阶段 7 天空改走 cube 采样（0 回退渐变路径）
    public bool setSkyCube( Int64 texHandle )
    {
        if this._pipe == null
        {
            ret false
        }
        ret this._pipe.setSkyCube( texHandle )
    }

    # 管线句柄访问（诊断/高级用法；消费方直接调 pipe.stat 等）
    public SLang.RenderPipeline pipe()
    {
        ret this._pipe
    }

    # ── P8 Volume：参数栈下发（doc/14 §5 过渡映射）────────
    # contributing=0 → 后处理关闭（enable=0 纯拷贝）；混合数学在 C
    # （VolumeSystem.compute → sle_volume_blend），本方法只做门面转发。
    public bool applyPost( VolumeStack st )
    {
        if this._pipe == null
        {
            ret false
        }
        if st == null
        {
            ret false
        }
        Int32 en = 0
        if st.contributing > 0
        {
            en = 1
        }
        ret this._pipe.setPostEffect( en, st.brightness, st.saturation, st.vignette )
    }

    # 场景光源收集（v2.13）：sync 每帧先收集 LightData 写管线光照槽 0..7
    public Int32 lightCount = 0

    # 场景 → RenderObject 同步（直通组）；返回本帧提交对象数
    public Int32 sync( Scene scene )
    {
        if this._pipe == null
        {
            ret 0 - 1
        }
        this.recycle()
        this.applyLights( scene )
        this.batcher.collect( scene, this.cullMask )
        this.batcher.build()
        Float32 ax = this.aspectX()
        Float32 cxw = this.cameraCenter.x
        Float32 cyw = this.cameraCenter.y
        Float32 hw = this.viewSize * ax
        Int32 i = 0
        Int32 n = this.batcher.groupCount()
        Int32 submitted = 0
        while i < n
        {
            BatchGroup g = this.batcher.groupAt( i )
            if g.singleObject
            {
                GameObject go = g.soleMember
                Transform t = go.transform
                Float32_3 wp = t.worldPosition()
                Float32 wrz = t.worldRotationZ()
                Float32_3 ws = t.worldScale()
                SLang.RenderObject ro = this._pipe.addObject( g.meshKind )
                if ro != null
                {
                    # 世界 → NDC（正交相机；z 作深度序直传）。
                    # 纵向半高 = viewSize（Unity orthographicSize 语义），
                    # 横向半宽 = viewSize × aspect —— 窗口非方形时内容
                    # 不被拉伸，只是视野横向变宽/变窄。
                    Float32 dxw = wp.x - cxw
                    Float32 dyw = wp.y - cyw
                    Float32 nx = dxw / hw
                    Float32 ny = dyw / this.viewSize
                    ro.setPosition( nx, ny, wp.z )
                    ro.setRotationZ( wrz )
                    Float32 swx = ws.x / hw
                    Float32 swy = ws.y / this.viewSize
                    ro.setScale( swx, swy )
                    ro.setColor( g.color.x, g.color.y, g.color.z, 1.0f )
                    # v2.13：材质消费（模型/高光/贴图/阴影/队列）
                    MaterialData md = g.material
                    if md != null
                    {
                        ro.setMaterial( md.materialModel )
                        ro.setSpecular( md.specular, md.shininess )
                        SLang.RenderTexture tex = md.texture
                        if tex != null
                        {
                            ro.setTexture( tex )
                        }
                        if md.castShadow
                        {
                            ro.setShadow( 1 )
                        }
                        ro.setQueue( g.renderQueue )
                    }
                    this._objIds.add( ro.handle )
                    submitted = submitted + 1
                }
            }
            else
            {
                # 烘焙组提交（P7 收尾，doc/05 §3 全量路径；2026-11-17）：
                # bakeVerticesInto 世界顶点 → C 正交投影（sle_ortho_bake，
                # 世界→NDC 仿射与直通组同式）→ uploadMesh（MESH_CUSTOM
                # pos2+uv2 NDC 语义，slot 0..3 轮转，单组上限 4096 顶点）
                List<Float32_3> baked = List<Float32_3>( 0 )
                g.bakeVerticesInto( baked )
                Int32 vn = baked.length
                if vn > 4096
                {
                    vn = 4096
                }
                if vn > 0
                {
                    Int64 srcPtr = Memory.alloc( vn * 12 )
                    Int64 dstPtr = Memory.alloc( vn * 16 )
                    Int64 cptr = Memory.alloc( 12 )
                    bool blocksOk = ( srcPtr != 0 ) && ( dstPtr != 0 )
                    bool allOk = blocksOk && ( cptr != 0 )
                    if allOk
                    {
                        Int32 vi = 0
                        while vi < vn
                        {
                            Float32_3 v = baked[vi]
                            Int32 off = vi * 12
                            # x 预缩放（绕相机中心）：bake 的 NDC_x = (x'-cx)/viewSize，
                            # 令 x' = cx + (x-cx)/aspect 后等效 (x-cx)/(viewSize×aspect)，
                            # 与直通组横向映射一致（非方形窗口不拉伸）
                            Float32 vx = v.x
                            Float32 bx = cxw + ( vx - cxw ) / ax
                            Memory.writeF32( srcPtr, off + 0, bx )
                            Memory.writeF32( srcPtr, off + 4, v.y )
                            Memory.writeF32( srcPtr, off + 8, v.z )
                            vi = vi + 1
                        }
                        Memory.writeF32( cptr, 0, cxw )
                        Memory.writeF32( cptr, 4, cyw )
                        Memory.writeF32( cptr, 8, 0.0f )
                        EngineFfi.libOrthoBake( cptr, this.viewSize, srcPtr, vn, dstPtr )
                        Int32 slot = this._bakeCursor % 4
                        this._bakeCursor = this._bakeCursor + 1
                        bool up = this._pipe.uploadMesh( slot, dstPtr, vn )
                        if up
                        {
                            SLang.RenderObject ro = this._pipe.addObject( 4 + slot )
                            if ro != null
                            {
                                # 顶点 xy 已是 NDC（对象 position xy 保持 0）。
                                # z 必须按组绘制次序分层：所有烘焙顶点的
                                # gl_Position.z 恒 0，若对象 z 全为 0，则多组
                                # 层叠时先画的棋盘写入 depth 0.5，后画的蛇/
                                # 食物 0 < 0 被 LESS 深度测试剔除（棋盘铺满
                                # 全屏 → 蛇/食物完全不可见）。
                                # 令先画的组 z 更负（ndc_z=-z 更大、更远），
                                # 后画的组 z 趋近 0（更近），保证叠加物通过
                                # LESS 覆盖背景。单组 n=1 时 z=0，与旧行为
                                # 一致（S10~S14 单烘焙三角不受影响）。
                                Int32 depthRank = n - 1 - i
                                Float32 depthRankF = depthRank.toFloat32()
                                Float32 zo = 0.0f - depthRankF * 0.05f
                                ro.setPosition( 0.0f, 0.0f, zo )
                                Float32_3 gc = g.color
                                ro.setColor( gc.x, gc.y, gc.z, 1.0f )
                                Int32 gq = g.renderQueue
                                ro.setQueue( gq )
                                this._objIds.add( ro.handle )
                                submitted = submitted + 1
                            }
                        }
                    }
                    else
                    {
                        this.bakedSkipped = this.bakedSkipped + 1
                    }
                    if srcPtr != 0
                    {
                        Memory.free( srcPtr )
                    }
                    if dstPtr != 0
                    {
                        Memory.free( dstPtr )
                    }
                    if cptr != 0
                    {
                        Memory.free( cptr )
                    }
                }
            }
            i = i + 1
        }
        this.lastSubmitted = submitted
        ret submitted
    }

    # ── 光源收集（v2.13，doc/19 §6）──────────────────────
    # 显式栈先序遍历（同 Batcher.collect 形态，不递归）：收集激活节点的
    # LightData，按发现序写管线槽 0..7（SLR_MAX_LIGHTS=8，超出的计入
    # lightOverflow 不提交）。着色器消费首个平行光 + 首个聚光。
    public Int32 lightOverflow = 0

    public Int32 applyLights( Scene scene )
    {
        this.lightCount = 0
        this.lightOverflow = 0
        if scene == null || this._pipe == null
        {
            ret 0
        }
        List<GameObject> stack = List<GameObject>( 16 )
        Int32 ri = scene.rootCount() - 1
        while ri > 0 - 1
        {
            GameObject r = scene.getRoot( ri )
            if r != null
            {
                stack.add( r )
            }
            ri = ri - 1
        }
        while stack.length > 0
        {
            Int32 lastIdx = stack.length - 1
            GameObject cur = stack[lastIdx]
            stack.removeAt( lastIdx )
            if cur.getActiveInHierarchy()
            {
                Int32 ci = cur.childCount - 1
                while ci > 0 - 1
                {
                    GameObject ch = cur.getChild( ci )
                    if ch != null
                    {
                        stack.add( ch )
                    }
                    ci = ci - 1
                }
                LightData ld = cur.getComponent<LightData>()
                if ld != null
                {
                    if this.lightCount < 8
                    {
                        bool ok = ld.applyTo( this._pipe, this.lightCount )
                        if ok
                        {
                            this.lightCount = this.lightCount + 1
                        }
                    }
                    else
                    {
                        this.lightOverflow = this.lightOverflow + 1
                    }
                }
            }
        }
        ret this.lightCount
    }

    # ── 自定义网格上传（v2.13）──────────────────────────
    # 3D 顶点（xy 参与，z 忽略）→ pos2+uv2 交错块（stride 16B）→
    # pipe.uploadMesh(slot)。uv 取平面映射 (x*0.5+0.5, y*0.5+0.5)。
    # 消费形态：对象 meshKind = 4 + slot（MESH_CUSTOM + slot），顶点为
    # 模型空间坐标，经对象 MVP（setPosition/setScale）变换。
    public bool uploadMeshXyz( Int32 slot, List<Float32_3> verts )
    {
        if this._pipe == null || verts == null
        {
            ret false
        }
        Int32 n = verts.length
        if n <= 0
        {
            ret false
        }
        Int64 ptr = Memory.alloc( n * 16 )
        if ptr == 0
        {
            ret false
        }
        Int32 i = 0
        while i < n
        {
            Float32_3 v = verts[i]
            Int32 off = i * 16
            Memory.writeF32( ptr, off + 0, v.x )
            Memory.writeF32( ptr, off + 4, v.y )
            Float32 u = v.x * 0.5f + 0.5f
            Float32 w = v.y * 0.5f + 0.5f
            Memory.writeF32( ptr, off + 8, u )
            Memory.writeF32( ptr, off + 12, w )
            i = i + 1
        }
        bool ok = this._pipe.uploadMesh( slot, ptr, n )
        Memory.free( ptr )
        ret ok
    }

    # ── P7 2D：精灵收集（doc/15 §3）──────────────────────
    # 显式栈先序遍历（不递归）——激活节点 + layer 掩码 + SpriteRenderer
    # 可见才收集；本组件字段为同模块读（可靠），一次读全进平行数组；
    # 队列 = layers.queueOf(sortingLayer, orderInLayer)；pivot 偏移按
    # 未旋转世界系计入坐标（(pivot-0.5)*size*worldScale）。
    public void collect2D( Scene scene, Int32 cullMask )
    {
        this.clear2D()
        if scene == null
        {
            ret
        }
        List<GameObject> stack = List<GameObject>( 16 )
        Int32 ri = scene.rootCount() - 1
        while ri > 0 - 1
        {
            GameObject r = scene.getRoot( ri )
            if r != null
            {
                stack.add( r )
            }
            ri = ri - 1
        }
        while stack.length > 0
        {
            Int32 lastIdx = stack.length - 1
            GameObject cur = stack[lastIdx]
            stack.removeAt( lastIdx )
            bool active = cur.getActiveInHierarchy()
            if active
            {
                Int32 layer = cur.layer
                Int32 layerBit = 1 << layer
                Int32 masked = layerBit & cullMask
                if masked != 0
                {
                    SpriteRenderer sr = cur.getComponent<SpriteRenderer>()
                    if sr != null
                    {
                        if sr.visible
                        {
                            Transform t = cur.transform
                            Float32_3 wp = t.worldPosition()
                            Float32 wrz = t.worldRotationZ()
                            Float32_3 ws = t.worldScale()
                            Float32_2 sz = sr.size
                            Float32_2 pv = sr.pivot
                            Float32_3 col = sr.color
                            Int32 q = this.layers.queueOf( sr.sortingLayer, sr.orderInLayer )
                            Float32 ox = ( pv.x - 0.5f ) * sz.x * ws.x
                            Float32 oy = ( pv.y - 0.5f ) * sz.y * ws.y
                            this._spGo.add( cur )
                            this._spQueue.add( q )
                            this._spLayer.add( layer )
                            this._spX.add( wp.x + ox )
                            this._spY.add( wp.y + oy )
                            this._spZ.add( wp.z )
                            this._spRot.add( wrz )
                            this._spW.add( sz.x * ws.x )
                            this._spH.add( sz.y * ws.y )
                            this._spColor.add( col )
                            this._spAlpha.add( sr.colorAlpha )
                        }
                    }
                }
                Int32 cn = cur.childCount
                Int32 ci = cn - 1
                while ci > 0 - 1
                {
                    GameObject ch = cur.getChild( ci )
                    if ch != null
                    {
                        stack.add( ch )
                    }
                    ci = ci - 1
                }
            }
        }
        this.sort2D()
    }

    # 按 queue 升序稳定排序（新列表 + insert 稳定插入法，Batcher 同款；
    # 全程只消费平行数组标量）
    void sort2D()
    {
        List<GameObject> sGo = List<GameObject>( 0 )
        List<Int32> sQueue = List<Int32>( 0 )
        List<Int32> sLayer = List<Int32>( 0 )
        List<Float32> sX = List<Float32>( 0 )
        List<Float32> sY = List<Float32>( 0 )
        List<Float32> sZ = List<Float32>( 0 )
        List<Float32> sRot = List<Float32>( 0 )
        List<Float32> sW = List<Float32>( 0 )
        List<Float32> sH = List<Float32>( 0 )
        List<Float32_3> sColor = List<Float32_3>( 0 )
        List<Float32> sAlpha = List<Float32>( 0 )
        Int32 i = 0
        Int32 n = this._spGo.length
        while i < n
        {
            GameObject go = this._spGo[i]
            Int32 iq = this._spQueue[i]
            Int32 il = this._spLayer[i]
            Float32 ix = this._spX[i]
            Float32 iy = this._spY[i]
            Float32 iz = this._spZ[i]
            Float32 ir = this._spRot[i]
            Float32 iw = this._spW[i]
            Float32 ih = this._spH[i]
            Float32_3 ic = this._spColor[i]
            Float32 ia = this._spAlpha[i]
            Int32 pos = sGo.length
            Int32 k = sGo.length - 1
            while k > 0 - 1
            {
                Int32 oq = sQueue[k]
                if oq > iq
                {
                    pos = k
                    k = k - 1
                }
                else
                {
                    k = 0 - 1
                }
            }
            sGo.insert( pos, go )
            sQueue.insert( pos, iq )
            sLayer.insert( pos, il )
            sX.insert( pos, ix )
            sY.insert( pos, iy )
            sZ.insert( pos, iz )
            sRot.insert( pos, ir )
            sW.insert( pos, iw )
            sH.insert( pos, ih )
            sColor.insert( pos, ic )
            sAlpha.insert( pos, ia )
            i = i + 1
        }
        this._spGo = sGo
        this._spQueue = sQueue
        this._spLayer = sLayer
        this._spX = sX
        this._spY = sY
        this._spZ = sZ
        this._spRot = sRot
        this._spW = sW
        this._spH = sH
        this._spColor = sColor
        this._spAlpha = sAlpha
    }

    public void clear2D()
    {
        this._spGo.clear()
        this._spQueue.clear()
        this._spLayer.clear()
        this._spX.clear()
        this._spY.clear()
        this._spZ.clear()
        this._spRot.clear()
        this._spW.clear()
        this._spH.clear()
        this._spColor.clear()
        this._spAlpha.clear()
    }

    # ── 2D 平行数组 getters（消费方跨模块读的可靠形态，doc/10 §6）──
    # 坑：`ret this._x[i]` 返回表达式下标解析失败——下标读先落局部变量
    public Int32 spriteCount()
    {
        ret this._spGo.length
    }

    public GameObject spriteGoAt( Int32 idx )
    {
        GameObject v = this._spGo[idx]
        ret v
    }

    public Int32 spriteQueueAt( Int32 idx )
    {
        Int32 v = this._spQueue[idx]
        ret v
    }

    public Int32 spriteLayerAt( Int32 idx )
    {
        Int32 v = this._spLayer[idx]
        ret v
    }

    public Float32 spriteWorldXAt( Int32 idx )
    {
        Float32 v = this._spX[idx]
        ret v
    }

    public Float32 spriteWorldYAt( Int32 idx )
    {
        Float32 v = this._spY[idx]
        ret v
    }

    public Float32 spriteRotZAt( Int32 idx )
    {
        Float32 v = this._spRot[idx]
        ret v
    }

    public Float32 spriteWidthAt( Int32 idx )
    {
        Float32 v = this._spW[idx]
        ret v
    }

    public Float32 spriteHeightAt( Int32 idx )
    {
        Float32 v = this._spH[idx]
        ret v
    }

    public Float32_3 spriteColorAt( Int32 idx )
    {
        Float32_3 v = this._spColor[idx]
        ret v
    }

    public Float32 spriteAlphaAt( Int32 idx )
    {
        Float32 v = this._spAlpha[idx]
        ret v
    }

    # ── P7 2D：精灵提交（MESH_QUAD 直通）─────────────────
    # 收集结果按 queue 后→前提交为独立 MESH_QUAD RenderObject（透明段
    # queue >= 2500；世界 → NDC 正交映射与 3D sync 同款）。管线未就绪
    # 返回 -1（只收集不提交的用法合法）。
    public Int32 sync2D()
    {
        if this._pipe == null
        {
            ret 0 - 1
        }
        this.recycle2D()
        Float32 ax = this.aspectX()
        Float32 hw = this.viewSize * ax
        Int32 i = 0
        Int32 n = this._spGo.length
        Int32 submitted = 0
        while i < n
        {
            SLang.RenderObject ro = this._pipe.addObject( 1 )
            if ro != null
            {
                # 坑：下标/字段链参与算术表达式解析失败——先落局部变量
                Float32 wx = this._spX[i]
                Float32 wy = this._spY[i]
                Float32 cx0 = this.cameraCenter.x
                Float32 cy0 = this.cameraCenter.y
                Float32 vs = this.viewSize
                Float32 pz = this._spZ[i]
                Float32 rz = this._spRot[i]
                Float32 w0 = this._spW[i]
                Float32 h0 = this._spH[i]
                Float32_3 col = this._spColor[i]
                Float32 al = this._spAlpha[i]
                Float32 nx = ( wx - cx0 ) / hw
                Float32 ny = ( wy - cy0 ) / vs
                Float32 sw = w0 / hw
                Float32 sh = h0 / vs
                ro.setPosition( nx, ny, pz )
                ro.setRotationZ( rz )
                ro.setScale( sw, sh )
                ro.setColor( col.x, col.y, col.z, al )
                Int32 q = this._spQueue[i]
                ro.setQueue( q )
                Int32 ly = this._spLayer[i]
                ro.setLayer( ly )
                this._objIds2D.add( ro.handle )
                submitted = submitted + 1
            }
            i = i + 1
        }
        this.lastSubmitted2D = submitted
        ret submitted
    }


    # 渲染一帧到 dstPtr 原生块（RGBA8，供 QT/宿主上屏）
    public bool frame( Float32 time, Int64 dstPtr )
    {
        if this._pipe == null
        {
            ret false
        }
        ret this._pipe.renderFrame( time, dstPtr )
    }

    # 帧尾回收本帧 RenderObject（句柄池由 Render 侧管理；按 Int64 句柄
    # 直接销毁——跨模块对象实例入 List 会污染字段，doc/10 §6）
    void recycle()
    {
        Int32 i = 0
        Int64 ph = this._pipe.handle
        Int32 n = this._objIds.length
        while i < n
        {
            Int64 oid = this._objIds[i]
            if oid != 0
            {
                SLang.RenderObject.destroyById( ph, oid )
            }
            i = i + 1
        }
        this._objIds.clear()
    }

    # 帧尾回收本帧 2D RenderObject（与 3D 池分开，同帧 sync+sync2D 不互杀）
    void recycle2D()
    {
        Int32 i = 0
        Int64 ph = this._pipe.handle
        Int32 n = this._objIds2D.length
        while i < n
        {
            Int64 oid = this._objIds2D[i]
            if oid != 0
            {
                SLang.RenderObject.destroyById( ph, oid )
            }
            i = i + 1
        }
        this._objIds2D.clear()
    }

    public void shutdown()
    {
        this.recycle()
        this.recycle2D()
        if this._pipe != null
        {
            this._pipe.destroy()
            this._pipe = null
        }
    }
}
