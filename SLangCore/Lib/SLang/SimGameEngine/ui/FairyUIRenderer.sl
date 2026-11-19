import Core;
import Std;
import Math;
import SLangRender;
# ============================================================================
# FairyGUI 渲染层（顶点生成 / RenderSystem 提交 / 点击命中）
# ----------------------------------------------------------------------------
# 整张 UI 烘焙成一个带 UV 的自定义网格（pos2+uv2，stride 16B）交
# RenderSystem.submitUiMesh（动态网格槽 3 + UI 叠加相机 layer 31）。
# 顶点在 draw 内联生成（发布构建下多参数方法调用路径有已知问题，
# 见 troubleshooting/06）。hitTestLocal 把渲染面局部像素换算成设计坐标，
# 倒序取最上层 quad 命中（菜单项统一命名 menu_N 配合 menuIndex）。
# ============================================================================
public class FairyUIRenderer
{
    public FairyPackage pkg = null
    public Float32 aspect = 1.0f
    public string lastError = ""
    public Int32 lastVerts = 0
    public Int32 lastQuads = 0

    public void _init_()
    {
        this.aspect = 1.0f
    }

    public Int32 vertCountOf( FairyQuad q )
    {
        if q.use9
        {
            ret 54
        }
        ret 6
    }

    Int32 emitOne( Int64 ptr, Int32 cursor,
        Float32 dx, Float32 dy, Float32 dw, Float32 dh,
        Float32 u0, Float32 vTop, Float32 u1, Float32 vBot )
    {
        Float32 dwf = this.pkg.designW.toFloat32()
        Float32 dhf = this.pkg.designH.toFloat32()
        if dwf <= 0.0f || dhf <= 0.0f
        {
            ret cursor
        }
        Float32 nx0 = ( dx / dwf * 2.0f - 1.0f ) / this.aspect
        Float32 nx1 = ( ( dx + dw ) / dwf * 2.0f - 1.0f ) / this.aspect
        Float32 nyTop = 1.0f - dy / dhf * 2.0f
        Float32 nyBot = 1.0f - ( dy + dh ) / dhf * 2.0f
        Int32 off = cursor * 16
        Memory.writeF32( ptr, off + 0, nx0 )
        Memory.writeF32( ptr, off + 4, nyTop )
        Memory.writeF32( ptr, off + 8, u0 )
        Memory.writeF32( ptr, off + 12, vTop )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx0 )
        Memory.writeF32( ptr, off + 4, nyBot )
        Memory.writeF32( ptr, off + 8, u0 )
        Memory.writeF32( ptr, off + 12, vBot )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx1 )
        Memory.writeF32( ptr, off + 4, nyBot )
        Memory.writeF32( ptr, off + 8, u1 )
        Memory.writeF32( ptr, off + 12, vBot )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx0 )
        Memory.writeF32( ptr, off + 4, nyTop )
        Memory.writeF32( ptr, off + 8, u0 )
        Memory.writeF32( ptr, off + 12, vTop )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx1 )
        Memory.writeF32( ptr, off + 4, nyBot )
        Memory.writeF32( ptr, off + 8, u1 )
        Memory.writeF32( ptr, off + 12, vBot )
        off = off + 16
        Memory.writeF32( ptr, off + 0, nx1 )
        Memory.writeF32( ptr, off + 4, nyTop )
        Memory.writeF32( ptr, off + 8, u1 )
        Memory.writeF32( ptr, off + 12, vTop )
        ret cursor + 6
    }

    Int32 emitQuad( Int64 ptr, Int32 cursor, FairyQuad q )
    {
        if !q.use9 || q.sw <= 0.0f || q.sh <= 0.0f
        {
            ret this.emitOne( ptr, cursor, q.x, q.y, q.w, q.h, q.u0, q.vTop, q.u1, q.vBot )
        }
        Float32 l = q.bl
        Float32 t = q.bt
        Float32 r = q.br
        Float32 b = q.bb
        Int32 col = 0
        while col < 3
        {
            Float32 ssx = 0.0f
            Float32 ssw = 0.0f
            Float32 ddx = 0.0f
            Float32 ddw = 0.0f
            if col == 0
            {
                ssx = 0.0f
                ssw = l
                ddx = q.x
                ddw = l
            }
            elif col == 1
            {
                ssx = l
                ssw = q.sw - l - r
                ddx = q.x + l
                ddw = q.w - l - r
            }
            else
            {
                ssx = q.sw - r
                ssw = r
                ddx = q.x + q.w - r
                ddw = r
            }
            Int32 row = 0
            while row < 3
            {
                Float32 ssy = 0.0f
                Float32 ssh = 0.0f
                Float32 ddy = 0.0f
                Float32 ddh = 0.0f
                if row == 0
                {
                    ssy = 0.0f
                    ssh = t
                    ddy = q.y
                    ddh = t
                }
                elif row == 1
                {
                    ssy = t
                    ssh = q.sh - t - b
                    ddy = q.y + t
                    ddh = q.h - t - b
                }
                else
                {
                    ssy = q.sh - b
                    ssh = b
                    ddy = q.y + q.h - b
                    ddh = b
                }
                Float32 fu0 = ssx / q.sw
                Float32 fu1 = ( ssx + ssw ) / q.sw
                Float32 fv0 = ssy / q.sh
                Float32 fv1 = ( ssy + ssh ) / q.sh
                Float32 cu0 = q.u0 + ( q.u1 - q.u0 ) * fu0
                Float32 cu1 = q.u0 + ( q.u1 - q.u0 ) * fu1
                Float32 cvTop = q.vTop + ( q.vBot - q.vTop ) * fv0
                Float32 cvBot = q.vTop + ( q.vBot - q.vTop ) * fv1
                cursor = this.emitOne( ptr, cursor, ddx, ddy, ddw, ddh, cu0, cvTop, cu1, cvBot )
                row = row + 1
            }
            col = col + 1
        }
        ret cursor
    }

    # ── 点击命中测试（FairyGUI 逻辑 → 引擎 input）────────────
    # localX/localY = 渲染面（QLabel）局部像素，viewW/viewH = 渲染目标像素。
    # 顶点 NDC 的 aspect 缩放在这里与视口映射抵消，故局部像素 → 设计坐标
    # 只需按 design/view 比例换算；倒序遍历 quads（后画在上）取最上层命中。
    public string hitTestLocal( Int32 localX, Int32 localY, Int32 viewW, Int32 viewH )
    {
        if this.pkg == null || viewW <= 0 || viewH <= 0
        {
            ret ""
        }
        Float32 dwf = this.pkg.designW.toFloat32()
        Float32 dhf = this.pkg.designH.toFloat32()
        if dwf <= 0.0f || dhf <= 0.0f
        {
            ret ""
        }
        Float32 dx = localX.toFloat32() * dwf / viewW.toFloat32()
        Float32 dy = localY.toFloat32() * dhf / viewH.toFloat32()
        Int32 i = this.pkg.quads.length - 1
        while i >= 0
        {
            FairyQuad q = this.pkg.quads[i]
            if dx >= q.x && dx <= q.x + q.w && dy >= q.y && dy <= q.y + q.h
            {
                ret q.name
            }
            i = i - 1
        }
        ret ""
    }

    # 命中项名字前缀判定（菜单项统一命名 menu_N）
    public static Int32 menuIndex( string name, string prefix )
    {
        if name == null || prefix == null || name.length <= prefix.length
        {
            ret 0 - 1
        }
        string head = SystemStringRange( name, 0, prefix.length )
        if head != prefix
        {
            ret 0 - 1
        }
        string tail = SystemStringRange( name, prefix.length, name.length )
        ret FairySprite.parseI32( tail )
    }

    # 子串包含（UTF-8 字节级；ASCII 子串够用）
    public static bool nameHas( string s, string sub )
    {
        Int32 sl = s.length
        Int32 pl = sub.length
        if pl <= 0 || sl < pl
        {
            ret false
        }
        Int32 i = 0
        while i <= sl - pl
        {
            Int32 j = 0
            bool all = true
            while j < pl
            {
                Int32 a = SystemStringCharCodeAt( s, i + j )
                Int32 b = SystemStringCharCodeAt( sub, j )
                if a != b
                {
                    all = false
                    j = pl
                }
                else
                {
                    j = j + 1
                }
            }
            if all
            {
                ret true
            }
            i = i + 1
        }
        ret false
    }

    # ── 动态 UI 命中（2026-11-19 SnakeGame）────────────────────
    # 与 hitTestLocal 同换算，但只把「可交互 quad」当候选：名字含
    # "menu_" 或 "chk"（标签 t_* / 动态数字 dyn* / 隐藏 x<=-100 自动
    # 跳过），倒序取最上层。
    public string hitTopLocal( Int32 localX, Int32 localY, Int32 viewW, Int32 viewH )
    {
        if this.pkg == null
        {
            ret ""
        }
        if viewW <= 0
        {
            ret ""
        }
        if viewH <= 0
        {
            ret ""
        }
        Float32 dwf = this.pkg.designW.toFloat32()
        Float32 dhf = this.pkg.designH.toFloat32()
        if dwf <= 0.0f || dhf <= 0.0f
        {
            ret ""
        }
        Float32 dx = localX.toFloat32() * dwf / viewW.toFloat32()
        Float32 dy = localY.toFloat32() * dhf / viewH.toFloat32()
        Int32 i = this.pkg.quads.length - 1
        while i >= 0
        {
            FairyQuad q = this.pkg.quads[i]
            if q.x > 0.0f - 100.0f
            {
                bool cand = FairyUIRenderer.nameHas( q.name, "menu_" )
                if !cand
                {
                    cand = FairyUIRenderer.nameHas( q.name, "chk" )
                }
                if cand
                {
                    if dx >= q.x && dx <= q.x + q.w && dy >= q.y && dy <= q.y + q.h
                    {
                        ret q.name
                    }
                }
            }
            i = i - 1
        }
        ret ""
    }

    public bool draw( RenderSystem rs )
    {
        this.lastError = ""
        this.lastVerts = 0
        this.lastQuads = 0
        if rs == null || this.pkg == null || this.pkg.texture == null
        {
            this.lastError = "renderer not ready"
            ret false
        }
        Int32 n = this.pkg.quads.length
        if n <= 0
        {
            this.lastError = "no quads"
            ret false
        }
        Int32 total = 0
        Int32 i = 0
        while i < n
        {
            FairyQuad q = this.pkg.quads[i]
            total = total + this.vertCountOf( q )
            i = i + 1
        }
        if total <= 0 || total > 4096
        {
            this.lastError = "vertex budget exceeded: " + total.toString()
            ret false
        }
        Int64 ptr = Memory.alloc( total * 16 )
        if ptr == 0
        {
            this.lastError = "vertex memory alloc failed"
            ret false
        }
        # ── 按纹理分组（2026-11-19 FairyGUI v2）：pass1 计每组顶点数 →
        # 组区段连续布局（texIndex 序 = 提交序 = 绘制序，extras 盖图集）──
        Int32 groups = this.pkg.texGroupCount()
        if groups > 7
        {
            groups = 7
        }
        Array<Int32> gv = Array<Int32>( groups )
        Array<Int32> gstart = Array<Int32>( groups )
        Array<Int32> gcur = Array<Int32>( groups )
        Int32 gi = 0
        while gi < groups
        {
            gv[gi] = 0
            gstart[gi] = 0
            gcur[gi] = 0
            gi = gi + 1
        }
        i = 0
        while i < n
        {
            FairyQuad qg = this.pkg.quads[i]
            Int32 tg = qg.texIndex
            if tg < 0 || tg >= groups
            {
                tg = 0
            }
            gv[tg] = gv[tg] + this.vertCountOf( qg )
            i = i + 1
        }
        Int32 acc = 0
        gi = 0
        while gi < groups
        {
            gstart[gi] = acc
            gcur[gi] = acc
            acc = acc + gv[gi]
            gi = gi + 1
        }
        Float32 dwf = this.pkg.designW.toFloat32()
        Float32 dhf = this.pkg.designH.toFloat32()
        Float32 asp = this.aspect
        i = 0
        while i < n
        {
            FairyQuad fq = this.pkg.quads[i]
            Int32 tg2 = fq.texIndex
            if tg2 < 0 || tg2 >= groups
            {
                tg2 = 0
            }
            Int32 cells = 1
            if fq.use9 && fq.sw > 0.0f && fq.sh > 0.0f
            {
                cells = 9
            }
            Int32 ci = 0
            while ci < cells
            {
                Float32 dx = fq.x
                Float32 dy = fq.y
                Float32 dw = fq.w
                Float32 dh = fq.h
                Float32 u0 = fq.u0
                Float32 u1 = fq.u1
                Float32 vT = fq.vTop
                Float32 vB = fq.vBot
                if cells == 9
                {
                    Int32 col = ci % 3
                    Int32 row = ci / 3
                    Float32 ssx = 0.0f
                    Float32 ssw = 0.0f
                    if col == 0
                    {
                        ssx = 0.0f
                        ssw = fq.bl
                        dx = fq.x
                        dw = fq.bl
                    }
                    elif col == 1
                    {
                        ssx = fq.bl
                        ssw = fq.sw - fq.bl - fq.br
                        dx = fq.x + fq.bl
                        dw = fq.w - fq.bl - fq.br
                    }
                    else
                    {
                        ssx = fq.sw - fq.br
                        ssw = fq.br
                        dx = fq.x + fq.w - fq.br
                        dw = fq.br
                    }
                    Float32 ssy = 0.0f
                    Float32 ssh = 0.0f
                    if row == 0
                    {
                        ssy = 0.0f
                        ssh = fq.bt
                        dy = fq.y
                        dh = fq.bt
                    }
                    elif row == 1
                    {
                        ssy = fq.bt
                        ssh = fq.sh - fq.bt - fq.bb
                        dy = fq.y + fq.bt
                        dh = fq.h - fq.bt - fq.bb
                    }
                    else
                    {
                        ssy = fq.sh - fq.bb
                        ssh = fq.bb
                        dy = fq.y + fq.h - fq.bb
                        dh = fq.bb
                    }
                    Float32 fu0 = ssx / fq.sw
                    Float32 fu1 = ( ssx + ssw ) / fq.sw
                    Float32 fv0 = ssy / fq.sh
                    Float32 fv1 = ( ssy + ssh ) / fq.sh
                    u0 = fq.u0 + ( fq.u1 - fq.u0 ) * fu0
                    u1 = fq.u0 + ( fq.u1 - fq.u0 ) * fu1
                    vT = fq.vTop + ( fq.vBot - fq.vTop ) * fv0
                    vB = fq.vTop + ( fq.vBot - fq.vTop ) * fv1
                }
                Float32 x0 = ( dx / dwf * 2.0f - 1.0f ) / asp
                Float32 x1 = ( ( dx + dw ) / dwf * 2.0f - 1.0f ) / asp
                Float32 y0 = 1.0f - dy / dhf * 2.0f
                Float32 y1 = 1.0f - ( dy + dh ) / dhf * 2.0f
                Int32 off = gcur[tg2] * 16
                Memory.writeF32( ptr, off + 0, x0 )
                Memory.writeF32( ptr, off + 4, y0 )
                Memory.writeF32( ptr, off + 8, u0 )
                Memory.writeF32( ptr, off + 12, vT )
                Memory.writeF32( ptr, off + 16, x0 )
                Memory.writeF32( ptr, off + 20, y1 )
                Memory.writeF32( ptr, off + 24, u0 )
                Memory.writeF32( ptr, off + 28, vB )
                Memory.writeF32( ptr, off + 32, x1 )
                Memory.writeF32( ptr, off + 36, y1 )
                Memory.writeF32( ptr, off + 40, u1 )
                Memory.writeF32( ptr, off + 44, vB )
                Memory.writeF32( ptr, off + 48, x0 )
                Memory.writeF32( ptr, off + 52, y0 )
                Memory.writeF32( ptr, off + 56, u0 )
                Memory.writeF32( ptr, off + 60, vT )
                Memory.writeF32( ptr, off + 64, x1 )
                Memory.writeF32( ptr, off + 68, y1 )
                Memory.writeF32( ptr, off + 72, u1 )
                Memory.writeF32( ptr, off + 76, vB )
                Memory.writeF32( ptr, off + 80, x1 )
                Memory.writeF32( ptr, off + 84, y0 )
                Memory.writeF32( ptr, off + 88, u1 )
                Memory.writeF32( ptr, off + 92, vT )
                gcur[tg2] = gcur[tg2] + 6
                ci = ci + 1
            }
            i = i + 1
        }
        bool ok = true
        gi = 0
        while gi < groups
        {
            if gv[gi] > 0
            {
                Int64 gp = ptr + gstart[gi] * 16
                Int64 texh = this.pkg.texHandleAt( gi )
                if texh != 0
                {
                    bool gok = rs.submitUiMeshTex( 7 + gi, gp, gv[gi], texh,
                        1.0f, 1.0f, 1.0f, 1.0f, 4000 )
                    if !gok
                    {
                        ok = false
                        this.lastError = "submit group " + gi.toString() + " failed: " + rs.lastError
                    }
                }
            }
            gi = gi + 1
        }
        Memory.free( ptr )
        this.lastVerts = total
        this.lastQuads = n
        if !ok
        {
            this.lastError = "submitUiMeshTex failed"
        }
        ret ok
    }
}
