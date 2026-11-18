import Std;
import Math;

# ============================================================================
# Ray.sl —— 软光追射线层（N4a，对应 C 侧 Pipeline/sl_ray.c）
#
# 三类角色：
#   Ray       —— 射线（origin/direction；屏幕拾取/射线投射的返回类型，
#                原 Camera.screenPointToRay 产出；组件式 Camera 已随 SRP
#                草稿链移除，本类保持既有 API 不变）；
#   RayHit    —— 求交记录（t / 命中点 / 法线 / 材质：球下标或地面）；
#   RaySphere / RayScene —— 场景描述 + SL 参考实现。
#
# RayScene 是 SL 侧「参考光追器」：与 C 侧 sl_ray.c 的 whitted 数学逐字
# 一致（求交 eps / 法线偏移 / 着色公式 / 相机模型，常量见类头），供
# RenderTest Phase RAY 对 C 渲产纹理做逐像素断言；同时经
# CommandBuffer.recordRayScene(scene) 把场景录进 SLMC 命令流
# （RaySet* 命令），C 侧 RayRender 命令消费渲染。
#
# SL 红线遵守：ret 非 return；无 for 用 while；实例成员访问带 this.；
# 数组下标先落局部变量；方法名避开 get/set；跨类构造用无参 + 字段赋值。
# ============================================================================

# 射线（屏幕拾取用；Mesh.sl 明确不引入 Ray，这里就近定义）
public class Ray
{
    public Float32_3 origin = Float32_3.zero()
    public Float32_3 direction = Float32_3.forward()

    public void _init_()
    {
        this.origin = Float32_3.zero()
        this.direction = Float32_3.forward()
    }

    public void _init_( Float32_3 _origin, Float32_3 _direction )
    {
        this.origin = _origin.clone()
        this.direction = _direction.normalize()
    }

    # 射线上 t 处的点
    public Float32_3 getPoint( Float32 t )
    {
        ret this.origin._add_( this.direction.scale( t ) ) as Float32_3
    }

    override string toString()
    {
        ret "Ray(origin=" + this.origin.toString() + ", dir=" + this.direction.toString() + ")"
    }
}

# RayHit —— 求交记录（参考实现与 Phase RAY 断言的载体）
#   sphereIndex >= 0 球下标；-1 地面平面；-2 无命中（t 无效）
public class RayHit
{
    public Float32 t = 0.0f
    public Float32 px = 0.0f
    public Float32 py = 0.0f
    public Float32 pz = 0.0f
    public Float32 nx = 0.0f
    public Float32 ny = 0.0f
    public Float32 nz = 0.0f
    public Int32 sphereIndex = -2
    public Float32 albedoR = 0.0f
    public Float32 albedoG = 0.0f
    public Float32 albedoB = 0.0f
    public Float32 reflect = 0.0f

    public void _init_()
    {
        this.t = 0.0f
        this.px = 0.0f
        this.py = 0.0f
        this.pz = 0.0f
        this.nx = 0.0f
        this.ny = 0.0f
        this.nz = 0.0f
        this.sphereIndex = -2
        this.albedoR = 0.0f
        this.albedoG = 0.0f
        this.albedoB = 0.0f
        this.reflect = 0.0f
    }

    override string toString()
    {
        ret "RayHit(t=" + this.t.toString() + ", mat=" + this.sphereIndex.toString() + ")"
    }
}

# RaySphere —— 球场景元素（中心/半径 + albedo + 反射率）
public class RaySphere
{
    public Float32 cx = 0.0f
    public Float32 cy = 0.0f
    public Float32 cz = 0.0f
    public Float32 radius = 1.0f
    public Float32 cr = 1.0f
    public Float32 cg = 1.0f
    public Float32 cb = 1.0f
    public Float32 reflect = 0.0f

    public void _init_()
    {
        this.cx = 0.0f
        this.cy = 0.0f
        this.cz = 0.0f
        this.radius = 1.0f
        this.cr = 1.0f
        this.cg = 1.0f
        this.cb = 1.0f
        this.reflect = 0.0f
    }

    # 八字段便捷赋值（不调 this._init_()，直接全量覆写；方法名不能用
    # set——解析器关键字，会触发特殊语法导致编译异常）
    public void setAll( Float32 _cx, Float32 _cy, Float32 _cz, Float32 _radius,
                        Float32 _cr, Float32 _cg, Float32 _cb, Float32 _reflect )
    {
        this.cx = _cx
        this.cy = _cy
        this.cz = _cz
        this.radius = _radius
        this.cr = _cr
        this.cg = _cg
        this.cb = _cb
        this.reflect = _reflect
    }
}

