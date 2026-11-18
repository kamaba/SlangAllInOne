import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# VolumeSystem — Volume 参数栈系统（P8 Volume 落盘 v1，doc/14 §3/§4）
# ----------------------------------------------------------------------------
# 每帧、每相机各算一次：收集激活 Volume → 过滤（全局 / 范围 + blendDistance
# 衰减）→ C 侧排序混合（sle_volume_blend：全局优先 → priority 升序 →
# 距离升序，掩码字段 lerp）→ VolumeStack → RenderSystem.applyPost 下发
# setPostEffect。**计算核心在 C**（sl_sim_engine_lib），本类只做收集
# 组块与解块（复用专项约定：重计算下沉 FFI，SL 只放类与接口）。
# 架构约束（doc/10 §6）：plain 类循环读 Behaviour 实例字段 = collect
# 上下文可靠（Batcher 同款）；Volume.weightAt 为 straight-line 方法。
# ============================================================================
public class VolumeSystem
{
    # 单次混合上限（C 侧 SLE_VOLUME_MAX 同值）
    public Int32 maxVolumes = 64
    # 上次 compute 的诊断计数
    public Int32 lastCollected = 0
    public Int32 lastCulled = 0

    # 场景 → 每相机参数栈（无 Volume / 无贡献时返回中性栈 contributing=0）
    public VolumeStack compute( Scene scene, Float32_3 camPos )
    {
        VolumeStack st = VolumeStack()
        this.lastCollected = 0
        this.lastCulled = 0
        if scene == null
        {
            ret st
        }
        # ── 收集（显式栈先序遍历，不递归）──────────────────
        List<Volume> vols = List<Volume>( 8 )
        List<Float32> wts = List<Float32>( 8 )
        List<Float32> dsts = List<Float32>( 8 )
        List<GameObject> stack = List<GameObject>( 16 )
        Int32 ri = scene.rootCount() - 1
        while ri > 0 - 1
        {
            GameObject r = scene.getRoot( ri )
            if r != null
            {
                stack.add( r )
            }
            ri = ri - 1
        }
        while stack.length > 0
        {
            Int32 lastIdx = stack.length - 1
            GameObject cur = stack[lastIdx]
            stack.removeAt( lastIdx )
            bool active = cur.getActiveInHierarchy()
            if active
            {
                Volume vol = cur.getComponent<Volume>()
                if vol != null
                {
                    Float32 w = vol.weightAt( camPos )
                    if w > 0.0f
                    {
                        Float32 d = 0.0f
                        if !vol.isGlobal
                        {
                            Bounds b = vol.influenceBounds
                            if b != null
                            {
                                d = b.distanceTo( camPos )
                            }
                        }
                        vols.add( vol )
                        wts.add( w )
                        dsts.add( d )
                    }
                    else
                    {
                        this.lastCulled = this.lastCulled + 1
                    }
                }
                Int32 cn = cur.childCount
                Int32 ci = cn - 1
                while ci > 0 - 1
                {
                    GameObject ch = cur.getChild( ci )
                    if ch != null
                    {
                        stack.add( ch )
                    }
                    ci = ci - 1
                }
            }
        }
        Int32 n = vols.length
        this.lastCollected = n
        if n < 1
        {
            ret st
        }
        Int32 cap = n
        if cap > this.maxVolumes
        {
            cap = this.maxVolumes
        }
        # ── 组块（每 Volume 24 float，布局见 sle_engine.c）──────
        Int32 stride = 96
        Int64 inPtr = Memory.alloc( cap * stride )
        Int64 outPtr = Memory.alloc( 44 )
        if inPtr == 0 || outPtr == 0
        {
            if inPtr != 0
            {
                Memory.free( inPtr )
            }
            if outPtr != 0
            {
                Memory.free( outPtr )
            }
            ret st
        }
        Int32 i = 0
        while i < cap
        {
            Volume v = vols[i]
            VolumeProfile pf = v.profile
            Float32 w = wts[i]
            Int32 off = i * stride
            Memory.writeF32( inPtr, off + 0, w )
            Memory.writeF32( inPtr, off + 4, v.priority.toFloat32() )
            Int32 g = 0
            if v.isGlobal
            {
                g = 1
            }
            Memory.writeF32( inPtr, off + 8, g.toFloat32() )
            Float32 d = dsts[i]
            Memory.writeF32( inPtr, off + 12, d )
            # [4..5] brightness / [6..7] contrast / [8..9] saturation
            Int32 m = 0
            if pf.hasBrightness
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 16, m.toFloat32() )
            Memory.writeF32( inPtr, off + 20, pf.brightness )
            m = 0
            if pf.hasContrast
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 24, m.toFloat32() )
            Memory.writeF32( inPtr, off + 28, pf.contrast )
            m = 0
            if pf.hasSaturation
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 32, m.toFloat32() )
            Memory.writeF32( inPtr, off + 36, pf.saturation )
            # [10..11] vignette / [12..13] vigSmooth
            m = 0
            if pf.hasVignette
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 40, m.toFloat32() )
            Memory.writeF32( inPtr, off + 44, pf.vignette )
            m = 0
            if pf.hasVignetteSmooth
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 48, m.toFloat32() )
            Memory.writeF32( inPtr, off + 52, pf.vignetteSmooth )
            # [14..15] hueShift / [16..17] grain
            m = 0
            if pf.hasHueShift
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 56, m.toFloat32() )
            Memory.writeF32( inPtr, off + 60, pf.hueShift )
            m = 0
            if pf.hasGrain
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 64, m.toFloat32() )
            Memory.writeF32( inPtr, off + 68, pf.grain )
            # [18..19] tonemap（枚举以 float 传入，覆盖不插值）
            m = 0
            if pf.hasTonemap
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 72, m.toFloat32() )
            Memory.writeF32( inPtr, off + 76, pf.tonemapMode.toFloat32() )
            # [20..23] colorFilter RGB
            m = 0
            if pf.hasFilter
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 80, m.toFloat32() )
            Memory.writeF32( inPtr, off + 84, pf.filterR )
            Memory.writeF32( inPtr, off + 88, pf.filterG )
            Memory.writeF32( inPtr, off + 92, pf.filterB )
            i = i + 1
        }
        # ── C 混合（绑定失败 <0 → SL 线性兜底）──────────────
        Int32 used = EngineFfi.libVolumeBlend( inPtr, cap, outPtr )
        if used >= 0
        {
            st.brightness = Memory.readFloat32( outPtr, 0 )
            st.contrast = Memory.readFloat32( outPtr, 4 )
            st.saturation = Memory.readFloat32( outPtr, 8 )
            st.vignette = Memory.readFloat32( outPtr, 12 )
            st.vignetteSmooth = Memory.readFloat32( outPtr, 16 )
            st.hueShift = Memory.readFloat32( outPtr, 20 )
            st.grain = Memory.readFloat32( outPtr, 24 )
            st.tonemap = Memory.readFloat32( outPtr, 28 ).toInt32()
            st.filterR = Memory.readFloat32( outPtr, 32 )
            st.filterG = Memory.readFloat32( outPtr, 36 )
            st.filterB = Memory.readFloat32( outPtr, 40 )
            st.contributing = used
        }
        else
        {
            # SL 兜底：按收集序线性 lerp（无排序——绑定失败征兆，功能可用）
            Float32 br = 1.0f
            Float32 ct = 1.0f
            Float32 sa = 1.0f
            Float32 vi = 0.0f
            Float32 vs = 1.0f
            Float32 hu = 0.0f
            Float32 gr = 0.0f
            Float32 tm = 0.0f
            Float32 fr = 1.0f
            Float32 fg = 1.0f
            Float32 fb = 1.0f
            Int32 k = 0
            while k < cap
            {
                Volume v = vols[k]
                VolumeProfile pf = v.profile
                Float32 w = wts[k]
                if pf.hasBrightness
                {
                    br = br + ( pf.brightness - br ) * w
                }
                if pf.hasContrast
                {
                    ct = ct + ( pf.contrast - ct ) * w
                }
                if pf.hasSaturation
                {
                    sa = sa + ( pf.saturation - sa ) * w
                }
                if pf.hasVignette
                {
                    vi = vi + ( pf.vignette - vi ) * w
                }
                if pf.hasVignetteSmooth
                {
                    vs = vs + ( pf.vignetteSmooth - vs ) * w
                }
                if pf.hasHueShift
                {
                    hu = hu + ( pf.hueShift - hu ) * w
                }
                if pf.hasGrain
                {
                    gr = gr + ( pf.grain - gr ) * w
                }
                if pf.hasTonemap
                {
                    tm = pf.tonemapMode.toFloat32()
                }
                if pf.hasFilter
                {
                    fr = fr + ( pf.filterR - fr ) * w
                    fg = fg + ( pf.filterG - fg ) * w
                    fb = fb + ( pf.filterB - fb ) * w
                }
                k = k + 1
            }
            st.brightness = br
            st.contrast = ct
            st.saturation = sa
            st.vignette = vi
            st.vignetteSmooth = vs
            st.hueShift = hu
            st.grain = gr
            st.tonemap = tm.toInt32()
            st.filterR = fr
            st.filterG = fg
            st.filterB = fb
            st.contributing = cap
        }
        Memory.free( inPtr )
        Memory.free( outPtr )
        ret st
    }
}
