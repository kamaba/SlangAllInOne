import SimGameEngine;
import SLangRender;
import Math;
import Std;

# ============================================================================
# SimCameraLightTest — Camera/Light 实体（extends GameObject + Data 组件）第 18 套
# ----------------------------------------------------------------------------
# 覆盖：
#   C1  CameraData 默认值 / 常量 / setter / 裁剪面修正 / 投影矩阵（透视+正交）
#   C2  Camera extends GameObject：Transform/components 初始化、CameraData 组件
#       绑定（getComponent 可查）、参数转发、四类矩阵/坐标方法
#   C3  Light extends GameObject：LightData 组件绑定、工厂、setter、衰减
# 写法约束（doc/10 §6）：常量先落局部；跨模块链拆单步；static 字段不作实参。
# 纯 SL + Math，不依赖 GL/C 核心，稳定可复现。
# ============================================================================

public class SimCameraLightTest
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            _pass = _pass + 1
        }
        else
        {
            _fail = _fail + 1
            Console.println( "[FAIL] " + msg )
        }
    }

    static bool near( Float32 a, Float32 b, Float32 eps )
    {
        Float32 d = a - b
        if d < 0.0f
        {
            d = 0.0f - d
        }
        ret d <= eps
    }

    # ── C1. CameraData 数据组件 ──────────────────────────
    static void testCameraData()
    {
        CameraData cd = CameraData()
        check( cd.isOrthographic == false, "C1a default perspective" )
        check( near( cd.fieldOfView, 60.0f, 0.001f ), "C1b default fov 60" )
        check( near( cd.nearClipPlane, 0.1f, 0.001f ), "C1c default near" )
        check( near( cd.farClipPlane, 1000.0f, 0.001f ), "C1d default far" )
        check( near( cd.aspect, 1.0f, 0.001f ), "C1e default aspect" )
        check( cd.cullingMask == -1, "C1f default cull all" )

        Int32 clrAll = CameraData.CLEAR_ALL
        check( clrAll == 3, "C1g CLEAR_ALL constant" )

        cd.setFieldOfView( 45.0f )
        check( near( cd.fieldOfView, 45.0f, 0.001f ), "C1h setFieldOfView" )
        cd.setOrthographicSize( 8.0f )
        check( near( cd.orthographicSize, 8.0f, 0.001f ), "C1i setOrthographicSize" )
        cd.setAspect( 2.0f )
        check( near( cd.orthographicHalfWidth(), 16.0f, 0.001f ), "C1j ortho half width" )
        cd.setPixelRect( 800, 400 )
        check( near( cd.aspect, 2.0f, 0.001f ), "C1k setPixelRect aspect" )

        # 裁剪面修正：near<=0 -> 0.01；far<=near -> near+1
        cd.setClipPlanes( 0.0f - 1.0f, 0.0f )
        check( near( cd.nearClipPlane, 0.01f, 0.0001f ), "C1l clamp near" )
        check( cd.farClipPlane > cd.nearClipPlane, "C1m clamp far > near" )

        # 投影矩阵：正交 halfW=orthoSize*aspect, halfH=orthoSize
        cd.setOrthographic( true )
        cd.setOrthographicSize( 5.0f )
        cd.setAspect( 2.0f )
        cd.setClipPlanes( 0.1f, 100.0f )
        Float32_4x4 op = cd.projectionMatrix()
        check( near( op.getValue( 0, 0 ), 0.1f, 0.0001f ), "C1n ortho m00=1/halfW" )
        check( near( op.getValue( 1, 1 ), 0.2f, 0.0001f ), "C1o ortho m11=1/halfH" )

        # 透视投影矩阵基本非零
        cd.setOrthographic( false )
        Float32_4x4 pp = cd.projectionMatrix()
        check( pp.getValue( 0, 0 ) > 0.0f, "C1p perspective m00>0" )
    }

    # ── C2. Camera 实体 ──────────────────────────────────
    static void testCamera()
    {
        Camera cam = Camera( "MainCamera" )
        check( cam.name == "MainCamera", "C2a name" )
        check( cam.transform != null, "C2b transform initialized" )
        check( cam.components.length >= 2, "C2c components has transform+data" )
        check( cam.cameraData != null, "C2d cameraData bound" )

        # getComponent 能查到组件（验证 addComponent 回填正确）
        CameraData found = cam.getComponent<CameraData>()
        check( found != null, "C2e getComponent<CameraData>" )
        check( found == cam.cameraData, "C2f component identity" )

        # 参数转发
        cam.setOrthographic( true )
        cam.setOrthographicSize( 4.0f )
        cam.setAspect( 2.0f )
        cam.setClipPlanes( 0.5f, 50.0f )
        check( cam.cameraData.isOrthographic, "C2g forward ortho" )
        check( near( cam.orthographicHalfWidth(), 8.0f, 0.001f ), "C2h forward half width" )
        check( near( cam.nearClipPlane(), 0.5f, 0.001f ), "C2i forward near" )
        check( near( cam.farClipPlane(), 50.0f, 0.001f ), "C2j forward far" )

        # 投影/视图/VP 矩阵
        Float32_4x4 proj = cam.projectionMatrix()
        check( near( proj.getValue( 0, 0 ), 0.125f, 0.0001f ), "C2k projection m00" )
        Float32_4x4 c2w = cam.cameraToWorldMatrix()
        check( near( c2w.getValue( 0, 0 ), 1.0f, 0.0001f ), "C2l cameraToWorld identity so far" )
        Float32_4x4 w2c = cam.worldToCameraMatrix()
        check( near( w2c.getValue( 0, 0 ), 1.0f, 0.0001f ), "C2m worldToCamera identity so far" )
        Float32_4x4 vp = cam.viewProjectionMatrix()
        check( vp.getValue( 0, 0 ) > 0.0f, "C2n viewProjection m00>0" )

        # 移动节点后世界矩阵反映平移（跨模块字段链先落局部变量）
        Transform camT = cam.transform
        camT.position = Float32_3( 10.0f, 2.0f, 0.0f )
        Float32_4x4 c2w2 = cam.cameraToWorldMatrix()
        check( near( c2w2.getValue( 0, 3 ), 10.0f, 0.001f ), "C2o cameraToWorld translate x" )
        check( near( c2w2.getValue( 1, 3 ), 2.0f, 0.001f ), "C2p cameraToWorld translate y" )
        Float32_4x4 w2c2 = cam.worldToCameraMatrix()
        check( near( w2c2.getValue( 0, 3 ), 0.0f - 10.0f, 0.001f ), "C2q worldToCamera inverse tx" )

        # TRS 变换
        Float32_3 tp = cam.transformPoint( Float32_3.zero() )
        check( near( tp.x, 10.0f, 0.001f ), "C2r transformPoint origin -> eye" )
        Float32_3 wp = cam.worldToLocal( Float32_3( 10.0f, 2.0f, 0.0f ) )
        check( near( wp.x, 0.0f, 0.001f ), "C2s worldToLocal at eye -> origin" )

        # 工厂
        Camera c2 = Camera.create( "Aux" )
        check( c2.name == "Aux", "C2t create factory" )
    }

    # ── C3. Light 实体 ───────────────────────────────────
    static void testLight()
    {
        Light l = Light( "Sun" )
        check( l.name == "Sun", "C3a name" )
        check( l.transform != null, "C3b transform initialized" )
        check( l.lightData != null, "C3c lightData bound" )
        LightData found = l.getComponent<LightData>()
        check( found != null, "C3d getComponent<LightData>" )
        check( found == l.lightData, "C3e component identity" )

        # 参数转发
        l.setIntensity( 2.5f )
        check( near( l.lightData.intensity, 2.5f, 0.001f ), "C3f setIntensity" )
        l.setColor( 1.0f, 0.5f, 0.25f )
        check( near( l.lightData.color.x, 1.0f, 0.001f ), "C3g setColor r" )
        check( near( l.lightData.color.z, 0.25f, 0.001f ), "C3h setColor b" )
        l.setDirection( 0.6f, 0.8f )
        check( near( l.lightData.dirX, 0.6f, 0.001f ), "C3i setDirection x" )

        # 工厂设定 type
        Light dl = Light.directional( "Dir" )
        check( dl.lightData.type == 0, "C3j directional factory" )
        Light pl = Light.point( "Pt" )
        check( pl.lightData.type == 1, "C3k point factory" )
        Light sl = Light.spot( "Spot" )
        check( sl.lightData.type == 2, "C3l spot factory" )

        # 衰减
        Light pl2 = Light.point( "Pt2" )
        pl2.setRange( 10.0f )
        check( near( pl2.attenuation( 0.0f ), 1.0f, 0.001f ), "C3m attenuation at 0" )
        check( near( pl2.attenuation( 10.0f ), 0.0f, 0.001f ), "C3n attenuation at range" )
        check( near( pl2.attenuation( 5.0f ), 0.5f, 0.001f ), "C3o attenuation mid" )

        # 聚光锥角衰减
        Light spot2 = Light.spot( "Spot2" )
        spot2.setSpotAngle( 30.0f )
        check( spot2.spotAttenuation( 1.0f ) > 0.99f, "C3p spot attenuation on axis" )
        check( near( spot2.spotAttenuation( 0.0f ), 0.0f, 0.001f ), "C3q spot attenuation off axis" )
    }

    public static void run()
    {
        testCameraData()
        testCamera()
        testLight()
    }

    public static Int32 passCount()
    {
        ret _pass
    }

    public static Int32 failCount()
    {
        ret _fail
    }
}