# RayScene —— 软光追场景（SL 参考实现 + SLMC 录制桥）
#
# 数学契约（与 C 侧 sl_ray.c / sl_render_internal.h 逐字一致）：
#   着色   local = albedo * (AMBIENT + (阴影 ? 0 : intensity * max(0, n·l)))
#          color = refl > 0 ? local*(1-refl) + trace(reflected)*refl : local
#          （whitted 2 弹射：主射线 + 1 反射，反射命中不再反射）
#   求交   球：t = -b - sqrt(b²-c) > eps；地面 y=0 仅自上向下命中
#   偏移   阴影/反射射线起点 = 命中点 + 法线 * OFFSET
#   相机   正交固定基（forward +z / up +y / right +x），fovY 垂直视场角：
#          ndc_x = (px+0.5)/w*2-1  ndc_y = 1-(py+0.5)/h*2
#          half_h = tan(fovY*PI/360)  half_w = half_h*(w/h)
#          dir = normalize(ndc_x*half_w, ndc_y*half_h, 1)
public class RayScene
{
    public static Int32 MAX_SPHERES = 16
    public static Float32 AMBIENT = 0.25f
    # 求交阈值（最近命中）与二次射线法线偏移（与 C 侧常量一致）
    public static Float32 HIT_EPS = 0.0001f
    public static Float32 OFFSET = 0.001f
    public static Float32 PI = 3.14159265f

    Array<RaySphere> _spheres = null
    Int32 _sphereCount = 0

    public bool groundOn = true
    public Float32 groundR = 0.5f
    public Float32 groundG = 0.5f
    public Float32 groundB = 0.5f
    public Float32 groundReflect = 0.0f

    public Float32 lightX = 0.0f
    public Float32 lightY = 1.0f
    public Float32 lightZ = 0.0f
    public Float32 lightIntensity = 1.0f

    public Float32 eyeX = 0.0f
    public Float32 eyeY = 1.0f
    public Float32 eyeZ = -4.0f
    public Float32 fovY = 60.0f

    public Float32 bgR = 0.0f
    public Float32 bgG = 0.0f
    public Float32 bgB = 0.0f

    # 默认态与 C 侧 ray_scene_reset 逐字一致
    public void _init_()
    {
        this._spheres = Array<RaySphere>( RayScene.MAX_SPHERES )
        this.clear()
    }

    # 重置为默认态（球表清空；容量保留）
    public void clear()
    {
        Int32 i = 0
        while i < RayScene.MAX_SPHERES
        {
            this._spheres[ i ] = null
            i = i + 1
        }
        this._sphereCount = 0
        this.groundOn = true
        this.groundR = 0.5f
        this.groundG = 0.5f
        this.groundB = 0.5f
        this.groundReflect = 0.0f
        this.lightX = 0.0f
        this.lightY = 1.0f
        this.lightZ = 0.0f
        this.lightIntensity = 1.0f
        this.eyeX = 0.0f
        this.eyeY = 1.0f
        this.eyeZ = -4.0f
        this.fovY = 60.0f
        this.bgR = 0.0f
        this.bgG = 0.0f
        this.bgB = 0.0f
    }

    public get int sphereCount()
    {
        ret this._sphereCount
    }

    # 取球（下标先落局部变量；越界返回 null）
    public RaySphere sphereAt( Int32 i )
    {
        Int32 idx = i
        if idx < 0 || idx >= this._sphereCount
        {
            ret null
        }
        ret this._spheres[ idx ]
    }

    # 追加球（返回下标；满返回 -1）
    public Int32 addSphere( RaySphere s )
    {
        if s == null
        {
            ret -1
        }
        if this._sphereCount >= RayScene.MAX_SPHERES
        {
            ret -1
        }
        Int32 idx = this._sphereCount
        this._spheres[ idx ] = s
        this._sphereCount = idx + 1
        ret idx
    }

    public void setLight( Float32 dx, Float32 dy, Float32 dz, Float32 intensity )
    {
        this.lightX = dx
        this.lightY = dy
        this.lightZ = dz
        this.lightIntensity = intensity
    }

    public void setGround( Float32 r, Float32 g, Float32 b, Float32 reflect )
    {
        this.groundOn = true
        this.groundR = r
        this.groundG = g
        this.groundB = b
        this.groundReflect = reflect
    }

    public void setCamera( Float32 ex, Float32 ey, Float32 ez, Float32 fovYDegrees )
    {
        this.eyeX = ex
        this.eyeY = ey
        this.eyeZ = ez
        this.fovY = fovYDegrees
    }

