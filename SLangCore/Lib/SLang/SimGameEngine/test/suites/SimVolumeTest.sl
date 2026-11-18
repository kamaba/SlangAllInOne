import SimGameEngine;
import Std;
import Math;
import SLangRender;

# ============================================================================
# SimVolumeTest — SimGameEngine P8 Volume 参数栈验证（第 10 套）
# ----------------------------------------------------------------------------
# 覆盖：C 混合核心（sle_volume_blend 经 EngineFfi 绑定）——单 Volume 全字段、
# 掩码保留（缺省=不修改）、priority 排序覆盖、weight lerp、局部范围 +
# blendDistance 衰减、激活过滤、诊断计数、确定性、未支持效果统计、
# applyPost 无管线优雅 false。
# 写法约束（doc/10 §6）：构造器 + addComponent（跨模块静态工厂不可用）；
# 比较值取二进制精确浮点（0.5/0.25/1.5）防 lerp 末位噪声；内联构造
# 表达式不作实参。
# ============================================================================

public class SimVolumeTest
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

    static VolumeProfile newProfile()
    {
        VolumeProfile p = VolumeProfile()
        ret p
    }

    static GameObject addVolume( Scene scene, string name, GameObject parent, VolumeProfile prof, bool isG, Int32 prio, Float32 w )
    {
        GameObject go = scene.createObject( name, parent )
        Volume vol = Volume()
        vol.profile = prof
        vol.isGlobal = isG
        vol.priority = prio
        vol.weight = w
        go.addComponent( vol )
        ret go
    }

    # 造局部 Volume 的生效范围（中心 + 尺寸）
    static Bounds makeBounds( Float32 cx, Float32 cy, Float32 cz, Float32 sx, Float32 sy, Float32 sz )
    {
        Bounds b = Bounds()
        Float32_3 mn = Float32_3( cx - sx * 0.5f, cy - sy * 0.5f, cz - sz * 0.5f )
        Float32_3 mx = Float32_3( cx + sx * 0.5f, cy + sy * 0.5f, cz + sz * 0.5f )
        b.min = mn
        b.max = mx
        ret b
    }

    # ── W1. C 绑定直测（手组块，24 float/Volume 布局）──
    static void testFfiDirect()
    {
        Int64 inPtr = Memory.alloc( 96 )
        Int64 outPtr = Memory.alloc( 44 )
        check( inPtr != 0 && outPtr != 0, "W1a alloc" )
        # [0]w [1]pri [2]global [3]dist
        Memory.writeF32( inPtr, 0, 1.0f )
        Memory.writeF32( inPtr, 4, 0.0f )
        Memory.writeF32( inPtr, 8, 1.0f )
        Memory.writeF32( inPtr, 12, 0.0f )
        # [4..5] brightness=0.5（唯一配置项）
        Memory.writeF32( inPtr, 16, 1.0f )
        Memory.writeF32( inPtr, 20, 0.5f )
        # [6..23] 其余全部未配置（中性）
        Memory.writeF32( inPtr, 24, 0.0f )
        Memory.writeF32( inPtr, 28, 1.0f )
        Memory.writeF32( inPtr, 32, 0.0f )
        Memory.writeF32( inPtr, 36, 1.0f )
        Memory.writeF32( inPtr, 40, 0.0f )
        Memory.writeF32( inPtr, 44, 0.0f )
        Memory.writeF32( inPtr, 48, 0.0f )
        Memory.writeF32( inPtr, 52, 1.0f )
        Memory.writeF32( inPtr, 56, 0.0f )
        Memory.writeF32( inPtr, 60, 0.0f )
        Memory.writeF32( inPtr, 64, 0.0f )
        Memory.writeF32( inPtr, 68, 0.0f )
        Memory.writeF32( inPtr, 72, 0.0f )
        Memory.writeF32( inPtr, 76, 0.0f )
        Memory.writeF32( inPtr, 80, 0.0f )
        Memory.writeF32( inPtr, 84, 1.0f )
        Memory.writeF32( inPtr, 88, 1.0f )
        Memory.writeF32( inPtr, 92, 1.0f )
        Int32 used = EngineFfi.libVolumeBlend( inPtr, 1, outPtr )
        check( used == 1, "W1b blend returns 1 (C binding live)" )
        Float32 br = Memory.readFloat32( outPtr, 0 )
        Float32 sa = Memory.readFloat32( outPtr, 8 )
        Float32 vi = Memory.readFloat32( outPtr, 12 )
        check( br == 0.5f, "W1c brightness blended" )
        check( sa == 1.0f, "W1d saturation neutral" )
        check( vi == 0.0f, "W1e vignette neutral (无暗角，v1.1 语义)" )
        check( Memory.readFloat32( outPtr, 4 ) == 1.0f, "W1f contrast neutral" )
        Memory.free( inPtr )
        Memory.free( outPtr )
    }

    # ── W2. 单全局 Volume 全字段 ───────────────────────
    static void testSingleGlobal()
    {
        Scene scene = Scene( "W2" )
        VolumeProfile prof = newProfile()
        prof.setPost( 0.5f, 1.25f, 0.75f )
        addVolume( scene, "V", null, prof, true, 0, 1.0f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack st = vs.compute( scene, cam )
        check( st.contributing == 1, "W2a contributing 1" )
        check( st.brightness == 0.5f, "W2b brightness" )
        check( st.saturation == 1.25f, "W2c saturation" )
        check( st.vignette == 0.75f, "W2d vignette" )
    }

    # ── W3. 掩码保留（缺省 = 不修改）──────────────────
    static void testMaskPreserve()
    {
        Scene scene = Scene( "W3" )
        VolumeProfile prof = newProfile()
        prof.setVignette( 0.5f )
        addVolume( scene, "V", null, prof, true, 0, 1.0f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack st = vs.compute( scene, cam )
        check( st.brightness == 1.0f, "W3a brightness preserved" )
        check( st.saturation == 1.0f, "W3b saturation preserved" )
        check( st.vignette == 0.5f, "W3c vignette applied" )
    }

    # ── W4. priority 排序（值大者后应用 = 覆盖优先）───
    static void testPriorityOrder()
    {
        Scene scene = Scene( "W4" )
        VolumeProfile low = newProfile()
        low.setBrightness( 0.5f )
        VolumeProfile high = newProfile()
        high.setBrightness( 1.5f )
        addVolume( scene, "L", null, low, true, 0, 1.0f )
        addVolume( scene, "H", null, high, true, 5, 1.0f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack st = vs.compute( scene, cam )
        check( st.contributing == 2, "W4a contributing 2" )
        check( st.brightness == 1.5f, "W4b high priority wins" )
    }

    # ── W5. weight lerp（0.5 → 0.75 → 0.625）─────────
    static void testWeightLerp()
    {
        Scene scene = Scene( "W5" )
        VolumeProfile p1 = newProfile()
        p1.setBrightness( 0.5f )
        VolumeProfile p2 = newProfile()
        p2.setBrightness( 0.5f )
        addVolume( scene, "A", null, p1, true, 0, 0.5f )
        addVolume( scene, "B", null, p2, true, 1, 0.5f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack st = vs.compute( scene, cam )
        check( st.brightness == 0.625f, "W5a lerp chain 0.625" )
    }

    # ── W6. 局部范围（内圈满权重）──────────────────────
    static void testLocalInside()
    {
        Scene scene = Scene( "W6" )
        VolumeProfile prof = newProfile()
        prof.setBrightness( 0.5f )
        GameObject go = addVolume( scene, "R", null, prof, false, 0, 1.0f )
        Volume vol = go.getComponent<Volume>()
        vol.influenceBounds = makeBounds( 0.0f, 0.0f, 0.0f, 10.0f, 10.0f, 10.0f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack st = vs.compute( scene, cam )
        check( st.contributing == 1, "W6a inside contributes" )
        check( st.brightness == 0.5f, "W6b full weight applied" )
    }

    # ── W7. blendDistance 外扩衰减 ─────────────────────
    static void testBlendDistance()
    {
        Scene scene = Scene( "W7" )
        VolumeProfile prof = newProfile()
        prof.setBrightness( 0.0f )
        GameObject go = addVolume( scene, "R", null, prof, false, 0, 1.0f )
        Volume vol = go.getComponent<Volume>()
        vol.influenceBounds = makeBounds( 0.0f, 0.0f, 0.0f, 10.0f, 10.0f, 10.0f )
        vol.blendDistance = 4.0f
        VolumeSystem vs = VolumeSystem()
        # 相机在 +Z 面外 2（max z=5，cam z=7）→ 衰减 1-2/4 = 0.5
        Float32_3 cam = Float32_3( 0.0f, 0.0f, 7.0f )
        VolumeStack st = vs.compute( scene, cam )
        check( st.contributing == 1, "W7a in falloff band" )
        check( st.brightness == 0.5f, "W7b half weight lerp" )
        # 远离范围 → 不贡献
        Float32_3 far = Float32_3( 0.0f, 0.0f, 20.0f )
        VolumeStack st2 = vs.compute( scene, far )
        check( st2.contributing == 0, "W7c far outside culled" )
        check( st2.brightness == 1.0f, "W7d neutral stack" )
    }

    # ── W8. 硬切（blendDistance=0）与全局优先 ──────────
    static void testGlobalPriority()
    {
        Scene scene = Scene( "W8" )
        VolumeProfile pg = newProfile()
        pg.setBrightness( 0.5f )
        VolumeProfile pl = newProfile()
        pl.setBrightness( 1.5f )
        addVolume( scene, "G", null, pg, true, 0, 1.0f )
        GameObject goL = addVolume( scene, "L", null, pl, false, 9, 1.0f )
        Volume volL = goL.getComponent<Volume>()
        volL.influenceBounds = makeBounds( 0.0f, 0.0f, 0.0f, 10.0f, 10.0f, 10.0f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack st = vs.compute( scene, cam )
        # 全局先应用（ despite priority），局部后应用 → 局部覆盖
        check( st.brightness == 1.5f, "W8a global first, local overrides" )
    }

    # ── W9. 过滤：未激活 / null profile / weight 0 ─────
    static void testFiltering()
    {
        Scene scene = Scene( "W9" )
        VolumeProfile prof = newProfile()
        prof.setBrightness( 0.5f )
        GameObject dead = addVolume( scene, "dead", null, prof, true, 0, 1.0f )
        dead.setActive( false )
        GameObject nop = scene.createObject( "nop" )
        Volume vn = Volume()
        nop.addComponent( vn )
        GameObject zero = addVolume( scene, "zero", null, prof, true, 0, 0.0f )
        Volume volZero = zero.getComponent<Volume>()
        volZero.influenceBounds = makeBounds( 0.0f, 0.0f, 0.0f, 10.0f, 10.0f, 10.0f )
        addVolume( scene, "alive", null, prof, true, 0, 1.0f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack st = vs.compute( scene, cam )
        check( st.contributing == 1, "W9a only valid volume survives" )
        check( vs.lastCollected == 1, "W9b collected diag" )
        # culled = weight 0 + null profile（两者 weightAt=0）
        check( vs.lastCulled == 2, "W9c culled diag (weight0 + null profile)" )
    }

    # ── W10. 确定性 + 未支持效果统计 + 无管线 ──────────
    static void testDeterminismAndStats()
    {
        Scene scene = Scene( "W10" )
        VolumeProfile prof = newProfile()
        prof.setBrightness( 0.5f )
        prof.hasBloom = true
        prof.bloomIntensity = 0.7f
        prof.hasDof = true
        prof.dofFocusDistance = 3.0f
        check( prof.unsupportedCount() == 2, "W10a unsupported counted" )
        addVolume( scene, "V", null, prof, true, 0, 1.0f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack s1 = vs.compute( scene, cam )
        VolumeStack s2 = vs.compute( scene, cam )
        bool same = ( s1.brightness == s2.brightness ) && ( s1.saturation == s2.saturation )
        check( same, "W10b deterministic" )
        check( s1.brightness == 0.5f, "W10c bloom not applied (post params only)" )
        # 空场景中性栈
        VolumeStack s0 = vs.compute( Scene( "empty" ), cam )
        bool neutral = ( s0.contributing == 0 ) && ( s0.brightness == 1.0f )
        check( neutral, "W10d empty scene neutral" )
        # 无管线优雅失败
        RenderSystem rs = RenderSystem()
        check( !rs.applyPost( s1 ), "W10e applyPost no-pipe false" )
    }

    # ── W11. v1.1 扩参全字段（contrast/hue/grain/filter/tonemap/vigSmooth）──
    static void testExtendedFields()
    {
        Scene scene = Scene( "W11" )
        VolumeProfile prof = newProfile()
        prof.setContrast( 0.6f )
        prof.setHueShift( 30.0f )
        prof.setGrain( 0.2f )
        prof.setTonemap( 1 )
        prof.setColorFilter( 0.9f, 0.8f, 0.7f )
        prof.setVignetteSmooth( 0.5f )
        prof.setVignette( 0.4f )
        addVolume( scene, "V", null, prof, true, 0, 1.0f )
        VolumeSystem vs = VolumeSystem()
        Float32_3 cam = Float32_3.zero()
        VolumeStack st = vs.compute( scene, cam )
        check( st.contributing == 1, "W11a contributing 1" )
        check( st.contrast == 0.6f, "W11b contrast" )
        check( st.hueShift == 30.0f, "W11c hueShift" )
        check( st.grain == 0.2f, "W11d grain" )
        check( st.tonemap == 1, "W11e tonemap override" )
        check( st.filterR == 0.9f && st.filterG == 0.8f && st.filterB == 0.7f, "W11f colorFilter" )
        check( st.vignette == 0.4f, "W11g vignette" )
        check( st.vignetteSmooth == 0.5f, "W11h vignetteSmooth" )
        # 未配置字段保持中性（掩码语义）
        check( st.brightness == 1.0f && st.saturation == 1.0f, "W11i unconfigured neutral" )
        # 局部 weight 0.5 lerp：contrast 0.6 → 中性 1 + (0.6-1)*0.5 = 0.8
        Scene s2 = Scene( "W11b" )
        VolumeProfile p2 = newProfile()
        p2.setContrast( 0.6f )
        addVolume( s2, "V", null, p2, true, 0, 0.5f )
        VolumeStack s3 = vs.compute( s2, cam )
        check( s3.contrast == 0.8f, "W11j contrast lerp half weight" )
    }

    public static void run()
    {
        testFfiDirect()
        testSingleGlobal()
        testMaskPreserve()
        testPriorityOrder()
        testWeightLerp()
        testLocalInside()
        testBlendDistance()
        testGlobalPriority()
        testFiltering()
        testDeterminismAndStats()
        testExtendedFields()
        Console.println( "SimVolumeTest: PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
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
