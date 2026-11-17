import Core;
import Std;
import Math;

# ============================================================================
# ShapeFactory — 固定形状工厂（P9 shape 库，doc/17）
# ----------------------------------------------------------------------------
# 计算核心在 C（sle_shape_counts/sle_shape_build，经 EngineFfi 绑定），本类
# 只做组块/解块门面（专项约定）：shapeParams 打包 float 块 → counts 两段式拿
# V/T → 按规模分配 Memory 块 → build 填充 → 读回 SL Array → 释放块。
# 每形状一个便捷方法（参数即 C 侧形状表参数序）；通用入口 build(type, shapeParams)。
# 注意（doc/10 §6 实证）：
#   ① static 常量字段不作实参——便捷方法内部用字面量形状号；
#   ② 方法调用不作实参——全部先取局部变量；
#   ③ 绑定失败（libShapeCounts 兜底 -1）返回 null，调用方判空。
# ============================================================================

public class ShapeFactory
{
    # 通用入口：shapeType 取 ShapeTypes 常量（先赋局部变量再传）；shapeParams 参数块
    # 各形状参数个数见 doc/17 形状表（整型参数以 Float32 传入）。
    public static ShapeMesh build( Int32 shapeType, Array<Float32> shapeParams )
    {
        Int32 pc = 0
        if shapeParams != null
        {
            pc = shapeParams.length
        }
        Int64 pp = Memory.alloc( pc * 4 )
        if pp == 0
        {
            ret null
        }
        Int32 i = 0
        while i < pc
        {
            Float32 val = shapeParams[ i ]
            Memory.writeF32( pp, i * 4, val )
            i = i + 1
        }
        Int64 cp = Memory.alloc( 8 )
        if cp == 0
        {
            Memory.free( pp )
            ret null
        }
        Int32 rc = EngineFfi.libShapeCounts( shapeType, pp, pc, cp )
        if rc != 0
        {
            Memory.free( pp )
            Memory.free( cp )
            ret null
        }
        Int32 v = Memory.readInt32( cp, 0 )
        Int32 t = Memory.readInt32( cp, 4 )
        Memory.free( cp )
        if v < 1 || t < 1
        {
            Memory.free( pp )
            ret null
        }
        Int64 vp = Memory.alloc( v * 32 )
        Int64 tp = Memory.alloc( t * 12 )
        if vp == 0 || tp == 0
        {
            if vp != 0
            {
                Memory.free( vp )
            }
            if tp != 0
            {
                Memory.free( tp )
            }
            Memory.free( pp )
            ret null
        }
        Int32 rb = EngineFfi.libShapeBuild( shapeType, pp, pc, vp, tp )
        Memory.free( pp )
        if rb < 1
        {
            Memory.free( vp )
            Memory.free( tp )
            ret null
        }
        Array<Float32> pos = Array<Float32>( v * 3 )
        Array<Float32> nrm = Array<Float32>( v * 3 )
        Array<Float32> uv = Array<Float32>( v * 2 )
        Array<Int32> tri = Array<Int32>( t * 3 )
        Int32 total3 = v * 3
        Int32 total2 = v * 2
        Int32 triTotal = t * 3
        Int32 normBase = v * 3
        Int32 uvBase = v * 6
        Int32 k = 0
        while k < total3
        {
            pos[ k ] = Memory.readFloat32( vp, k * 4 )
            nrm[ k ] = Memory.readFloat32( vp, ( normBase + k ) * 4 )
            k = k + 1
        }
        k = 0
        while k < total2
        {
            uv[ k ] = Memory.readFloat32( vp, ( uvBase + k ) * 4 )
            k = k + 1
        }
        k = 0
        while k < triTotal
        {
            tri[ k ] = Memory.readInt32( tp, k * 4 )
            k = k + 1
        }
        Memory.free( vp )
        Memory.free( tp )
        ShapeMesh mesh = ShapeMesh( pos, nrm, uv, tri )
        ret mesh
    }

