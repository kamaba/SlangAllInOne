import Std;
import Math;
# 材质：着色器 + 基础颜色 + 主纹理 + 常用 PBR 参数。
public class Material
{
    public string name = ""
    public Color color = Color.white()
    public Color emission = Color.black()
    public Texture mainTexture = null
    public Shader shader = null

    public Float32 metallic = 0.0f
    public Float32 smoothness = 0.5f

    # 渲染状态
    public bool enableDepthTest = true
    public bool enableDepthWrite = true
    public bool isTransparent = false

    # ── P5：变体关键字位掩码（程序枚举 + int 关键字，C 侧 switch 消费）──
    # Unity shader keyword 思想：位 = 关键字开关，Material.resolveProgram
    # 按位掩码路由到 C 侧程序槽（ShaderProgramMap 同源表）。
    public static Int32 KEY_TEXTURED = 1   # bit0：带主纹理
    public static Int32 KEY_LIT = 2        # bit1：参与光照（Phong 通路）
    public static Int32 KEY_SPECULAR = 4   # bit2：高光（PHONG_TEX 通路预留）
    public Int32 keywords = 0

    # ── 构造 ─────────────────────────────────────────────
    public void _init_()
    {
        this.name = "Material"
        this.color = Color.white()
        this.emission = Color.black()
        this.mainTexture = null
        this.shader = null
        this.metallic = 0.0f
        this.smoothness = 0.5f
        this.enableDepthTest = true
        this.enableDepthWrite = true
        this.isTransparent = false
        this.keywords = 0
    }

    public void _init_( Shader _shader )
    {
        this._init_()
        this.shader = _shader
    }

    public void _init_( Shader _shader, Color _color )
    {
        this._init_()
        this.shader = _shader
        this.color = _color.clone()
    }

    # ── 设置 ─────────────────────────────────────────────
    public void setColor( Color c )
    {
        this.color = c.clone()
    }

    public Color getColor()
    {
        ret this.color.clone()
    }

    public void setTexture( Texture tex )
    {
        this.mainTexture = tex
    }

    public Texture getTexture()
    {
        ret this.mainTexture
    }

    public void setShader( Shader s )
    {
        this.shader = s
    }

    public Shader getShader()
    {
        ret this.shader
    }

    # 各参数统一限制到 [0,1]
    public void clampParameters()
    {
        this.metallic = Mathf.clamp( this.metallic, 0.0f, 1.0f )
        this.smoothness = Mathf.clamp( this.smoothness, 0.0f, 1.0f )
        this.color = this.color.clamp01()
        this.emission = this.emission.clamp01()
    }

    # 透明材质默认关闭深度写入
    public void setTransparent( bool transparent )
    {
        this.isTransparent = transparent
        if transparent
        {
            this.enableDepthWrite = false
        }
        else
        {
            this.enableDepthWrite = true
        }
    }

    # ── P5：关键字位掩码 API ──────────────────────────────
    # isKeywordEnabled(bit) —— 关键字位是否开（位 = 1/2/4）
    public bool isKeywordEnabled( Int32 bit )
    {
        if bit <= 0
        {
            ret false
        }
        ret ( this.keywords / bit ) % 2 == 1
    }

    # enableKeyword(bit) —— 打开关键字位（已开幂等）
    public void enableKeyword( Int32 bit )
    {
        if bit <= 0
        {
            ret
        }
        if this.isKeywordEnabled( bit ) == false
        {
            this.keywords = this.keywords + bit
        }
    }

    # disableKeyword(bit) —— 关闭关键字位（已关幂等）
    public void disableKeyword( Int32 bit )
    {
        if bit <= 0
        {
            ret
        }
        if this.isKeywordEnabled( bit )
        {
            this.keywords = this.keywords - bit
        }
    }

    # resolveProgram() —— 位掩码 -> C 侧程序槽（变体路由，AIPrompt P5：
    # 程序枚举 + Material 关键字位掩码，C 侧 draw_item(prog) switch 消费）：
    #   KEY_LIT x KEY_TEXTURED -> PHONG_TEX / PHONG_FLAT / PTEX / PFLAT
    public Int32 resolveProgram()
    {
        bool lit = this.isKeywordEnabled( Material.KEY_LIT )
        bool tex = this.isKeywordEnabled( Material.KEY_TEXTURED )
        if lit
        {
            if tex
            {
                ret SLang.RenderPipeline.PROG_PHONG_TEX
            }
            ret SLang.RenderPipeline.PROG_PHONG_FLAT
        }
        if tex
        {
            ret SLang.RenderPipeline.PROG_PTEX
        }
        ret SLang.RenderPipeline.PROG_PFLAT
    }

    public Material clone()
    {
        Material m = Material()
        m.name = this.name
        m.color = this.color.clone()
        m.emission = this.emission.clone()
        m.mainTexture = this.mainTexture
        m.shader = this.shader
        m.metallic = this.metallic
        m.smoothness = this.smoothness
        m.enableDepthTest = this.enableDepthTest
        m.enableDepthWrite = this.enableDepthWrite
        m.isTransparent = this.isTransparent
        m.keywords = this.keywords
        ret m
    }

    override string toString()
    {
        ret String.toFormat( "Material(name={0}, color={1})", this.name, this.color.toString() )
    }
}
