import SLangRender;
import SLangAudio;
import Math;
import Std;

# 光照 / 阴影 / 固化 shader phase 分组：
#   runLightScene   Phase L  光照（直射 + 聚光 + 无光回归）
#   runShadowMap    Phase SHADOW2  N2a 真实阴影（shadow map + PCF 平行光）
#   runCsmShadow    Phase CSM  N2b 4 级联（v 分段 + 图集 1x4）
#   runGenShaders   Phase G  固化 shader（gen 效果 material 0..4 全路由）正面断言
public class RenderTestPhasesB
{

    # ── Phase G：固化 shader（gen 效果，material 0..4 全路由）端到端 ──
    # 「通用固化编译」产物正面断言（GL/D3D11/GLES 用真实 gen 源码，
    # 全部 5 效果 × flat/tex 变体；VK 降级 builtin 槽）。同一 quad 切
    # material 对比法：
    #   断言 1：uSpec.x 默认 0 时 gen BlinnPhong-flat 与 gen Lambert-flat
    #     公式逐字一致 -> 两帧中心像素逐通道差 <= 2（末位浮点容差）；
    #   断言 2a：setSpecular(2,8)+直射光 -> Blinn 高光真实执行（手算
    #     NdotH~0.916、pow8~0.50 -> 中心像素大幅增亮）；
    #   断言 2b：gen Phong 经典高光 R=reflect(-L,N)、pow(R·V,8)*2 ->
    #     手算 (63,126,251)±3（比 Blinn 暗，两族公式可区分）；
    #   断言 3：gen NormalMap-flat —— uSpec.z（凹凸强度）无 API 写入
    #     恒 0 -> 扰动/边缘光全零，退化为 BlinnPhong 基座 -> == 基准 1；
    #   断言 4：gen Toon-flat setSpecular(3,0.5)（3 阶梯 + 阈值夹取 1
    #     压制硬边高光）-> 手算阶梯 tint (48,97,207)±3 且暗于 Lambert；
    #   断言 5：gen BlinnPhong-tex == gen Lambert-tex（tex 变体）；
    #   断言 6：gen NormalMap-tex == 基准 5（tex 变体槽位）；
    #   断言 7：gen Toon-tex 阶梯 tint 全通道严格暗于 Lambert-tex。
    #   VK：全部效果降级 PFLAT/PTEX（uSpec 不消费）-> 一致性断言改
    #     比对应基准，specular/阶梯手算断言跳过。
    public static bool runGenShaders()
    {
        Console.println( "-- Phase G: frozen shaders (gen effects, material>=2) --" )
        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 128, 128 )
        if pipe == null
        {
            Console.println( "[gen] FAIL: pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[gen] FAIL: setClearColor" )
            ret false
        }
        # 低环境光 + 直射光（漫反射 + Blinn 高光两条路径都活跃）
        if pipe.setAmbient( 0.25f ) == false
        {
            Console.println( "[gen] FAIL: setAmbient" )
            ret false
        }
        Light sun = Light.directional( Color.white(), 0.9f )
        sun.dirX = 1.0f
        sun.dirY = 0.0f
        if sun.applyTo( pipe, 0 ) == false
        {
            Console.println( "[gen] FAIL: apply directional light" )
            ret false
        }
        # 居中 quad：rot=0 法线 (1,0) 正对直射光 -> 全亮基准
        SLang.RenderObject quad = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if quad == null
        {
            Console.println( "[gen] FAIL: addObject - " + SLang.Render.errorString() )
            ret false
        }
        quad.setPosition( 0.0f, 0.0f, 0.0f )
        quad.setScale( 0.8f, 0.8f )
        quad.setColor( 0.2f, 0.4f, 0.8f, 1.0f )
        Int64 px = Memory.alloc( 128 * 128 * 4 )
        if px == 0
        {
            Console.println( "[gen] FAIL: alloc pixels" )
            ret false
        }

