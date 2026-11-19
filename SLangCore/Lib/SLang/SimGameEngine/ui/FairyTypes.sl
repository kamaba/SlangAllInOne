import Core;
import Std;
import Math;
import SLangRender;
# ============================================================================
# FairyGUI 数据层（图集 sprite / quad 数据结构 + XML 属性解析助手）
# ----------------------------------------------------------------------------
# 数据来自 FairyGUI 编辑器导出的 XML 包；渲染走顶点 UV 承载图集裁剪与九宫格的
# 自定义网格（pos2+uv2）经 RenderSystem.submitUiMesh 送 2D 管线（doc/18 之外
# 见 ui/ 目录三文件分工：FairyTypes / FairyPackage / FairyUIRenderer）。
# 文本首期用图集白块占位；tint 首期不下发（顶点格式无 color 字段）。
# ============================================================================
public class FairySprite
{
    public string name = ""
    public Float32 x = 0.0f
    public Float32 y = 0.0f
    public Float32 w = 0.0f
    public Float32 h = 0.0f
    public Float32 u0 = 0.0f
    public Float32 u1 = 1.0f
    public Float32 vTop = 1.0f
    public Float32 vBot = 0.0f
    public Float32 bl = 0.0f
    public Float32 bt = 0.0f
    public Float32 br = 0.0f
    public Float32 bb = 0.0f

    # XML 属性节点名 "l,t,r,b" 形式的九宫格边距（源图像素）
    public void setBorders( string s )
    {
        Int32 n = s.length
        if n <= 0
        {
            ret
        }
        Int32 comma1 = 0 - 1
        Int32 comma2 = 0 - 1
        Int32 comma3 = 0 - 1
        Int32 i = 0
        while i < n
        {
            Int32 c = SystemStringCharCodeAt( s, i )
            if c == 44
            {
                if comma1 < 0
                {
                    comma1 = i
                }
                elif comma2 < 0
                {
                    comma2 = i
                }
                elif comma3 < 0
                {
                    comma3 = i
                }
            }
            i = i + 1
        }
        if comma1 < 0 || comma2 < 0 || comma3 < 0
        {
            ret
        }
        string a = SystemStringRange( s, 0, comma1 )
        string b = SystemStringRange( s, comma1 + 1, comma2 )
        string c3 = SystemStringRange( s, comma2 + 1, comma3 )
        string d = SystemStringRange( s, comma3 + 1, n )
        this.bl = FairySprite.parseF32( a )
        this.bt = FairySprite.parseF32( b )
        this.br = FairySprite.parseF32( c3 )
        this.bb = FairySprite.parseF32( d )
    }

    # 自包含十进制解析（不依赖系统转换调用；XML 属性都是简单数值）
    public static Float32 parseF32( string s )
    {
        if s == null || s.length == 0
        {
            ret 0.0f
        }
        Int32 sign = 1
        Int32 i = 0
        Int32 c = SystemStringCharCodeAt( s, 0 )
        if c == 45
        {
            sign = 0 - 1
            i = 1
        }
        Float32 whole = 0.0f
        Float32 frac = 0.0f
        Float32 scale = 0.1f
        bool dot = false
        while i < s.length
        {
            c = SystemStringCharCodeAt( s, i )
            i = i + 1
            if c == 46
            {
                dot = true
                continue
            }
            if c < 48 || c > 57
            {
                continue
            }
            Int32 d = c - 48
            if dot
            {
                frac = frac + d.toFloat32() * scale
                scale = scale * 0.1f
            }
            else
            {
                whole = whole * 10.0f + d.toFloat32()
            }
        }
        Float32 v = whole + frac
        if sign < 0
        {
            v = 0.0f - v
        }
        ret v
    }

    public static Int32 parseI32( string s )
    {
        if s == null || s.length == 0
        {
            ret 0
        }
        Int32 sign = 1
        Int32 i = 0
        Int32 c = SystemStringCharCodeAt( s, 0 )
        if c == 45
        {
            sign = 0 - 1
            i = 1
        }
        Int32 v = 0
        while i < s.length
        {
            c = SystemStringCharCodeAt( s, i )
            i = i + 1
            if c < 48 || c > 57
            {
                continue
            }
            v = v * 10 + c - 48
        }
        ret v * sign
    }

    # XML 取值助手（属性节点在 BaseXml 里以 "@名字" 挂在元素下）
    public static string attr( TreeNode<string> node, string name )
    {
        if node == null || name == null || name.length == 0
        {
            ret ""
        }
        string an = "@" + name
        TreeNode<string> a = node.childByName( an )
        if a == null || a._value == null
        {
            ret ""
        }
        ret a._value
    }

    public static Float32 attrF( TreeNode<string> node, string name )
    {
        string s = FairySprite.attr( node, name )
        if s.length == 0
        {
            ret 0.0f
        }
        ret FairySprite.parseF32( s )
    }

    public static Int32 attrI( TreeNode<string> node, string name )
    {
        string s = FairySprite.attr( node, name )
        if s.length == 0
        {
            ret 0
        }
        ret FairySprite.parseI32( s )
    }
}

public class FairyQuad
{
    public string name = ""
    public Int32 kind = 0
    public Float32 x = 0.0f
    public Float32 y = 0.0f
    public Float32 w = 0.0f
    public Float32 h = 0.0f
    public Float32 u0 = 0.0f
    public Float32 u1 = 1.0f
    public Float32 vTop = 1.0f
    public Float32 vBot = 0.0f
    public Float32 sw = 0.0f
    public Float32 sh = 0.0f
    public Float32 bl = 0.0f
    public Float32 bt = 0.0f
    public Float32 br = 0.0f
    public Float32 bb = 0.0f
    public bool use9 = false
    # 纹理组下标（2026-11-19 多纹理基建）：0 = 包图集，≥1 = loader/graph/
    # go3d 元素的独立纹理（包纹理表 extraTexs[i-1]）。渲染按组分网格分对象。
    public Int32 texIndex = 0
}