    public void setBackground( Float32 r, Float32 g, Float32 b )
    {
        this.bgR = r
        this.bgG = g
        this.bgB = b
    }

    # ── 参考求交（与 C 侧逐字一致；direction 须已归一）───────────────

    # 单球求交：t > eps 命中，hit 写 t/点/法线/材质，返回 true
    bool hitSphere( Ray ray, RaySphere s, Float32 eps, RayHit hit )
    {
        Float32 ocx = ray.origin.x - s.cx
        Float32 ocy = ray.origin.y - s.cy
        Float32 ocz = ray.origin.z - s.cz
        Float32 b = Mathf.dot3( ocx, ocy, ocz, ray.direction.x, ray.direction.y, ray.direction.z )
        Float32 c = ocx * ocx + ocy * ocy + ocz * ocz - s.radius * s.radius
        Float32 disc = b * b - c
        if disc < 0.0f
        {
            ret false
        }
        Float32 t = -b - Mathf.sqrt( disc )
        if t <= eps
        {
            ret false
        }
        Float32 invR = 1.0f / s.radius
        hit.t = t
        hit.px = ray.origin.x + ray.direction.x * t
        hit.py = ray.origin.y + ray.direction.y * t
        hit.pz = ray.origin.z + ray.direction.z * t
        hit.nx = ( hit.px - s.cx ) * invR
        hit.ny = ( hit.py - s.cy ) * invR
        hit.nz = ( hit.pz - s.cz ) * invR
        ret true
    }

    # 地面（y=0，法线 +y）求交：仅自上方向下的射线可命中
    bool hitGround( Ray ray, Float32 eps, RayHit hit )
    {
        if this.groundOn == false
        {
            ret false
        }
        if ray.direction.y >= -0.00000001f
        {
            ret false
        }
        Float32 t = -ray.origin.y / ray.direction.y
        if t <= eps
        {
            ret false
        }
        hit.t = t
        hit.px = ray.origin.x + ray.direction.x * t
        hit.py = 0.0f
        hit.pz = ray.origin.z + ray.direction.z * t
        hit.nx = 0.0f
        hit.ny = 1.0f
        hit.nz = 0.0f
        ret true
    }

    # 最近命中（球 + 地面；eps = RayScene.HIT_EPS）
    bool nearestHit( Ray ray, RayHit hit )
    {
        bool found = false
        Float32 bestT = 0.0f
        Int32 bestMat = -2
        Int32 i = 0
        while i < this._sphereCount
        {
            Int32 idx = i
            RaySphere s = this._spheres[ idx ]
            if s != null
            {
                bool ok = this.hitSphere( ray, s, RayScene.HIT_EPS, hit )
                if ok
                {
                    if found == false || hit.t < bestT
                    {
                        bestT = hit.t
                        bestMat = idx
                        found = true
                    }
                }
            }
            i = i + 1
        }
        bool gOk = this.hitGround( ray, RayScene.HIT_EPS, hit )
        if gOk
        {
            if found == false || hit.t < bestT
            {
                bestT = hit.t
                bestMat = -1
                found = true
            }
        }
        if found == false
        {
            ret false
        }
        # 最近项重求一次写全 hit（球法线/材质；地面已在上面临时写过）
        if bestMat >= 0
        {
            Int32 midx = bestMat
            RaySphere s2 = this._spheres[ midx ]
            bool ok2 = this.hitSphere( ray, s2, RayScene.HIT_EPS, hit )
            if ok2 == false
            {
                ret false
            }
            hit.sphereIndex = midx
            hit.albedoR = s2.cr
            hit.albedoG = s2.cg
            hit.albedoB = s2.cb
            hit.reflect = s2.reflect
        }
        else
        {
            bool ok3 = this.hitGround( ray, RayScene.HIT_EPS, hit )
            if ok3 == false
            {
                ret false
            }
            hit.sphereIndex = -1
            hit.albedoR = this.groundR
            hit.albedoG = this.groundG
            hit.albedoB = this.groundB
            hit.reflect = this.groundReflect
        }
        ret true
    }

    # 阴影射线遮挡测试：起点 = 命中点 + 法线 * OFFSET，方向 = 归一 L；
    # 任一球挡住（t > OFFSET）即遮挡（地面是接收面不遮挡）
    bool shadowBlocked( RayHit hit, Float32 lx, Float32 ly, Float32 lz )
    {
        Ray sray = Ray()
        sray.origin = Float32_3( hit.px + hit.nx * RayScene.OFFSET,
                                 hit.py + hit.ny * RayScene.OFFSET,
                                 hit.pz + hit.nz * RayScene.OFFSET )
        sray.direction = Float32_3( lx, ly, lz )
        RayHit tmp = RayHit()
        Int32 i = 0
        while i < this._sphereCount
        {
            Int32 idx = i
            RaySphere s = this._spheres[ idx ]
            if s != null
            {
                bool ok = this.hitSphere( sray, s, RayScene.OFFSET, tmp )
                if ok
                {
                    ret true
                }
            }
            i = i + 1
        }
        ret false
    }

