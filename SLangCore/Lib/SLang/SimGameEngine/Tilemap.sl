import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# Tilemap — 2D 瓦片地图组件（P7，doc/15 §6）
# ----------------------------------------------------------------------------
# 数据：width×height 格子，每格一个图集索引（-1 = 空）；tiles 用
# Array<Int32>（List 下标写跨模块失效——doc/10 §6，CollisionSystem 同款）。
# 绘制策略：整张地图作为一个动态网格批次——可见格子顶点合并进调用方传入
# 的 List<Float32_3>（写入式 out 参数，bakeVerticesInto 同款），后续经
# uploadMesh 上传 MESH_CUSTOM 槽（uploadMesh 全量提交路径随相机投影专项，
# 本版先落数据与烘焙层）。简单裁剪：格子中心是否在相机正交边界内（外扩
# 半格防边缘裁切）。
# 世界约定：格子 (0,0) 中心 = 挂载节点 worldPosition + (cell/2, cell/2)，
# x 向右 y 向上；即节点位置是格子 (0,0) 的**左下角**。
# 排序：整图单批，sortingLayer/orderInLayer 与 SpriteRenderer 同一映射。
# 坑（doc/10 §6）：消费侧读数值字段跨模块不可靠——统一走方法
# （getTile/getTile 等）与写入式 bake（out 参数）。
# ============================================================================

public class Tilemap extends Behaviour
{
    public bool visible = true
    # 图集句柄 id（图集切分数据由业务侧维护，doc/15 §3.3）
    public Int32 atlasTextureId = 0
    public Int32 width = 0
    public Int32 height = 0
    public Float32 cellSize = 1.0f
    # 整图单批排序（与 SpriteRenderer 同一 SortingLayers 映射）
    public Int32 sortingLayer = 0
    public Int32 orderInLayer = 0

    # 格子存储：List<Int32>（**不用 Array**——Behaviour 子类的 Array 字段
    # 元素读进循环体上下文返回垃圾（Sim2DTest D9h/D10 实证：tileCount 全
    # 计满、bake 空格全烘焙；straight-line 调用可靠）。List 字段 + 方法内
    # 局部别名 + 局部变量下标是 Batcher/RenderSystem 实证可靠形态；
    # 元素写走 removeAt + insert（List 下标写 _setItem_ 跨模块静默失效，
    # doc/10 §6），-1 = 空）
    List<Int32> _tiles = List<Int32>( 0 )

    # tile 属性表（按 tile 图集索引，2026-11-19 补全；bit0 = solid 实心/
    # 阻挡，其余位业务自定义）。默认全 0 = 非实心；空格(-1)恒非实心。
    List<Int32> _flags = List<Int32>( 0 )

    # 分配/重置格子（全部填 -1 = 空）
    public void resize( Int32 w, Int32 h )
    {
        if w < 0
        {
            w = 0
        }
        if h < 0
        {
            h = 0
        }
        this.width = w
        this.height = h
        Int32 n = w * h
        List<Int32> tiles = List<Int32>( n )
        Int32 i = 0
        while i < n
        {
            tiles.add( 0 - 1 )
            i = i + 1
        }
        this._tiles = tiles
    }

    public bool inBounds( Int32 x, Int32 y )
    {
        if x < 0
        {
            ret false
        }
        if y < 0
        {
            ret false
        }
        if x > this.width - 1
        {
            ret false
        }
        if y > this.height - 1
        {
            ret false
        }
        ret true
    }

    public void setTile( Int32 x, Int32 y, Int32 index )
    {
        if !this.inBounds( x, y )
        {
            ret
        }
        List<Int32> tiles = this._tiles
        Int32 idx = y * this.width + x
        tiles.removeAt( idx )
        tiles.insert( idx, index )
    }

    # 越界返回 -1（与空格同值）
    public Int32 getTile( Int32 x, Int32 y )
    {
        if !this.inBounds( x, y )
        {
            ret 0 - 1
        }
        List<Int32> tiles = this._tiles
        Int32 idx = y * this.width + x
        Int32 v = tiles[idx]
        ret v
    }