    # ── 各形状便捷方法（参数序 = C 侧形状表；形状号用字面量）──

    public static ShapeMesh cube( Float32 sx, Float32 sy, Float32 sz )
    {
        Array<Float32> p = Array<Float32>( 3 )
        p[0] = sx
        p[1] = sy
        p[2] = sz
        ShapeMesh m = ShapeFactory.build( 0, p )
        ret m
    }

    public static ShapeMesh plane( Float32 width, Float32 height, Int32 cols, Int32 rows )
    {
        Array<Float32> p = Array<Float32>( 4 )
        p[0] = width
        p[1] = height
        p[2] = cols * 1.0f
        p[3] = rows * 1.0f
        ShapeMesh m = ShapeFactory.build( 1, p )
        ret m
    }

    public static ShapeMesh sprite( Float32 width, Float32 height )
    {
        Array<Float32> p = Array<Float32>( 2 )
        p[0] = width
        p[1] = height
        ShapeMesh m = ShapeFactory.build( 2, p )
        ret m
    }

    public static ShapeMesh sphere( Float32 radius, Int32 segU, Int32 segV )
    {
        Array<Float32> p = Array<Float32>( 3 )
        p[0] = radius
        p[1] = segU * 1.0f
        p[2] = segV * 1.0f
        ShapeMesh m = ShapeFactory.build( 3, p )
        ret m
    }

    public static ShapeMesh cylinder( Float32 radius, Float32 height, Int32 segments, Int32 heightSegments )
    {
        Array<Float32> p = Array<Float32>( 4 )
        p[0] = radius
        p[1] = height
        p[2] = segments * 1.0f
        p[3] = heightSegments * 1.0f
        ShapeMesh m = ShapeFactory.build( 4, p )
        ret m
    }

    public static ShapeMesh cone( Float32 radius, Float32 height, Int32 segments )
    {
        Array<Float32> p = Array<Float32>( 3 )
        p[0] = radius
        p[1] = height
        p[2] = segments * 1.0f
        ShapeMesh m = ShapeFactory.build( 5, p )
        ret m
    }

    public static ShapeMesh torus( Float32 radius, Float32 tube, Int32 segU, Int32 segV )
    {
        Array<Float32> p = Array<Float32>( 4 )
        p[0] = radius
        p[1] = tube
        p[2] = segU * 1.0f
        p[3] = segV * 1.0f
        ShapeMesh m = ShapeFactory.build( 6, p )
        ret m
    }

    public static ShapeMesh prism( Float32 sx, Float32 sy, Float32 sz )
    {
        Array<Float32> p = Array<Float32>( 3 )
        p[0] = sx
        p[1] = sy
        p[2] = sz
        ShapeMesh m = ShapeFactory.build( 7, p )
        ret m
    }

    public static ShapeMesh pipe( Float32 radius, Float32 height, Float32 thickness, Int32 segments )
    {
        Array<Float32> p = Array<Float32>( 4 )
        p[0] = radius
        p[1] = height
        p[2] = thickness
        p[3] = segments * 1.0f
        ShapeMesh m = ShapeFactory.build( 8, p )
        ret m
    }

    public static ShapeMesh arch( Float32 angleDeg, Float32 radius, Float32 width, Float32 thickness, Int32 segments )
    {
        Array<Float32> p = Array<Float32>( 5 )
        p[0] = angleDeg
        p[1] = radius
        p[2] = width
        p[3] = thickness
        p[4] = segments * 1.0f
        ShapeMesh m = ShapeFactory.build( 9, p )
        ret m
    }

    public static ShapeMesh stair( Int32 steps, Float32 width, Float32 stepHeight, Float32 depth )
    {
        Array<Float32> p = Array<Float32>( 4 )
        p[0] = steps * 1.0f
        p[1] = width
        p[2] = stepHeight
        p[3] = depth
        ShapeMesh m = ShapeFactory.build( 10, p )
        ret m
    }
}