    # 命中点局部着色：albedo * (AMBIENT + (阴影 ? 0 : intensity * ndl))
    Float32_3 shadeLocal( RayHit hit )
    {
        # L 归一（C 侧 ray_trace 每次调用归一一份拷贝）
        Float32 ll = Mathf.sqrt( this.lightX * this.lightX + this.lightY * this.lightY + this.lightZ * this.lightZ )
        Float32 lx = this.lightX
        Float32 ly = this.lightY
        Float32 lz = this.lightZ
        if ll > 0.00000001f
        {
            lx = lx / ll
            ly = ly / ll
            lz = lz / ll
        }
        Float32 ndl = hit.nx * lx + hit.ny * ly + hit.nz * lz
        Float32 lit = RayScene.AMBIENT
        if ndl > 0.0f
        {
            if this.lightIntensity > 0.0f
            {
                bool blocked = this.shadowBlocked( hit, lx, ly, lz )
                if blocked == false
                {
                    lit = lit + this.lightIntensity * ndl
                }
            }
        }
        ret Float32_3( hit.albedoR * lit, hit.albedoG * lit, hit.albedoB * lit )
    }

    # whitted 2 弹射展开（无递归：主射线 + 1 反射，反射命中只算局部色）
    #   像素 -> 相机射线 -> 最近命中 -> 局部着色 ->（reflect > 0 时）
    #   反射射线再走一轮最近命中 + 局部着色 -> 按 reflect 混合
    Float32_3 tracePixel( Int32 px, Int32 py, Int32 w, Int32 h )
    {
        Float32 fw = w.toFloat32()
        Float32 fh = h.toFloat32()
        Float32 halfH = Mathf.tan( this.fovY * RayScene.PI / 360.0f )
        Float32 halfW = halfH * fw / fh
        Float32 ndcX = ( px.toFloat32() + 0.5f ) * 2.0f / fw - 1.0f
        Float32 ndcY = 1.0f - ( py.toFloat32() + 0.5f ) * 2.0f / fh
        Float32 dx = ndcX * halfW
        Float32 dy = ndcY * halfH
        Float32 dz = 1.0f
        Float32 inv = 1.0f / Mathf.sqrt( dx * dx + dy * dy + dz * dz )

        Ray ray = Ray()
        ray.origin = Float32_3( this.eyeX, this.eyeY, this.eyeZ )
        ray.direction = Float32_3( dx * inv, dy * inv, dz * inv )

        RayHit h0 = RayHit()
        if this.nearestHit( ray, h0 ) == false
        {
            ret Float32_3( this.bgR, this.bgG, this.bgB )
        }
        Float32_3 local0 = this.shadeLocal( h0 )
        if h0.reflect <= 0.0f
        {
            ret local0
        }

        # 反射射线（d/n 均单位向量，反射方向保持单位长度）
        Float32 dd = Mathf.dot3( ray.direction.x, ray.direction.y, ray.direction.z, h0.nx, h0.ny, h0.nz )
        Float32 rdx = ray.direction.x - 2.0f * dd * h0.nx
        Float32 rdy = ray.direction.y - 2.0f * dd * h0.ny
        Float32 rdz = ray.direction.z - 2.0f * dd * h0.nz
        Ray rray = Ray()
        rray.origin = Float32_3( h0.px + h0.nx * RayScene.OFFSET,
                                 h0.py + h0.ny * RayScene.OFFSET,
                                 h0.pz + h0.nz * RayScene.OFFSET )
        rray.direction = Float32_3( rdx, rdy, rdz )

        RayHit h1 = RayHit()
        Float32_3 rc = null
        if this.nearestHit( rray, h1 )
        {
            rc = this.shadeLocal( h1 )
        }
        else
        {
            rc = Float32_3( this.bgR, this.bgG, this.bgB )
        }
        Float32 k = 1.0f - h0.reflect
        ret Float32_3( local0.x * k + rc.x * h0.reflect,
                       local0.y * k + rc.y * h0.reflect,
                       local0.z * k + rc.z * h0.reflect )
    }

    override string toString()
    {
        ret "RayScene(spheres=" + this._sphereCount.toString() + ", ground=" + ( this.groundOn ? "on" : "off" ) + ")"
    }
}
