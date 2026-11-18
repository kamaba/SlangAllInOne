import Core;
import Std;

# ============================================================================
# ShapeTypes — 固定形状库形状号常量表（P9 shape 库，doc/17）
# ----------------------------------------------------------------------------
# 数值与 C 侧 sle_engine.h / sle_shape_dims 的形状表逐项一致（改一处必须同步
# 另一处）。全部形状：中心在原点、Y 轴向上、右手系、从外侧看逆时针（CCW）。
# 注意（doc/10 §6 实证）：把 static 常量字段直接作实参传给方法会触发
# MetaCoreCallNotSupportNotSupport（如 build(ShapeTypes.CUBE, ...)）——
# 先赋局部变量再传（Int32 t = ShapeTypes.CUBE），或直接用字面量。
# ============================================================================

public class ShapeTypes
{
    # 盒（参数 sx,sy,sz）
    public static Int32 CUBE = 0
    # XZ 平面网格（width,height,cols,rows，法线 +Y）
    public static Int32 PLANE = 1
    # XY 单面片（width,height，法线 +Z）
    public static Int32 SPRITE = 2
    # 经纬球（radius,segU,segV）
    public static Int32 SPHERE = 3
    # 圆柱含双端盖（radius,height,segments,heightSegments）
    public static Int32 CYLINDER = 4
    # 圆锥含底盖（radius,height,segments）
    public static Int32 CONE = 5
    # 圆环主圈绕 +Y（radius,tube,segU,segV）
    public static Int32 TORUS = 6
    # 三棱柱顶点朝上沿 Z 拉伸（sx,sy,sz）
    public static Int32 PRISM = 7
    # 空心管含双环端盖（radius,height,thickness,segments）
    public static Int32 PIPE = 8
    # 竖直拱带 XY 弧 Z 向宽（angleDeg,radius,width,thickness,segments）
    public static Int32 ARCH = 9
    # 直梯沿 +Z 上升整梯居中（steps,width,stepHeight,depth）
    public static Int32 STAIR = 10
    # 门框：左立柱 + 右立柱 + 顶梁三盒组装，中间门洞（ProBuilder Door 同款；
    # sx,sy,sz,lintel,legWidth —— lintel 顶梁高、legWidth 立柱宽）
    public static Int32 DOOR = 11
}
