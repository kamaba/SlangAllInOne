import Math;
# ScriptableRenderContext —— 剔除 + 绘制执行上下文
#
# 对应 Unity SRP：
#   ScriptableCullingParameters / CullingResults / ScriptableRenderContext
#
# 视锥剔除：由 viewProjection 矩阵按 Gribb-Hartmann 抽 6 个平面，
#           用包围球（center + extents.length()）做快速判定

public class CullingParameters
{
    public Float32_4x4 cullingMatrix = null
    public bool isOrthographic = false
    public Float32 maxShadowDistance = 100.0f
    public Int32 cullingMask = -1
    public Float32_3 cameraPosition = Float32_3.zero()
    public Float32 farClip = 1000.0f

    public void _init_()
    {
        this.cullingMatrix = Float32_4x4.identity()
        this.isOrthographic = false
        this.maxShadowDistance = 100.0f
        this.cullingMask = -1
        this.cameraPosition = Float32_3.zero()
        this.farClip = 1000.0f
    }

    public static CullingParameters fromCamera( Camera cam )
    {
        CullingParameters p = CullingParameters()
        p.cullingMatrix = cam.viewProjectionMatrix()
        p.isOrthographic = cam.isOrthographic
        p.cameraPosition = cam.position()
        p.farClip = cam.farClipPlane
        ret p
    }

    # 从 VP 矩阵抽 6 个平面，每个平面存 (nx, ny, nz, d)
    public Array<Float32_4> extractPlanes()
    {
        Float32_4x4 m = this.cullingMatrix
        # Float32_4x4 无内部数组字段，用 getValue(row, col) 展开 16 个元素
        Array<Float32> e = Array<Float32>( 16 )
        int k = 0
        while k < 16
        {
            e[k] = m.getValue( k / 4, k % 4 )
            k++
        }
        Array<Float32_4> planes = Array<Float32_4>( 6 )

        # 行主序：m[row*4 + col]
        # left   = row3 + row0
        planes[0] = CullingParameters.makePlane( e[12] + e[0], e[13] + e[1], e[14] + e[2], e[15] + e[3] )
        # right  = row3 - row0
        planes[1] = CullingParameters.makePlane( e[12] - e[0], e[13] - e[1], e[14] - e[2], e[15] - e[3] )
        # bottom = row3 + row1
        planes[2] = CullingParameters.makePlane( e[12] + e[4], e[13] + e[5], e[14] + e[6], e[15] + e[7] )
        # top    = row3 - row1
        planes[3] = CullingParameters.makePlane( e[12] - e[4], e[13] - e[5], e[14] - e[6], e[15] - e[7] )
        # near   = row2（DX 风格 z ∈ [0,1]）
        planes[4] = CullingParameters.makePlane( e[8], e[9], e[10], e[11] )
        # far    = row3 - row2
        planes[5] = CullingParameters.makePlane( e[12] - e[8], e[13] - e[9], e[14] - e[10], e[15] - e[11] )
        ret planes
    }

    static Float32_4 makePlane( Float32 a, Float32 b, Float32 c, Float32 d )
    {
        Float32 len = Mathf.sqrt( a * a + b * b + c * c )
        if len <= 0.0f
        {
            ret Float32_4( 0.0f, 0.0f, 0.0f, 0.0f )
        }
        ret Float32_4( a / len, b / len, c / len, d / len )
    }

    override string toString()
    {
        ret "CullingParameters(ortho=" + this.isOrthographic.toString() + ", far=" + SystemConvertString( this.farClip ) + ")"
    }
}

# ── 可见物体 ───────────────────────────────────────────
public class VisibleRenderer
{
    public SLang.Mesh mesh = null
    public Material material = null
    public Float32_4x4 localToWorld = null
    # Bounds 类不存在（Mesh.sl 明确不引入 Bounds），用 center/extents 两向量占位
    public Float32_3 boundsCenter = Float32_3.zero()
    public Float32_3 boundsExtents = Float32_3.one()
    public Int32 renderQueue = 2000
    public Int32 layer = 0
    public Float32 distanceToCamera = 0.0f
    public Int32 rendererId = 0