    # 非空格子数（循环逻辑在 static 承载——Behaviour 子类实例方法体内含
    # while 循环时自身字段读失效（Sim2DTest D9h/D10 实证：straight-line
    # 方法可靠、含循环方法内 this._tiles 别名读全 0）；static 无 this，
    # 等价 Batcher.collect「plain 类循环读外部对象字段」可靠形态）
    public Int32 tileCount()
    {
        ret Tilemap.tileCountOf( this )
    }

    public static Int32 tileCountOf( Tilemap tm )
    {
        List<Int32> tiles = tm._tiles
        Int32 w = tm.width
        Int32 h = tm.height
        Int32 c = 0
        Int32 i = 0
        Int32 n = w * h
        # 坑：循环体内「t > 0 - 1」常量表达式比较失效（Sim2DTest D9h 实证：
        # 逐元素读值正确但比较恒真）——比较两侧一律局部变量（Batcher
        # oq > iq 实证形态）
        Int32 emptyVal = 0 - 1
        while i < n
        {
            Int32 t = tiles[i]
            if t > emptyVal
            {
                c = c + 1
            }
            i = i + 1
        }
        ret c
    }

    # 格子 (x,y) 的世界中心（挂载节点 worldPosition 为格子 (0,0) 左下角）
    public Float32_3 cellCenterWorld( Int32 x, Int32 y )
    {
        Float32_3 origin = Tilemap.originOf( this )
        Float32 fx = x.toFloat32()
        Float32 fy = y.toFloat32()
        Float32 halfSize = this.cellSize * 0.5f
        Float32 cx = origin.x + fx * this.cellSize + halfSize
        Float32 cy = origin.y + fy * this.cellSize + halfSize
        ret Float32_3( cx, cy, origin.z )
    }

    # 挂载节点世界原点（格 (0,0) 左下角；无节点 = 世界原点）
    static Float32_3 originOf( Tilemap tm )
    {
        Float32_3 origin = Float32_3.zero()
        GameObject ow = tm.owner
        if ow != null
        {
            Transform t = ow.transform
            if t != null
            {
                origin = t.worldPosition()
            }
        }
        ret origin
    }

    # ── world→cell 换算（俯视网格类游戏语义，doc/15 §9）────
    # cell = floor((world - origin) / cellSize)；越界格也返回计算值
    #（负数格 = 地图外，调用方用 inBounds 判定）；cellSize <= 0 返回 0。
    public Int32 cellXAtWorld( Float32 wx )
    {
        Float32_3 origin = Tilemap.originOf( this )
        Float32 cs = this.cellSize
        if cs <= 0.0f
        {
            ret 0
        }
        Float32 fx = Mathf.floor( ( wx - origin.x ) / cs )
        ret fx.toInt32()
    }

    public Int32 cellYAtWorld( Float32 wy )
    {
        Float32_3 origin = Tilemap.originOf( this )
        Float32 cs = this.cellSize
        if cs <= 0.0f
        {
            ret 0
        }
        Float32 fy = Mathf.floor( ( wy - origin.y ) / cs )
        ret fy.toInt32()
    }

    # ── tile 属性表（按 tile 图集索引；bit0 = solid）────────
    # 写入（静态承载扩容循环——Behaviour 子类循环坑，doc/10 §6）
    public void setTileFlag( Int32 tileIndex, Int32 flags )
    {
        Tilemap.setTileFlagOf( this, tileIndex, flags )
    }

    public static void setTileFlagOf( Tilemap tm, Int32 tileIndex, Int32 flags )
    {
        if tileIndex < 0
        {
            ret
        }
        List<Int32> fl = tm._flags
        Int32 n = fl.length
        while n < tileIndex + 1
        {
            fl.add( 0 )
            n = n + 1
        }
        fl.removeAt( tileIndex )
        fl.insert( tileIndex, flags )
    }

