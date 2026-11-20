import SimGameEngine;
import Std;
import Math;

# ============================================================================
# SimGizmoTest — 编辑器 Gizmo 验证（第 20 套，doc/21）
# ----------------------------------------------------------------------------
# 覆盖：常量表取值 / 变换三模式几何规模（move 箭头 / rotate 圆环 / scale 手柄）、
# 相机 2D/3D 图标规模、光源三类型图标规模、enabled/mode 状态机、缓冲清空、
# appendTo/vertexCountAt 槽读写、allFinite 数值健康检查、无 attach 离屏 endFrame。
# 写法约束（doc/10 §6）：跨模块只调 GizmoSystem 实例方法与 getters（GizmoGeometry
# 纯函数由 GizmoSystem 内部同模块消费）；浮点取粗界断言；保留字避让。
# ============================================================================

public class SimGizmoTest
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

    static Int32 passCount()
    {
        ret _pass
    }

    static Int32 failCount()
    {
        ret _fail
    }

    static void run()
    {
        Console.println( "  [Gizmo] constants + state machine" )
        GizmoSystem gs = GizmoSystem()
        Int32 defMode = gs.currentMode()
        check( defMode == GizmoTypes.MODE_MOVE, "default mode = MOVE (got " + defMode.toString() + ")" )
        check( gs.isEnabled(), "default enabled = true" )
        gs.setMode( GizmoTypes.MODE_ROTATE )
        check( gs.currentMode() == GizmoTypes.MODE_ROTATE, "setMode ROTATE" )
        gs.setMode( 99 )
        check( gs.currentMode() == GizmoTypes.MODE_ROTATE, "illegal mode ignored" )
        gs.setMode( GizmoTypes.MODE_SCALE )
        check( gs.currentMode() == GizmoTypes.MODE_SCALE, "setMode SCALE" )

        Console.println( "  [Gizmo] transform geometry (move/rotate/scale)" )
        Float32_3 c = Float32_3( 1.0f, 2.0f, 3.0f )
        # NONE mode 不产几何
        gs.setMode( GizmoTypes.MODE_NONE )
        gs.beginFrame()
        gs.drawTransform( c )
        check( gs.totalVertexCount() == 0, "NONE mode yields no geometry" )

        # MOVE: 每轴 arrow = seg(6) + 2 tri(6) = 12 顶点
        gs.setMode( GizmoTypes.MODE_MOVE )
        gs.beginFrame()
        gs.drawTransform( c )
        Int32 mx = gs.vertexCountAt( 0 )
        Int32 my = gs.vertexCountAt( 1 )
        Int32 mz = gs.vertexCountAt( 2 )
        check( mx == 12, "MOVE X arrow vertices = 12 (got " + mx.toString() + ")" )
        check( my == 12, "MOVE Y arrow vertices = 12 (got " + my.toString() + ")" )
        check( mz == 12, "MOVE Z arrow vertices = 12 (got " + mz.toString() + ")" )
        check( gs.allFinite(), "MOVE geometry all finite" )

        # ROTATE: 每轴 ring segments=24 → 24×2 tri = 144 顶点
        gs.setMode( GizmoTypes.MODE_ROTATE )
        gs.beginFrame()
        gs.drawTransform( c )
        Int32 rx = gs.vertexCountAt( 0 )
        Int32 ry = gs.vertexCountAt( 1 )
        Int32 rz = gs.vertexCountAt( 2 )
        check( rx == 144, "ROTATE X ring vertices = 144 (got " + rx.toString() + ")" )
        check( ry == 144, "ROTATE Y ring vertices = 144 (got " + ry.toString() + ")" )
        check( rz == 144, "ROTATE Z ring vertices = 144 (got " + rz.toString() + ")" )
        check( gs.allFinite(), "ROTATE geometry all finite" )

        # SCALE: 每轴 scaleHandle = seg(6) + box(6) = 12 顶点
        gs.setMode( GizmoTypes.MODE_SCALE )
        gs.beginFrame()
        gs.drawTransform( c )
        Int32 sx = gs.vertexCountAt( 0 )
        Int32 sy = gs.vertexCountAt( 1 )
        Int32 sz = gs.vertexCountAt( 2 )
        check( sx == 12, "SCALE X handle vertices = 12 (got " + sx.toString() + ")" )
        check( sy == 12, "SCALE Y handle vertices = 12 (got " + sy.toString() + ")" )
        check( sz == 12, "SCALE Z handle vertices = 12 (got " + sz.toString() + ")" )
        check( gs.allFinite(), "SCALE geometry all finite" )

        Console.println( "  [Gizmo] camera / light icons" )
        # 相机 2D: box(6) + 3 seg(18) = 24；3D: +1 seg(6) = 30
        gs.beginFrame()
        gs.drawCamera( c, true )
        Int32 cam2 = gs.vertexCountAt( 4 )
        check( cam2 == 24, "CAMERA 2D icon vertices = 24 (got " + cam2.toString() + ")" )
        gs.beginFrame()
        gs.drawCamera( c, false )
        Int32 cam3 = gs.vertexCountAt( 4 )
        check( cam3 == 30, "CAMERA 3D icon vertices = 30 (got " + cam3.toString() + ")" )
        check( gs.allFinite(), "CAMERA icon all finite" )

        # 光源三类型（is2D=false 含额外 Y 环）：DIR / POINT / SPOT 顶点数各异且为正
        gs.beginFrame()
        gs.drawLight( c, GizmoTypes.LIGHT_DIRECTIONAL, false )
        Int32 ld = gs.vertexCountAt( 5 )
        gs.beginFrame()
        gs.drawLight( c, GizmoTypes.LIGHT_POINT, false )
        Int32 lp = gs.vertexCountAt( 5 )
        gs.beginFrame()
        gs.drawLight( c, GizmoTypes.LIGHT_SPOT, false )
        Int32 ls = gs.vertexCountAt( 5 )
        check( ld > 0, "LIGHT directional icon non-empty (got " + ld.toString() + ")" )
        check( lp > 0, "LIGHT point icon non-empty (got " + lp.toString() + ")" )
        check( ls > 0, "LIGHT spot icon non-empty (got " + ls.toString() + ")" )
        check( lp > ld, "POINT rays > DIR rays" )
        check( gs.allFinite(), "LIGHT icon all finite" )

        Console.println( "  [Gizmo] lifecycle + slots" )
        # beginFrame 清空全部槽
        gs.beginFrame()
        check( gs.totalVertexCount() == 0, "beginFrame clears all buffers" )
        # enabled=false 禁止产几何
        gs.enabled = false
        gs.setMode( GizmoTypes.MODE_MOVE )
        gs.beginFrame()
        gs.drawTransform( c )
        gs.drawCamera( c, true )
        gs.drawLight( c, GizmoTypes.LIGHT_POINT, false )
        check( gs.totalVertexCount() == 0, "disabled yields no geometry" )
        gs.enabled = true

        # appendTo / vertexCountAt 槽读写 + totalVertexCount
        gs.beginFrame()
        gs.appendTo( 3, Float32_3( 1.0f, 1.0f, 1.0f ) )
        gs.appendTo( 3, Float32_3( 2.0f, 2.0f, 2.0f ) )
        check( gs.vertexCountAt( 3 ) == 2, "appendTo slot3 count = 2" )
        check( gs.totalVertexCount() == 2, "totalVertexCount = 2" )
        gs.appendTo( 0, Float32_3( 0.0f, 0.0f, 0.0f ) )
        check( gs.vertexCountAt( 0 ) == 1, "appendTo slot0 count = 1" )
        check( gs.totalVertexCount() == 3, "totalVertexCount = 3" )
        # 非法槽忽略
        gs.appendTo( 9, Float32_3( 1.0f, 1.0f, 1.0f ) )
        check( gs.totalVertexCount() == 3, "illegal slot ignored" )
        check( gs.allFinite(), "appended geometry all finite" )

        # 无 attach 离屏 endFrame 不崩溃、缓冲保留
        gs.endFrame()
        check( gs.totalVertexCount() == 3, "endFrame without attach keeps buffers" )

        Console.println( "  [Gizmo] PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
    }
}
