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
        # ── 组块（每 Volume 11 float，布局见 sle_engine.c）──────
        Int32 stride = 44
        Int64 inPtr = Memory.alloc( cap * stride )
        Int64 outPtr = Memory.alloc( 16 )
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
            Int32 m = 0
            if pf.hasBrightness
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 16, m.toFloat32() )
            Memory.writeF32( inPtr, off + 20, pf.brightness )
            m = 0
            if pf.hasSaturation
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 24, m.toFloat32() )
            Memory.writeF32( inPtr, off + 28, pf.saturation )
            m = 0
            if pf.hasVignette
            {
                m = 1
            }
            Memory.writeF32( inPtr, off + 32, m.toFloat32() )
            Memory.writeF32( inPtr, off + 36, pf.vignette )
            Memory.writeF32( inPtr, off + 40, 0.0f )
            i = i + 1
        }
        # ── C 混合（绑定失败 <0 → SL 线性兜底）──────────────
        Int32 used = EngineFfi.libVolumeBlend( inPtr, cap, outPtr )
        if used >= 0
        {
            st.brightness = Memory.readFloat32( outPtr, 0 )
            st.saturation = Memory.readFloat32( outPtr, 4 )
            st.vignette = Memory.readFloat32( outPtr, 8 )
            st.contributing = used
        }
        else
        {
            # SL 兜底：按收集序线性 lerp（无排序——绑定失败征兆，功能可用）
            Float32 br = 1.0f
            Float32 sa = 1.0f
            Float32 vi = 1.0f
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
                if pf.hasSaturation
                {
                    sa = sa + ( pf.saturation - sa ) * w
                }
                if pf.hasVignette
                {
                    vi = vi + ( pf.vignette - vi ) * w
                }
                k = k + 1
            }
            st.brightness = br
            st.saturation = sa
            st.vignette = vi
            st.contributing = cap
        }
        Memory.free( inPtr )
        Memory.free( outPtr )
        ret st
    }
}