    # 读取（越界/未登记 = 0 = 非实心）
    public Int32 tileFlag( Int32 tileIndex )
    {
        ret Tilemap.tileFlagOf( this, tileIndex )
    }

    public static Int32 tileFlagOf( Tilemap tm, Int32 tileIndex )
    {
        if tileIndex < 0
        {
            ret 0
        }
        List<Int32> fl = tm._flags
        Int32 n = fl.length
        if tileIndex > n - 1
        {
            ret 0
        }
        Int32 v = fl[tileIndex]
        ret v
    }

    # 格 (x,y) 是否实心：tile >= 0 且属性 bit0 == 1（空格恒非实心）
    public bool isSolidAt( Int32 x, Int32 y )
    {
        Int32 t = this.getTile( x, y )
        if t < 0
        {
            ret false
        }
        Int32 f = Tilemap.tileFlagOf( this, t )
        Int32 bit = f & 1
        ret bit == 1
    }

    # ── 顶点烘焙 ─────────────────────────────────────────
    # 可见格子（tile >= 0 且中心在 [camL,camR]×[camB,camT] 外扩半格内）
    # 世界空间 quad 顶点追加进 sink（每格 6 顶点）；返回烘焙格数。
    # 循环逻辑在 static bakeOf 承载（同 tileCount 说明）；（`out` 是保留字）
    public Int32 bake( Float32 camL, Float32 camR, Float32 camB, Float32 camT, List<Float32_3> sink )
    {
        ret Tilemap.bakeOf( this, camL, camR, camB, camT, sink )
    }

    public static Int32 bakeOf( Tilemap tm, Float32 camL, Float32 camR, Float32 camB, Float32 camT, List<Float32_3> sink )
    {
        Int32 count = 0
        if sink == null
        {
            ret 0
        }
        List<Int32> tiles = tm._tiles
        Int32 w = tm.width
        Int32 h = tm.height
        Float32 cs = tm.cellSize
        # 坑：常量表达式比较失效——两侧局部变量（同 tileCountOf）
        Int32 emptyVal = 0 - 1
        Int32 y = 0
        while y < h
        {
            Int32 x = 0
            while x < w
            {
                Int32 idx = y * w + x
                Int32 t = tiles[idx]
                if t > emptyVal
                {
                    Float32_3 cc = tm.cellCenterWorld( x, y )
                    Float32 hh = cs * 0.5f
                    Float32 leftEdge = camL - hh
                    Float32 rightEdge = camR + hh
                    Float32 bottomEdge = camB - hh
                    Float32 topEdge = camT + hh
                    bool bx = ( cc.x > leftEdge ) && ( cc.x < rightEdge )
                    bool by = ( cc.y > bottomEdge ) && ( cc.y < topEdge )
                    bool vis = bx && by
                    if vis
                    {
                        Float32 lx = cc.x - hh
                        Float32 rx = cc.x + hh
                        Float32 ly = cc.y - hh
                        Float32 uy = cc.y + hh
                        Float32_3 a = Float32_3( lx, ly, cc.z )
                        Float32_3 b = Float32_3( lx, uy, cc.z )
                        Float32_3 c = Float32_3( rx, uy, cc.z )
                        Float32_3 d = Float32_3( rx, ly, cc.z )
                        Tilemap.pushQuad( sink, a, b, c, d )
                        count = count + 1
                    }
                }
                x = x + 1
            }
            y = y + 1
        }
        ret count
    }

    # 无裁剪全量烘焙
    public Int32 bakeAll( List<Float32_3> sink )
    {
        ret this.bake( 0.0f - 1000000.0f, 1000000.0f, 0.0f - 1000000.0f, 1000000.0f, sink )
    }

    # 单格 quad = 2 三角形 6 顶点（MeshRef.quadVertices 同款绕序）
    static void pushQuad( List<Float32_3> v, Float32_3 a, Float32_3 b, Float32_3 c, Float32_3 d )
    {
        v.add( a )
        v.add( b )
        v.add( c )
        v.add( a )
        v.add( c )
        v.add( d )
    }
}