        # 断言 1：material 2（gen BlinnPhong flat，uSpec.x 默认 0 无高光）
        #   vs material 0（gen Lambert flat，uSpec.x=0 时同漫反射核心）
        #   —— 两帧中心像素逐通道差 <= 2
        if quad.setMaterial( 2 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(2)" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen flat - " + SLang.Render.errorString() )
            ret false
        }
        Int32 g1r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 g1g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 g1b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen BlinnPhong-flat (uSpec=0)  : (" + g1r + "," + g1g + "," + g1b + ")" )
        if quad.setMaterial( 0 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(0)" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render builtin flat - " + SLang.Render.errorString() )
            ret false
        }
        Int32 b1r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 b1g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 b1b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Lambert-flat (uSpec=0) : (" + b1r + "," + b1g + "," + b1b + ")" )
        Int32 dr = g1r - b1r
        if dr < 0
        {
            dr = -dr
        }
        Int32 dg = g1g - b1g
        if dg < 0
        {
            dg = -dg
        }
        Int32 db = g1b - b1b
        if db < 0
        {
            db = -db
        }
        if dr > 2 || dg > 2 || db > 2
        {
            Console.println( "[gen] FAIL: gen flat != Lambert flat (diff " + dr + "," + dg + "," + db + ")" )
            ret false
        }

        # 断言 2a：高光活跃（非平凡证明）—— setSpecular(2,8) 后像素必变
        bool isVk = SLang.Render.currentBackend() == "vk"
        if quad.setMaterial( 2 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(2) for specular" )
            ret false
        }
        if quad.setSpecular( 2.0f, 8.0f ) == false
        {
            Console.println( "[gen] FAIL: setSpecular" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen specular - " + SLang.Render.errorString() )
            ret false
        }
        Int32 s1r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 s1g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 s1b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen BlinnPhong specular(2,8): (" + s1r + "," + s1g + "," + s1b + ")" )
        Int32 sr = s1r - g1r
        if sr < 0
        {
            sr = -sr
        }
        Int32 sg = s1g - g1g
        if sg < 0
        {
            sg = -sg
        }
        Int32 sb = s1b - g1b
        if sb < 0
        {
            sb = -sb
        }
        if isVk
        {
            Console.println( "[gen] vk fallback slot: gen effects degrade to builtin PFLAT/PTEX (uSpec not consumed) - specular assertion skipped" )
        }
        else
        {
            # 手算：NdotH~0.916、pow8~0.50 -> 高光 ~0.9 -> 中心像素
            # 大幅增亮（R 差 ~196）。全部 <3 说明 gen 高光没执行。
            if sr < 3 && sg < 3 && sb < 3
            {
                Console.println( "[gen] FAIL: specular did not change pixels (diff " + sr + "," + sg + "," + sb + ")" )
                ret false
            }
        }

        # 断言 2b：gen Phong（material 1）经典高光 —— R=reflect(-L,N)、
        #   pow(R·V,8)*2 手算 light=1.15+0.081 -> (63,126,251)±3；
        #   与 Blinn（104,208,255）可区分（半角向量更亮）。VK 降级
        #   PFLAT 不消费 uSpec -> 应等于基准 1。
        if quad.setMaterial( 1 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(1) phong" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen phong - " + SLang.Render.errorString() )
            ret false
        }
        Int32 p1r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 p1g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 p1b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Phong specular(2,8)    : (" + p1r + "," + p1g + "," + p1b + ")" )
        if isVk
        {
            Int32 vr = p1r - g1r
            if vr < 0
            {
                vr = -vr
            }
            Int32 vg = p1g - g1g
            if vg < 0
            {
                vg = -vg
            }
            Int32 vb = p1b - g1b
            if vb < 0
            {
                vb = -vb
            }
            if vr > 2 || vg > 2 || vb > 2
            {
                Console.println( "[gen] FAIL: vk phong != degraded flat (diff " + vr + "," + vg + "," + vb + ")" )
                ret false
            }
        }
        else
        {
            Int32 pr = p1r - 63
            if pr < 0
            {
                pr = -pr
            }
            Int32 pg = p1g - 126
            if pg < 0
            {
                pg = -pg
            }
            Int32 pb = p1b - 251
            if pb < 0
            {
                pb = -pb
            }
            if pr > 3 || pg > 3 || pb > 3
            {
                Console.println( "[gen] FAIL: gen phong specular off (got " + p1r + "," + p1g + "," + p1b + " expect ~63,126,251)" )
                ret false
            }
        }

        # 断言 3：gen NormalMap-flat（material 3）—— uSpec.z（凹凸强度）
        #   无 API 写入恒 0 -> 扰动/边缘光全零，公式退化为 BlinnPhong
        #   基座 -> 与基准 1 逐字节一致（VK 同降级一致）。先重置高光。
        if quad.setSpecular( 0.0f, 0.0f ) == false
        {
            Console.println( "[gen] FAIL: reset specular nm-flat" )
            ret false
        }
        if quad.setMaterial( 3 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(3) normalmap" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen normalmap - " + SLang.Render.errorString() )
            ret false
        }
        Int32 n1r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 n1g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 n1b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen NormalMap-flat (bump=0) : (" + n1r + "," + n1g + "," + n1b + ")" )
        Int32 nr = n1r - g1r
        if nr < 0
        {
            nr = -nr
        }
        Int32 ng = n1g - g1g
        if ng < 0
        {
            ng = -ng
        }
        Int32 nb = n1b - g1b
        if nb < 0
        {
            nb = -nb
        }
        if nr > 2 || ng > 2 || nb > 2
        {
            Console.println( "[gen] FAIL: gen normalmap flat != blinnphong base (diff " + nr + "," + ng + "," + nb + ")" )
            ret false
        }

        # 断言 4：gen Toon-flat（material 4，setSpecular(3,0.5) = 3 阶梯
        #   + 高光阈值夹取 1 压制硬边高光）—— 手算阶梯 tint
        #   (0.775,0.775,0.85) -> (48,97,207)±3 且至少一通道严格暗于
        #   Lambert 基准；VK 降级 PFLAT -> == 基准 1。
        if quad.setMaterial( 4 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(4) toon" )
            ret false
        }
        if quad.setSpecular( 3.0f, 0.5f ) == false
        {
            Console.println( "[gen] FAIL: setSpecular toon" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen toon - " + SLang.Render.errorString() )
            ret false
        }
        Int32 t1r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 t1g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 t1b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Toon-flat (steps=3)     : (" + t1r + "," + t1g + "," + t1b + ")" )
        if isVk
        {
            Int32 kr = t1r - g1r
            if kr < 0
            {
                kr = -kr
            }
            Int32 kg = t1g - g1g
            if kg < 0
            {
                kg = -kg
            }
            Int32 kb = t1b - g1b
            if kb < 0
            {
                kb = -kb
            }
            if kr > 2 || kg > 2 || kb > 2
            {
                Console.println( "[gen] FAIL: vk toon != degraded flat (diff " + kr + "," + kg + "," + kb + ")" )
                ret false
            }
        }
        else
        {
            Int32 qr = t1r - 48
            if qr < 0
            {
                qr = -qr
            }
            Int32 qg = t1g - 97
            if qg < 0
            {
                qg = -qg
            }
            Int32 qb = t1b - 207
            if qb < 0
            {
                qb = -qb
            }
            if qr > 3 || qg > 3 || qb > 3
            {
                Console.println( "[gen] FAIL: gen toon steps off (got " + t1r + "," + t1g + "," + t1b + " expect ~48,97,207)" )
                ret false
            }
            if t1r >= g1r && t1g >= g1g && t1b >= g1b
            {
                Console.println( "[gen] FAIL: gen toon == lambert (no band tint)" )
                ret false
            }
        }

        # 断言 5：gen BlinnPhong-tex == gen Lambert-tex（tex 变体，先重置高光）
        if quad.setSpecular( 0.0f, 0.0f ) == false
        {
            Console.println( "[gen] FAIL: reset specular" )
            ret false
        }
        Int64 texPtr = RenderTestHelpers.makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[gen] FAIL: gradient texture" )
            ret false
        }
        SLang.RenderTexture tex = SLang.RenderTexture.createRgba( texPtr, 64, 64 )
        if tex == null
        {
            Console.println( "[gen] FAIL: createRgba - " + SLang.Render.errorString() )
            ret false
        }
        if quad.setTexture( tex ) == false
        {
            Console.println( "[gen] FAIL: setTexture" )
            ret false
        }
        # material 2 + texture -> gen BlinnPhong TEX 变体
        if quad.setMaterial( 2 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(2) tex" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen tex - " + SLang.Render.errorString() )
            ret false
        }
        Int32 g2r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 g2g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 g2b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen BlinnPhong-tex          : (" + g2r + "," + g2g + "," + g2b + ")" )
        if quad.setMaterial( 0 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(0) tex" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render builtin tex - " + SLang.Render.errorString() )
            ret false
        }
        Int32 b2r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 b2g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 b2b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Lambert-tex            : (" + b2r + "," + b2g + "," + b2b + ")" )
        Int32 xtr = g2r - b2r
        if xtr < 0
        {
            xtr = -xtr
        }
        Int32 xtg = g2g - b2g
        if xtg < 0
        {
            xtg = -xtg
        }
        Int32 xtb = g2b - b2b
        if xtb < 0
        {
            xtb = -xtb
        }
        if xtr > 2 || xtg > 2 || xtb > 2
        {
            Console.println( "[gen] FAIL: gen tex != Lambert tex (diff " + xtr + "," + xtg + "," + xtb + ")" )
            ret false
        }

        # 断言 6：gen NormalMap-tex（material 3 + 纹理）—— 同断言 3
        #   （tex 变体槽位）：bump=0 -> == 基准 5（gen Lambert-tex）。
        if quad.setMaterial( 3 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(3) nm-tex" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen nm-tex - " + SLang.Render.errorString() )
            ret false
        }
        Int32 n2r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 n2g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 n2b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen NormalMap-tex (bump=0)  : (" + n2r + "," + n2g + "," + n2b + ")" )
        Int32 mr = n2r - g2r
        if mr < 0
        {
            mr = -mr
        }
        Int32 mg = n2g - g2g
        if mg < 0
        {
            mg = -mg
        }
        Int32 mb = n2b - g2b
        if mb < 0
        {
            mb = -mb
        }
        if mr > 2 || mg > 2 || mb > 2
        {
            Console.println( "[gen] FAIL: gen nm-tex != lambert-tex (diff " + mr + "," + mg + "," + mb + ")" )
            ret false
        }

        # 断言 7：gen Toon-tex（material 4 + 纹理 + setSpecular(3,0.5)）
        #   —— 阶梯 tint 光照 (0.9475,0.9475,1.015) < Lambert 1.15
        #   -> 全通道严格暗于基准 5；VK 降级 PTEX -> == 基准 5。
        if quad.setMaterial( 4 ) == false
        {
            Console.println( "[gen] FAIL: setMaterial(4) toon-tex" )
            ret false
        }
        if quad.setSpecular( 3.0f, 0.5f ) == false
        {
            Console.println( "[gen] FAIL: setSpecular toon-tex" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[gen] FAIL: render gen toon-tex - " + SLang.Render.errorString() )
            ret false
        }
        Int32 t2r = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 0 )
        Int32 t2g = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 1 )
        Int32 t2b = RenderTestHelpers.sampleChannel( px, 128, 64, 64, 2 )
        Console.println( "[gen] gen Toon-tex (steps=3)      : (" + t2r + "," + t2g + "," + t2b + ")" )
        if isVk
        {
            Int32 wr = t2r - g2r
            if wr < 0
            {
                wr = -wr
            }
            Int32 wg = t2g - g2g
            if wg < 0
            {
                wg = -wg
            }
            Int32 wb = t2b - g2b
            if wb < 0
            {
                wb = -wb
            }
            if wr > 2 || wg > 2 || wb > 2
            {
                Console.println( "[gen] FAIL: vk toon-tex != degraded tex (diff " + wr + "," + wg + "," + wb + ")" )
                ret false
            }
        }
        else
        {
            if t2r >= g2r || t2g >= g2g || t2b >= g2b
            {
                Console.println( "[gen] FAIL: gen toon-tex not darker than lambert-tex (" + t2r + "," + t2g + "," + t2b + " vs " + g2r + "," + g2g + "," + g2b + ")" )
                ret false
            }
        }

        Console.println( "[gen] Phase G: PASS (5 frozen effects live: Lambert/Phong/BlinnPhong/NormalMap/Toon x flat+tex, backend " + SLang.Render.currentBackend() + ")" )
        ret true
    }

    # 采样像素通道：pixels 块内 (x,y) 像素的 c 通道（0=R 1=G 2=B 3=A）


    # ── Phase L：光照（一个直射光 + 一个 spot 光 + 无光回归）────────
    # 场景（1280x720，ortho [-1,1]²，ambient 0.25）：
    #   直射光 slot 0：方向 (1,0)、白色、强度 0.9 —— 顶部两个白 quad
    #     （rot 0 朝光 vs rot π 背光）验证 ndl 按物体朝向着色；
    #   聚光 slot 1：位置 (0,0.35)、光轴 (0,-1)、锥半角 30°、范围 1.3、
    #     暖色 (1.0,0.85,0.55)、强度 1.2 —— 底部大背光 quad（rot π，
    #     ndl=0 只剩环境光）上验证锥内/锥外亮度差（锥内 + 距离衰减）。
    # v3.4 增补：
    #   阴影 —— 白 box(0.45,-0.2) castShadow（不透明 z=0、地板接收面
    #     z=-0.1）：直射光沿 -x 投出阴影 quad（偏移 0.136、放大 1.15、
    #     黑 0.35、深度夹层 -0.01），S_in(阴影内地板) 显著暗于
    #     S_out(锥内普通地板)；无光回归帧无光源 -> 阴影不生成 ->
    #     纯白基线不受影响；
    #   灯光摇晃 —— 帧 2 摆动聚光（posX=0.08*sin(2.1)、强度
    #     1.2+0.35*sin(3.7)）-> P1 亮度随灯动变化（Δ≥4）；
    #   Phong —— 独立 256 管线子场景：同光照下 Lambert quad vs Phong
    #     quad（spec 2.0/4.0）中心亮度差 = 伪 3D 高光贡献（Δ≥35）。
    # 末帧回归：clearLight(0/1) + setAmbient(1.0) -> 采样点全部回到
    # 纯白（无光照默认态与旧版逐字节一致）。
    public static bool runLightScene()
    {
        Console.println( "-- Phase L: lighting + sway + Phong + shadow (1 directional + 1 spot, ambient 0.25) --" )

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 1280, 720 )
        if pipe == null
        {
            Console.println( "[light] FAIL: create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[light] FAIL: setCamera" )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[light] FAIL: setClearColor" )
            ret false
        }

        # 光照：环境光 + 直射光 + 聚光（Light.applyTo 写管线槽）
        if pipe.setAmbient( 0.25f ) == false
        {
            Console.println( "[light] FAIL: setAmbient" )
            ret false
        }
        Light sun = Light.directional( Color.white(), 0.9f )
        if sun == null
        {
            Console.println( "[light] FAIL: Light.directional" )
            ret false
        }
        sun.dirX = 1.0f
        sun.dirY = 0.0f
        if sun.applyTo( pipe, 0 ) == false
        {
            Console.println( "[light] FAIL: directional applyTo - " + SLang.Render.errorString() )
            ret false
        }
        Light lamp = Light.spot( Color( 1.0f, 0.85f, 0.55f, 1.0f ), 1.2f, 1.3f, 30.0f )
        if lamp == null
        {
            Console.println( "[light] FAIL: Light.spot" )
            ret false
        }
        lamp.posX = 0.0f
        lamp.posY = 0.35f
        lamp.dirX = 0.0f
        lamp.dirY = -1.0f
        if lamp.applyTo( pipe, 1 ) == false
        {
            Console.println( "[light] FAIL: spot applyTo - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.lightCount() != 2
        {
            Console.println( "[light] FAIL: lightCount should be 2" )
            ret false
        }

        # 顶部两个白 quad：rot 0（法线 (1,0)，朝直射光 -> 全亮）
        # vs rot π（法线 (-1,0)，背光 -> 仅环境光）
        SLang.RenderObject quadA = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        SLang.RenderObject quadB = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if quadA == null || quadB == null
        {
            Console.println( "[light] FAIL: add quads" )
            ret false
        }
        quadA.setPosition( -0.55f, 0.6f, 0.0f )
        quadA.setScale( 0.42f, 0.42f )
        quadA.setRotationZ( 0.0f )
        quadA.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        quadB.setPosition( 0.55f, 0.6f, 0.0f )
        quadB.setScale( 0.42f, 0.42f )
        quadB.setRotationZ( 3.14159f )
        quadB.setColor( 1.0f, 1.0f, 1.0f, 1.0f )

        # 底部大背光 quad（rot π -> ndl=0，只剩环境光 + 聚光贡献）。
        # 不透明队列（2000）+ z=-0.1（比 box 远）—— 阴影接收面须先于
        # 阴影绘制且深度比阴影远；z<=0 保证 D3D11 NDC [0,1] 有效域
        SLang.RenderObject floor = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if floor == null
        {
            Console.println( "[light] FAIL: add floor" )
            ret false
        }
        floor.setPosition( 0.0f, -0.45f, -0.1f )
        floor.setScale( 1.9f, 1.0f )
        floor.setRotationZ( 3.14159f )
        floor.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        floor.setQueue( 2000 )

        # v3.4 阴影投射 box：朝光白方块（不透明、z=0 比地板近），
        # 直射光 (1,0) 沿 -x 投出阴影 quad（阴影中心 (0.314,-0.2)、尺寸
        # 0.345、z=-0.01 深度夹层：地板 -0.1 < 阴影 -0.01 < box 0），
        # 阴影落在地板上，与 box 重叠区被本体深度剔除
        SLang.RenderObject box = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if box == null
        {
            Console.println( "[light] FAIL: add shadow box" )
            ret false
        }
        box.setPosition( 0.45f, -0.2f, 0.0f )
        box.setScale( 0.3f, 0.3f )
        box.setRotationZ( 0.0f )
        box.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        box.setQueue( 2000 )
        if box.setShadow( 1 ) == false
        {
            Console.println( "[light] FAIL: box.setShadow - " + SLang.Render.errorString() )
            ret false
        }

        Int64 px = Memory.alloc( 1280 * 720 * 4 )
        if px == 0
        {
            Console.println( "[light] FAIL: pixel alloc" )
            ret false
        }

        # ── 帧 1：光照开 —— 采样六点（世界坐标 -> 1280x720 像素：
        #    x=(wx+1)/2*1280, y=(1-(wy+1)/2)*720）────────────────────
        #    A(288,144)=quadA 中心 B(992,144)=quadB 中心
        #    P1(640,492)=锥内地板 P2(1200,492)=锥外地板
        #    S_in(768,432)=box 阴影内地板 S_out(512,432)=锥内无阴影地板
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[light] FAIL: renderFrame lit - " + SLang.Render.errorString() )
            ret false
        }
        Int32 aR = RenderTestHelpers.sampleChannel( px, 1280, 288, 144, 0 )
        Int32 bR = RenderTestHelpers.sampleChannel( px, 1280, 992, 144, 0 )
        Int32 p1R = RenderTestHelpers.sampleChannel( px, 1280, 640, 492, 0 )
        Int32 p2R = RenderTestHelpers.sampleChannel( px, 1280, 1200, 492, 0 )
        Int32 sInR = RenderTestHelpers.sampleChannel( px, 1280, 768, 432, 0 )
        Int32 sOutR = RenderTestHelpers.sampleChannel( px, 1280, 512, 432, 0 )
        Console.println( "[light] lit   A=" + aR.toString() + " B=" + bR.toString() + " P1=" + p1R.toString() + " P2=" + p2R.toString() + " S_in=" + sInR.toString() + " S_out=" + sOutR.toString() )
        # 直射光：A 朝光全亮（0.25+0.9 -> 255），B 背光仅环境光（~64）
        if aR < 245
        {
            Console.println( "[light] FAIL: facing quad should be fully lit" )
            ret false
        }
        if bR < 45 || bR > 90
        {
            Console.println( "[light] FAIL: back-facing quad should be ambient-only" )
            ret false
        }
        if aR - bR < 120
        {
            Console.println( "[light] FAIL: directional ndl difference missing" )
            ret false
        }
        # 聚光：P1 锥内（环境光 + 衰减贡献 ~125），P2 锥外仅环境光（~64）
        if p1R < 100 || p1R > 165
        {
            Console.println( "[light] FAIL: in-cone pixel brightness out of range" )
            ret false
        }
        if p2R < 45 || p2R > 90
        {
            Console.println( "[light] FAIL: out-of-cone pixel should be ambient-only" )
            ret false
        }
        if p1R - p2R < 30
        {
            Console.println( "[light] FAIL: spot cone difference missing" )
            ret false
        }
        # 阴影：S_in = 阴影内地板（地板亮度 * 0.65），S_out = 锥内无阴影地板
        # 同聚光下两地板点光照一致 -> 亮度差即阴影 alpha 0.35 的贡献
        if sInR < 80 || sInR > 140
        {
            Console.println( "[light] FAIL: shadowed floor brightness out of range" )
            ret false
        }
        if sOutR - sInR < 25
        {
            Console.println( "[light] FAIL: shadow darkening missing (S_out - S_in < 25)" )
            ret false
        }

        # ── 帧 2：灯光摇晃 —— 聚光位置/强度小幅摆动 -> P1 亮度变化 ──
        # （QT 演示同款动画的确定性快照：posX ±0.08 摇晃 + 强度 ±0.35 脉动）
        lamp.posX = 0.08f * Mathf.sin( 2.1f )
        lamp.intensity = 1.2f + 0.35f * Mathf.sin( 3.7f )
        if lamp.applyTo( pipe, 1 ) == false
        {
            Console.println( "[light] FAIL: sway applyTo - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.renderFrame( 1.0f, px ) == false
        {
            Console.println( "[light] FAIL: renderFrame sway - " + SLang.Render.errorString() )
            ret false
        }
        Int32 p1sR = RenderTestHelpers.sampleChannel( px, 1280, 640, 492, 0 )
        Console.println( "[light] sway  P1=" + p1sR.toString() + " (lamp px=" + ( 0.08f * Mathf.sin( 2.1f ) ).toString() + " I=" + ( 1.2f + 0.35f * Mathf.sin( 3.7f ) ).toString() + ")" )
        if p1sR < 95 || p1sR > 175
        {
            Console.println( "[light] FAIL: swayed in-cone brightness out of range" )
            ret false
        }
        if p1R - p1sR < 4 && p1sR - p1R < 4
        {
            Console.println( "[light] FAIL: lamp sway should change pixel brightness" )
            ret false
        }

        # ── 帧 3：Phong 子场景（独立 256 管线）──────────────────────
        # 同一光照（直射光 0.5 + ambient 0.1）：Lambert quad 中心 =
        # (0.1+0.5)*255 ≈ 153；Phong quad（spec 2.0/4.0）中心 =
        # (0.1+0.5+0.5*0.213*2)*255 ≈ 207 —— 差值即伪 3D 高光贡献
        # 2026-11-13 修复：原误写 1280x720（注释即"独立 256 管线"；
        # px2 为 256x256 缓冲，1280x720 回写 3.5MB 堆越界）
        SLang.RenderPipeline pipe2 = SLang.RenderPipeline.create( 256, 256 )
        if pipe2 == null
        {
            Console.println( "[light] FAIL: phong pipeline create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe2.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[light] FAIL: phong setCamera" )
            ret false
        }
        if pipe2.setAmbient( 0.1f ) == false
        {
            Console.println( "[light] FAIL: phong setAmbient" )
            ret false
        }
        Light sun2 = Light.directional( Color.white(), 0.5f )
        if sun2 == null
        {
            Console.println( "[light] FAIL: phong Light.directional" )
            ret false
        }
        sun2.dirX = 1.0f
        sun2.dirY = 0.0f
        if sun2.applyTo( pipe2, 0 ) == false
        {
            Console.println( "[light] FAIL: phong applyTo" )
            ret false
        }
        SLang.RenderObject quadL = pipe2.addObject( SLang.RenderPipeline.MESH_QUAD )
        SLang.RenderObject quadP = pipe2.addObject( SLang.RenderPipeline.MESH_QUAD )
        if quadL == null || quadP == null
        {
            Console.println( "[light] FAIL: phong add quads" )
            ret false
        }
        quadL.setPosition( -0.55f, 0.6f, 0.0f )
        quadL.setScale( 0.42f, 0.42f )
        quadL.setRotationZ( 0.0f )
        quadL.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        quadP.setPosition( 0.55f, 0.6f, 0.0f )
        quadP.setScale( 0.42f, 0.42f )
        quadP.setRotationZ( 0.0f )
        quadP.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        if quadP.setMaterial( 1 ) == false || quadP.setSpecular( 2.0f, 4.0f ) == false
        {
            Console.println( "[light] FAIL: phong material/specular - " + SLang.Render.errorString() )
            ret false
        }
        Int64 px2 = Memory.alloc( 256 * 256 * 4 )
        if px2 == 0
        {
            Console.println( "[light] FAIL: phong pixel alloc" )
            ret false
        }
        if pipe2.renderFrame( 0.0f, px2 ) == false
        {
            Console.println( "[light] FAIL: phong renderFrame - " + SLang.Render.errorString() )
            ret false
        }
        Int32 lR = RenderTestHelpers.sampleChannel( px2, 256, 58, 51, 0 )
        Int32 pR = RenderTestHelpers.sampleChannel( px2, 256, 198, 51, 0 )
        Console.println( "[light] phong L=" + lR.toString() + " P=" + pR.toString() )
        if lR < 135 || lR > 170
        {
            Console.println( "[light] FAIL: lambert quad brightness out of range" )
            ret false
        }
        if pR < 190 || pR > 225
        {
            Console.println( "[light] FAIL: phong quad brightness out of range" )
            ret false
        }
        if pR - lR < 35
        {
            Console.println( "[light] FAIL: phong specular highlight missing (P - L < 35)" )
            ret false
        }
        if pipe2.destroy() == false
        {
            Console.println( "[light] FAIL: phong pipeline destroy" )
            ret false
        }

        # ── 帧 4：回归 —— 清光 + ambient=1 -> 无光照基线（纯白）──
        if pipe.clearLight( 0 ) == false || pipe.clearLight( 1 ) == false
        {
            Console.println( "[light] FAIL: clearLight" )
            ret false
        }
        if pipe.setAmbient( 1.0f ) == false
        {
            Console.println( "[light] FAIL: setAmbient restore" )
            ret false
        }
        if pipe.lightCount() != 0
        {
            Console.println( "[light] FAIL: lightCount should be 0 after clear" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[light] FAIL: renderFrame unlit - " + SLang.Render.errorString() )
            ret false
        }
        Int32 uA = RenderTestHelpers.sampleChannel( px, 1280, 288, 144, 0 )
        Int32 uB = RenderTestHelpers.sampleChannel( px, 1280, 992, 144, 0 )
        Int32 uP1 = RenderTestHelpers.sampleChannel( px, 1280, 640, 492, 0 )
        Int32 uP2 = RenderTestHelpers.sampleChannel( px, 1280, 1200, 492, 0 )
        Int32 uS = RenderTestHelpers.sampleChannel( px, 1280, 768, 432, 0 )
        Console.println( "[light] unlit A=" + uA.toString() + " B=" + uB.toString() + " P1=" + uP1.toString() + " P2=" + uP2.toString() + " S=" + uS.toString() )
        if uA < 250 || uB < 250 || uP1 < 250 || uP2 < 250 || uS < 250
        {
            Console.println( "[light] FAIL: no-light baseline should be pure white (shadow off without lights)" )
            ret false
        }

        Console.println( "[light] Phase L: PASS (directional ndl + spot cone/attenuation + lamp sway + Phong specular + shadow + no-light regression)" )
        ret true
    }

    # ── Phase SHADOW2：N2a 真实阴影（shadow map + PCF，平行光）──────
    # AIPrompt N2a 验收相位（遮挡像素断言——阴影内亮度 < 阴影外）。
    # 场景（256x256，ortho [-1,1]²，ambient 0.25；quad 半边 = scale*0.5）：
    #   直射光 slot 0：dirX=1（表面→光源 = +x，光沿 -x 照）、白 0.9、
    #     shadowQuality=1 —— stage_shadow_pass（阶段 4.5）以光空间
    #     正交投影渲 castShadow 对象入 512 深度图（LESS 保留最朝光面），
    #     LightBlock 下发 lightVP + shadow 参数，gen shader PCF 4-tap；
    #   地板：pos (0,-0.6,z=-0.1) scale (1.9,0.8) rot 0（法线 (1,0)
    #     朝光 ndl=1 全亮）—— 白色不透明接收面，x∈[-0.95,0.95]
    #     y∈[-1.0,-0.2]；
    #   box：castShadow pos (0.3,-0.6,z=0) scale (0.3,0.3)——
    #     x∈[0.15,0.45] y∈[-0.75,-0.45]，光沿 -x：地板上 x<0.45 且
    #     y∈box 区间区域被遮（深度图记录 box 最朝光 u=0.45 面）。
    # 采样（世界→像素 px=(wx+1)/2*256, py=(1-(wy+1)/2)*256）：
    #   S_in(-0.2,-0.6)→(102,204)：阴影内地板 = (0.25+0.9*0.65)*255≈213
    #   S_out(0.8,-0.6)→(230,204)：box 朝光侧外地板 = 1.15 饱和 255
    #   S_side(-0.2,-0.3)→(102,166)：地板内但 box y 区间外（v 超出）
    #     不遮 → 255（阴影被限定在遮挡几何的光向投影内——非全屏变暗）。
    # shadowQuality=0 时（Phase L 黑斑路径）本相位不重复覆盖。


    # ── Phase SHADOW2：N2a 真实阴影（shadow map + PCF，平行光）──────
    # AIPrompt N2a 验收相位（遮挡像素断言——阴影内亮度 < 阴影外）。
    # 场景（256x256，ortho [-1,1]²，ambient 0.25；quad 半边 = scale*0.5）：
    #   直射光 slot 0：dirX=1（表面→光源 = +x，光沿 -x 照）、白 0.9、
    #     shadowQuality=1 —— stage_shadow_pass（阶段 4.5）以光空间
    #     正交投影渲 castShadow 对象入 512 深度图（LESS 保留最朝光面），
    #     LightBlock 下发 lightVP + shadow 参数，gen shader PCF 4-tap；
    #   地板：pos (0,-0.6,z=-0.1) scale (1.9,0.8) rot 0（法线 (1,0)
    #     朝光 ndl=1 全亮）—— 白色不透明接收面，x∈[-0.95,0.95]
    #     y∈[-1.0,-0.2]；
    #   box：castShadow pos (0.3,-0.6,z=0) scale (0.3,0.3)——
    #     x∈[0.15,0.45] y∈[-0.75,-0.45]，光沿 -x：地板上 x<0.45 且
    #     y∈box 区间区域被遮（深度图记录 box 最朝光 u=0.45 面）。
    # 采样（世界→像素 px=(wx+1)/2*256, py=(1-(wy+1)/2)*256）：
    #   S_in(-0.2,-0.6)→(102,204)：阴影内地板 = (0.25+0.9*0.65)*255≈213
    #   S_out(0.8,-0.6)→(230,204)：box 朝光侧外地板 = 1.15 饱和 255
    #   S_side(-0.2,-0.3)→(102,166)：地板内但 box y 区间外（v 超出）
    #     不遮 → 255（阴影被限定在遮挡几何的光向投影内——非全屏变暗）。
    # shadowQuality=0 时（Phase L 黑斑路径）本相位不重复覆盖。
    public static bool runShadowMap()
    {
        Console.println( "-- Phase SHADOW2: shadow map + PCF (directional light, 256x256) --" )

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[shadow2] FAIL: create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[shadow2] FAIL: setCamera" )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[shadow2] FAIL: setClearColor" )
            ret false
        }
        if pipe.setAmbient( 0.25f ) == false
        {
            Console.println( "[shadow2] FAIL: setAmbient" )
            ret false
        }

        # 平行光：shadowQuality=1 启用 shadow map（N2a）
        Light sun = Light.directional( Color.white(), 0.9f )
        if sun == null
        {
            Console.println( "[shadow2] FAIL: Light.directional" )
            ret false
        }
        sun.dirX = 1.0f
        sun.dirY = 0.0f
        sun.shadowQuality = 1.0f
        if sun.applyTo( pipe, 0 ) == false
        {
            Console.println( "[shadow2] FAIL: directional applyTo - " + SLang.Render.errorString() )
            ret false
        }

        # 地板（接收面）：rot 0 朝光、z=-0.1 比 box 远
        SLang.RenderObject floor = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if floor == null
        {
            Console.println( "[shadow2] FAIL: add floor" )
            ret false
        }
        floor.setPosition( 0.0f, -0.6f, -0.1f )
        floor.setScale( 1.9f, 0.8f )
        floor.setRotationZ( 0.0f )
        floor.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        floor.setQueue( 2000 )

        # 阴影投射 box（不透明 z=0）
        SLang.RenderObject box = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if box == null
        {
            Console.println( "[shadow2] FAIL: add box" )
            ret false
        }
        box.setPosition( 0.3f, -0.6f, 0.0f )
        box.setScale( 0.3f, 0.3f )
        box.setRotationZ( 0.0f )
        box.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        box.setQueue( 2000 )
        if box.setShadow( 1 ) == false
        {
            Console.println( "[shadow2] FAIL: box.setShadow - " + SLang.Render.errorString() )
            ret false
        }

        Int64 px = Memory.alloc( 256 * 256 * 4 )
        if px == 0
        {
            Console.println( "[shadow2] FAIL: pixel alloc" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[shadow2] FAIL: renderFrame - " + SLang.Render.errorString() )
            ret false
        }

        Int32 sInR = RenderTestHelpers.sampleChannel( px, 256, 102, 204, 0 )
        Int32 sOutR = RenderTestHelpers.sampleChannel( px, 256, 230, 204, 0 )
        Int32 sSideR = RenderTestHelpers.sampleChannel( px, 256, 102, 166, 0 )
        Console.println( "[shadow2] S_in=" + sInR.toString() + " S_out=" + sOutR.toString() + " S_side=" + sSideR.toString() )
        if sOutR < 250
        {
            Console.println( "[shadow2] FAIL: unshadowed floor should be fully lit (ambient + directional)" )
            ret false
        }
        if sInR < 175 || sInR > 235
        {
            Console.println( "[shadow2] FAIL: shadowed floor brightness out of range (expect ~213)" )
            ret false
        }
        if sOutR - sInR < 30
        {
            Console.println( "[shadow2] FAIL: shadow darkening missing (S_out - S_in < 30)" )
            ret false
        }
        if sSideR < 250
        {
            Console.println( "[shadow2] FAIL: outside-projection floor should be fully lit" )
            ret false
        }

        Console.println( "[shadow2] Phase SHADOW2: PASS (shadow map: in-shadow 213 < out-shadow 255, PCF + projection bounds verified)" )
        ret true
    }

    # ── Phase CSM：N2b 级联阴影（4 级联 v 分段 + 图集 1x4 分区）─────
    # AIPrompt N2b 验收相位（级联采样落位断言）。
    # 场景（256x256，ortho [-1,1]²，ambient 0.25，光 (1,0) 沿 -x，
    # shadowQuality=1 + shadowCascades=4）——v 轴 = 光空间 y（dx=1,dy=0
    # → v = world.y）：相机视域 [-1,1] 主导 → 级联分段
    # {-1, -0.9, -0.5, 0.2, 1}（0.05/0.25/0.6/1.0 比例）：
    #   地板 (0,-0.1,z-0.1) scale (1.9,1.8)：y∈[-1.0,0.8] 接收面；
    #   boxA (0.3,-0.85) 0.3 —— v∈[-1.0,-0.7] 跨级联 0/1；
    #   boxB (0.3,0.0) 0.3   —— v∈[-0.15,0.15] 仅级联 2；
    #   boxC (0.3,-0.5) 0.2  —— v∈[-0.6,-0.4] 骑跨级联 1/2 边界(-0.5)。
    # 断言（级联采样落位——选错级联 → 采到空分区 → 255 不暗）：
    #   S_inA(-0.2,-0.85)=213（级联 0 落位 + boxA 覆盖）
    #   S_inB(-0.2,0.0)=213（级联 2 落位——boxB 只渲进级联 2，
    #     若 v 比较错落 0/1/3 级 → 空区 → 255）
    #   S_out(0.8,0.0)=255（级联 2 无遮挡区）
    #   S_e1(-0.2,-0.55)=213（boxC 级联 1 侧覆盖）
    #   S_e2(-0.2,-0.45)=213（boxC 级联 2 侧覆盖——边界骑跨两级都渲）
    #   S_out2(-0.2,0.3)=255（级联 3 空区）


    # ── Phase CSM：N2b 级联阴影（4 级联 v 分段 + 图集 1x4 分区）─────
    # AIPrompt N2b 验收相位（级联采样落位断言）。
    # 场景（256x256，ortho [-1,1]²，ambient 0.25，光 (1,0) 沿 -x，
    # shadowQuality=1 + shadowCascades=4）——v 轴 = 光空间 y（dx=1,dy=0
    # → v = world.y）：相机视域 [-1,1] 主导 → 级联分段
    # {-1, -0.9, -0.5, 0.2, 1}（0.05/0.25/0.6/1.0 比例）：
    #   地板 (0,-0.1,z-0.1) scale (1.9,1.8)：y∈[-1.0,0.8] 接收面；
    #   boxA (0.3,-0.85) 0.3 —— v∈[-1.0,-0.7] 跨级联 0/1；
    #   boxB (0.3,0.0) 0.3   —— v∈[-0.15,0.15] 仅级联 2；
    #   boxC (0.3,-0.5) 0.2  —— v∈[-0.6,-0.4] 骑跨级联 1/2 边界(-0.5)。
    # 断言（级联采样落位——选错级联 → 采到空分区 → 255 不暗）：
    #   S_inA(-0.2,-0.85)=213（级联 0 落位 + boxA 覆盖）
    #   S_inB(-0.2,0.0)=213（级联 2 落位——boxB 只渲进级联 2，
    #     若 v 比较错落 0/1/3 级 → 空区 → 255）
    #   S_out(0.8,0.0)=255（级联 2 无遮挡区）
    #   S_e1(-0.2,-0.55)=213（boxC 级联 1 侧覆盖）
    #   S_e2(-0.2,-0.45)=213（boxC 级联 2 侧覆盖——边界骑跨两级都渲）
    #   S_out2(-0.2,0.3)=255（级联 3 空区）
    public static bool runCsmShadow()
    {
        Console.println( "-- Phase CSM: 4-cascade shadow atlas (v split 0.05/0.25/0.6/1.0, 256x256) --" )

        SLang.RenderPipeline pipe = SLang.RenderPipeline.create( 256, 256 )
        if pipe == null
        {
            Console.println( "[csm] FAIL: create - " + SLang.Render.errorString() )
            ret false
        }
        if pipe.setCamera( -1, -1.0f, 1.0f, -1.0f, 1.0f ) == false
        {
            Console.println( "[csm] FAIL: setCamera" )
            ret false
        }
        if pipe.setClearColor( 0.06f, 0.06f, 0.10f, 1.0f ) == false
        {
            Console.println( "[csm] FAIL: setClearColor" )
            ret false
        }
        if pipe.setAmbient( 0.25f ) == false
        {
            Console.println( "[csm] FAIL: setAmbient" )
            ret false
        }

        # 平行光：shadowQuality=1 + 4 级联（N2b CSM）
        Light sun = Light.directional( Color.white(), 0.9f )
        if sun == null
        {
            Console.println( "[csm] FAIL: Light.directional" )
            ret false
        }
        sun.dirX = 1.0f
        sun.dirY = 0.0f
        sun.shadowQuality = 1.0f
        sun.shadowCascades = 4.0f
        if sun.applyTo( pipe, 0 ) == false
        {
            Console.println( "[csm] FAIL: directional applyTo - " + SLang.Render.errorString() )
            ret false
        }

        # 地板（接收面，rot 0 朝光）
        SLang.RenderObject floor = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if floor == null
        {
            Console.println( "[csm] FAIL: add floor" )
            ret false
        }
        floor.setPosition( 0.0f, -0.1f, -0.1f )
        floor.setScale( 1.9f, 1.8f )
        floor.setRotationZ( 0.0f )
        floor.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        floor.setQueue( 2000 )

        # 三个 castShadow box（分属不同级联 + 骑跨边界）
        SLang.RenderObject boxA = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        SLang.RenderObject boxB = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        SLang.RenderObject boxC = pipe.addObject( SLang.RenderPipeline.MESH_QUAD )
        if boxA == null || boxB == null || boxC == null
        {
            Console.println( "[csm] FAIL: add boxes" )
            ret false
        }
        boxA.setPosition( 0.3f, -0.85f, 0.0f )
        boxA.setScale( 0.3f, 0.3f )
        boxA.setRotationZ( 0.0f )
        boxA.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        boxA.setQueue( 2000 )
        if boxA.setShadow( 1 ) == false
        {
            Console.println( "[csm] FAIL: boxA.setShadow" )
            ret false
        }
        boxB.setPosition( 0.3f, 0.0f, 0.0f )
        boxB.setScale( 0.3f, 0.3f )
        boxB.setRotationZ( 0.0f )
        boxB.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        boxB.setQueue( 2000 )
        if boxB.setShadow( 1 ) == false
        {
            Console.println( "[csm] FAIL: boxB.setShadow" )
            ret false
        }
        boxC.setPosition( 0.3f, -0.5f, 0.0f )
        boxC.setScale( 0.2f, 0.2f )
        boxC.setRotationZ( 0.0f )
        boxC.setColor( 1.0f, 1.0f, 1.0f, 1.0f )
        boxC.setQueue( 2000 )
        if boxC.setShadow( 1 ) == false
        {
            Console.println( "[csm] FAIL: boxC.setShadow" )
            ret false
        }

        Int64 px = Memory.alloc( 256 * 256 * 4 )
        if px == 0
        {
            Console.println( "[csm] FAIL: pixel alloc" )
            ret false
        }
        if pipe.renderFrame( 0.0f, px ) == false
        {
            Console.println( "[csm] FAIL: renderFrame - " + SLang.Render.errorString() )
            ret false
        }

        Int32 sInA = RenderTestHelpers.sampleChannel( px, 256, 102, 237, 0 )
        Int32 sInB = RenderTestHelpers.sampleChannel( px, 256, 102, 128, 0 )
        Int32 sOut = RenderTestHelpers.sampleChannel( px, 256, 230, 128, 0 )
        Int32 sE1 = RenderTestHelpers.sampleChannel( px, 256, 102, 199, 0 )
        Int32 sE2 = RenderTestHelpers.sampleChannel( px, 256, 102, 186, 0 )
        Int32 sOut2 = RenderTestHelpers.sampleChannel( px, 256, 102, 90, 0 )
        Console.println( "[csm] S_inA=" + sInA.toString() + " S_inB=" + sInB.toString() + " S_out=" + sOut.toString() + " S_e1=" + sE1.toString() + " S_e2=" + sE2.toString() + " S_out2=" + sOut2.toString() )
        # 级联 0 落位（boxA 在 v≈-0.85 区）
        if sInA < 175 || sInA > 235
        {
            Console.println( "[csm] FAIL: cascade 0 sampling misplaced (expect ~213)" )
            ret false
        }
        # 级联 2 落位（boxB 仅渲进级联 2——选错级联采空区 255）
        if sInB < 175 || sInB > 235
        {
            Console.println( "[csm] FAIL: cascade 2 sampling misplaced (expect ~213)" )
            ret false
        }
        if sOut < 250
        {
            Console.println( "[csm] FAIL: unshadowed floor should be fully lit" )
            ret false
        }
        # 边界骑跨：boxC 在级联 1 与级联 2 两侧都投影覆盖
        if sE1 < 175 || sE1 > 235
        {
            Console.println( "[csm] FAIL: boundary box cascade-1 side should be shadowed" )
            ret false
        }
        if sE2 < 175 || sE2 > 235
        {
            Console.println( "[csm] FAIL: boundary box cascade-2 side should be shadowed" )
            ret false
        }
        # 级联 3 空区（v=0.3 无遮挡）
        if sOut2 < 250
        {
            Console.println( "[csm] FAIL: empty cascade 3 region should be fully lit" )
            ret false
        }

        Console.println( "[csm] Phase CSM: PASS (4 cascades: per-level placement + boundary straddle + empty region, atlas 1x4)" )
        ret true
    }

    # ── Phase CB：CommandBuffer 真录制（录制 → 整理 → 提交渲染）──
    # Unity 式三段式端到端验收（doc/04 §3.6 SLMC 命令流全链路）：
    #   1 录制：cb.begin() 后零后端调用，仅参数组织与顺序记账 ——
    #     setRenderTargets / setTexture / setPerDraw / drawItem /
    #     postProcess / blitFinal / readback，共 11 条命令；
    #   2 整理：cb.sortDrawItems() 对 DrawItem 段排序（drawItem 乱序
    #     录入：蓝 z0.3 -> 贴图 z0.5 -> 三角 z0.0；正确序 = 三角
    #     (queue2000 不透明先画) -> 贴图(z0.5 远) -> 蓝(z0.3 近)，
    #     透明 z 降序远->近保混合）；
    #   3 提交渲染：pipe.executeCommandBuffer(cb) 按 SLMC 布局打包
    #     整包提交，C 侧逐 opcode 回放（命令流走 RHI vtable ->
    #     GL/D3D11/VK/GLES 四后端同效果，Phase D/E/F 各复检一次）。
    # 场景（自建自毁 256x256 管线，不触碰 RenderTest._pipe/RenderTest._pixels）：
    #   perdraw 槽 0 红三角（不透明 queue2000）；槽 1 白贴图 quad
    #   (中心 0.45,0.35 scale0.55, 透明 z0.5, 64x64 渐变贴图)；槽 2
    #   蓝 quad（中心 0.55,0.35 scale0.25, 透明 z0.3, 与贴图 quad
    #   重叠 —— 重叠点是排序方向验证点：正确序蓝后画 -> 蓝分量高）。
}