    public void _init_()
    {
        this.mesh = null
        this.material = null
        this.localToWorld = Float32_4x4.identity()
        this.boundsCenter = Float32_3.zero()
        this.boundsExtents = Float32_3.one()
        this.renderQueue = 2000
        this.layer = 0
        this.distanceToCamera = 0.0f
        this.rendererId = 0
    }

    public void _init_( SLang.Mesh _mesh, Material _material, Float32_4x4 _localToWorld )
    {
        this._init_()
        this.mesh = _mesh
        this.material = _material
        this.localToWorld = _localToWorld
        # Mesh 当前不提供 bounds()（Mesh.sl 明确不引入 Bounds），单位包围球占位
        if _mesh != null
        {
            this.boundsCenter = Float32_3.zero()
            this.boundsExtents = Float32_3.one()
        }
        if _material != null && _material.isTransparent
        {
            this.renderQueue = 3000
        }
    }

    public get bool isTransparent()
    {
        if this.material == null
        {
            ret false
        }
        ret this.material.isTransparent
    }
}

# ── 剔除结果 ───────────────────────────────────────────
public class CullingResults
{
    Array<VisibleRenderer> _renderers = null
    Array<Light> _lights = null

    public void _init_()
    {
        this._renderers = Array<VisibleRenderer>( 0 )
        this._lights = Array<Light>( 0 )
    }

    public void add( VisibleRenderer r )
    {
        Int32 oldLen = this._renderers.length
        Array<VisibleRenderer> nr = Array<VisibleRenderer>( oldLen + 1 )
        int i = 0
        while i < oldLen
        {
            nr[i] = this._renderers[i]
            i++
        }
        nr[ oldLen ] = r
        this._renderers = nr
    }

    public void addLight( Light l )
    {
        Int32 oldLen = this._lights.length
        Array<Light> nl = Array<Light>( oldLen + 1 )
        int i = 0
        while i < oldLen
        {
            nl[i] = this._lights[i]
            i++
        }
        nl[ oldLen ] = l
        this._lights = nl
    }

    public get int count()
    {
        ret this._renderers.length
    }

    public get int lightCount()
    {
        ret this._lights.length
    }

    public Array<VisibleRenderer> all()
    {
        ret this._renderers
    }

    public Array<Light> lights()
    {
        ret this._lights
    }

    # 按 renderQueue 区间过滤：不透明 < 2500，透明 >= 2500
    public Array<VisibleRenderer> filterByQueue( Int32 minQueue, Int32 maxQueue )
    {
        int hit = 0
        int i = 0
        while i < this._renderers.length
        {
            Int32 q = this._renderers[i].renderQueue
            if q >= minQueue && q < maxQueue
            {
                hit++
            }
            i++
        }
        Array<VisibleRenderer> res = Array<VisibleRenderer>( hit )
        int k = 0
        i = 0
        while i < this._renderers.length
        {
            Int32 q2 = this._renderers[i].renderQueue
            if q2 >= minQueue && q2 < maxQueue
            {
                res[k] = this._renderers[i]
                k++
            }
            i++
        }
        ret res
    }

    public Array<VisibleRenderer> opaque()
    {
        ret this.filterByQueue( 0, 2500 )
    }

    public Array<VisibleRenderer> transparent()
    {
        ret this.filterByQueue( 2500, 5000 )
    }

    # 不透明从前到后（减少 overdraw），透明从后到前（保证混合顺序）
    public void sortFrontToBack()
    {
        this.sortByDistance( true )
    }

    public void sortBackToFront()
    {
        this.sortByDistance( false )
    }

    void sortByDistance( bool ascending )
    {
        Array<VisibleRenderer> a = this._renderers
        int i = 1
        while i < a.length
        {
            VisibleRenderer key = a[i]
            int j = i - 1
            while j >= 0
            {
                bool swap = false
                if ascending
                {
                    swap = a[j].distanceToCamera > key.distanceToCamera
                }
                else
                {
                    swap = a[j].distanceToCamera < key.distanceToCamera
                }
                if !swap
                {
                    break
                }
                a[ j + 1 ] = a[j]
                j--
            }
            a[ j + 1 ] = key
            i++
        }
    }
}

