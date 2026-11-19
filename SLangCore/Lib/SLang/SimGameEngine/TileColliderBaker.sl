import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# TileColliderBaker — Tilemap 实心格 → 碰撞体生成器（P7 2D，doc/15 §9）
# ----------------------------------------------------------------------------
# 2D 地形碰撞不逐格建节点：把同一行的连续实心格合并成一段，每段一个
# 子 GameObject + BoxCollider（横版/俯视通用；段数 = 行内实心游程数）。
# 段几何（parent 局部系，parent = Tilemap 挂载节点）：
#   段 [x0, x0+len-1] 行 y → center = ((x0 + len/2) * cell, (y+0.5) * cell, 0)
#   size = (len * cell, cell, cell)
# 实心判定 = Tilemap.isSolidAt（tile >= 0 且 tileFlag bit0 == 1，
# tile 属性表见 Tilemap.setTileFlag）。
# 静态方法承载循环（plain 类循环读外部对象字段 = 实证可靠形态，
# doc/10 §6）；GameObject 名用前缀 + 序号避免 NodeRegistry 重名。
# ============================================================================

public class TileColliderBaker
{
    # 按行合并实心格生成碰撞段；返回创建的段数。
    # scene/parent 任一为空返回 0。
    public static Int32 bakeRowColliders( Scene scene, Tilemap tm, GameObject parent, string namePrefix )
    {
        Int32 made = 0
        if scene == null
        {
            ret 0
        }
        if tm == null
        {
            ret 0
        }
        if parent == null
        {
            ret 0
        }
        Float32 cs = tm.cellSize
        Int32 w = tm.width
        Int32 h = tm.height
        Int32 y = 0
        while y < h
        {
            Int32 x = 0
            while x < w
            {
                bool solid = tm.isSolidAt( x, y )
                if solid
                {
                    Int32 end = x
                    Int32 nx = x + 1
                    bool open = true
                    while open
                    {
                        if nx < w
                        {
                            bool ext = tm.isSolidAt( nx, y )
                            if ext
                            {
                                end = nx
                                nx = nx + 1
                            }
                            else
                            {
                                open = false
                            }
                        }
                        else
                        {
                            open = false
                        }
                    }
                    Int32 len = end - x + 1
                    string segName = namePrefix + made.toString()
                    GameObject seg = scene.createObject( segName, parent )
                    Transform t = seg.transform
                    Float32 fx = x.toFloat32()
                    Float32 fl = len.toFloat32()
                    Float32 fy = y.toFloat32()
                    Float32 cxf = ( fx + fl * 0.5f ) * cs
                    Float32 cyf = ( fy + 0.5f ) * cs
                    Float32_3 p = Float32_3( cxf, cyf, 0.0f )
                    t.setPosition( p )
                    BoxCollider bc = BoxCollider()
                    Float32_3 c = Float32_3( 0.0f, 0.0f, 0.0f )
                    Float32_3 s = Float32_3( fl * cs, cs, cs )
                    bc.center = c
                    bc.size = s
                    seg.addComponent( bc )
                    made = made + 1
                    x = end + 1
                }
                else
                {
                    x = x + 1
                }
            }
            y = y + 1
        }
        ret made
    }
}