# ── 渲染上下文 ─────────────────────────────────────────
public class ScriptableRenderContext
{
    public GfxDevice device = null
    public CommandBuffer cmd = null
    public Camera camera = null
    public CullingResults cullingResults = null

    # ── P1 Pass 功能块：Pass 序列 + 共享命令流（单流提交）──────
    public static Int32 CAP_PASSES = 16

    # 目标管线（submitPasses 经它整包提交共享命令流）
    public SLang.RenderPipeline pipeline = null
    Array<RenderPass> _passes = null
    Int32 _passCount = 0
    CommandBuffer _passCmd = null

    public void _init_()
    {
        this.device = null
        this.cmd = null
        this.camera = null
        this.cullingResults = CullingResults()
        # P1 Pass 功能块
        this.pipeline = null
        this._passes = Array<RenderPass>( ScriptableRenderContext.CAP_PASSES )
        this._passCount = 0
        this._passCmd = CommandBuffer()
    }

    public void _init_( GfxDevice _device )
    {
        this._init_()
        this.device = _device
    }

    # 取出一条命令缓冲并开始录制
    public CommandBuffer beginCommandBuffer( string name )
    {
        this.cmd = this.device.createCommandBuffer( name )
        this.cmd.begin()
        ret this.cmd
    }

    public void executeCommandBuffer( CommandBuffer cb )
    {
        if this.device == null || cb == null
        {
            ret
        }
        cb.end()
        this.device.execute( cb )
    }

    # 把当前录制的命令提交
    public void submit()
    {
        if this.cmd != null
        {
            this.executeCommandBuffer( this.cmd )
            this.cmd = null
        }
    }

    # ── 剔除 ─────────────────────────────────────────────
    public CullingResults cull( CullingParameters parameters, Array<VisibleRenderer> allRenderers )
    {
        CullingResults results = CullingResults()
        if allRenderers == null
        {
            this.cullingResults = results
            ret results
        }
        Array<Float32_4> planes = parameters.extractPlanes()
        int i = 0
        while i < allRenderers.length
        {
            VisibleRenderer r = allRenderers[i]
            if this.isVisible( planes, r, parameters )
            {
                # 记录到相机的距离，供排序使用
                r.distanceToCamera = ScriptableRenderContext.distance( r.boundsCenter, parameters.cameraPosition )
                results.add( r )
            }
            i++
        }
        this.cullingResults = results
        ret results
    }

    # 包围球 vs 6 平面：任一面完全在外即剔除
    bool isVisible( Array<Float32_4> planes, VisibleRenderer r, CullingParameters parameters )
    {
        if r == null
        {
            ret false
        }
        Float32_3 center = r.boundsCenter
        Float32 radius = r.boundsExtents.length()
        int i = 0
        while i < planes.length
        {
            Float32_4 p = planes[i]
            Float32 dist = p.x * center.x + p.y * center.y + p.z * center.z + p.w
            if dist < 0.0f - radius
            {
                ret false
            }
            i++
        }
        if parameters.maxShadowDistance > 0.0f
        {
            r.distanceToCamera = ScriptableRenderContext.distance( center, parameters.cameraPosition )
        }
        ret true
    }

    static Float32 distance( Float32_3 a, Float32_3 b )
    {
        Float32 dx = a.x - b.x
        Float32 dy = a.y - b.y
        Float32 dz = a.z - b.z
        ret Mathf.sqrt( dx * dx + dy * dy + dz * dz )
    }

    # ── 绘制 ─────────────────────────────────────────────
    # 按队列区间批量绘制；overrideMaterial 非空时用它替换材质（深度预通道常用）
    public void drawRenderers( CullingResults results, Int32 minQueue, Int32 maxQueue, Material overrideMaterial )
    {
        if results == null || this.camera == null
        {
            ret
        }
        Array<VisibleRenderer> renderers = results.filterByQueue( minQueue, maxQueue )
        Float32_4x4 vp = this.camera.viewProjectionMatrix()
        int i = 0
        while i < renderers.length
        {
            VisibleRenderer r = renderers[i]
            Material mat = r.material
            if overrideMaterial != null
            {
                mat = overrideMaterial
            }
            if this.cmd != null
            {
                this.cmd.drawMesh( r.mesh, mat, r.localToWorld, vp )
            }
            i++
        }
    }

    public void drawSkybox( Camera cam )
    {
        if this.cmd == null || cam == null
        {
            ret
        }
        # 天空盒走全屏三角 + 立方体贴图（程序化，无需顶点缓冲）
        this.cmd.drawProcedural( 3, 1 )
    }

    public void drawFullscreen( Material mat )
    {
        if this.cmd == null
        {
            ret
        }
        this.cmd.drawProcedural( 3, 1 )
    }

    # ── 相机属性设置（清屏 / 视口）─────────────────────────
    public void setupCameraProperties( Camera cam )
    {
        if this.cmd == null || cam == null
        {
            ret
        }
        this.cmd.setViewport( 0, 0, this.cameraWidth(), this.cameraHeight() )
    }

    Int32 cameraWidth()
    {
        if this.device == null || this.device.window == null
        {
            ret 1280
        }
        ret this.device.window.width
    }

    Int32 cameraHeight()
    {
        if this.device == null || this.device.window == null
        {
            ret 720
        }
        ret this.device.window.height
    }

    # ── P1 Pass 序列管理 ──────────────────────────────────
    # addPass(pass) —— 追加一个 Pass 到序列末尾（空引用/容量满返回 false）
    public bool addPass( RenderPass pass )
    {
        if pass == null
        {
            ret false
        }
        if this._passCount >= ScriptableRenderContext.CAP_PASSES
        {
            ret false
        }
        Int32 idx = this._passCount
        this._passes[ idx ] = pass
        this._passCount = idx + 1
        ret true
    }

    # clearPasses() —— 清空序列（容量保留，只回退游标）
    public void clearPasses()
    {
        this._passCount = 0
    }

    public Int32 passCount()
    {
        ret this._passCount
    }

    # passAt(index) —— 取序列中的 Pass（越界返回 null）
    public RenderPass passAt( Int32 index )
    {
        if index < 0 || index >= this._passCount
        {
            ret null
        }
        Int32 idx = index
        ret this._passes[ idx ]
    }

    # ── P1 单流提交 ───────────────────────────────────────
    # beginPassRecording() —— 开启一帧的共享命令流：清空旧录制并 begin。
    # 之后可用 passCommandBuffer() 预录帧级共享状态（setTexture /
    # setPerDraw 等）——C 侧 slr_cmd_execute_stream 每次调用都会重置
    # PerDraw 槽与描述符表（sl_cmd.c 帧级前置 memset），一帧的全部
    # 命令必须录进同一条流。
    public void beginPassRecording()
    {
        if this._passCmd == null
        {
            this._passCmd = CommandBuffer()
        }
        this._passCmd.clear()
        this._passCmd.begin()
    }

    # passCommandBuffer() —— 共享命令流引用（预录 / 断言用）
    public CommandBuffer passCommandBuffer()
    {
        ret this._passCmd
    }

    # submitPasses() —— 依序执行 Pass 序列并整包提交（Unity
    # ScriptableRenderContext.Submit 的 Pass 化对应物）：
    #   1 逐 Pass 调 pass.execute(this, cmd) 把命令录进同一条流；
    #   2 cmd.sortDrawItems() 整理 DrawItem 段（不透明 queue→z→prog、
    #     透明 z 降序，与 C 侧 sort_items 键序一致）；
    #   3 cmd.end() 后经 pipeline.executeCommandBuffer 整包提交（C 侧
    #     逐 opcode 回放，统计口径与单流直提完全一致）。
    # 返回 false：无管线 / 无命令流 / 序列为空 / 录制为空 / 提交失败。
    public bool submitPasses()
    {
        if this.pipeline == null || this._passCmd == null
        {
            ret false
        }
        if this._passCount <= 0
        {
            ret false
        }
        Int32 i = 0
        while i < this._passCount
        {
            RenderPass p = this.passAt( i )
            if p != null
            {
                p.execute( this, this._passCmd )
            }
            i = i + 1
        }
        this._passCmd.sortDrawItems()
        this._passCmd.end()
        if this._passCmd.commandCount <= 0
        {
            ret false
        }
        ret this.pipeline.executeCommandBuffer( this._passCmd )
    }
}
