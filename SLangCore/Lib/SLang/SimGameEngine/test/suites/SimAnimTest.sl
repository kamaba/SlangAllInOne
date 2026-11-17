import SimGameEngine;
import SLangRender;
import Math;
import SLangRender;
import Std;
import SLangRender;

# ============================================================================
# SimAnimTest — P5 动画/特效/UI/探针冒烟（doc/06/07/08）
# ----------------------------------------------------------------------------
# 覆盖：AnimationClip 轨道采样（首尾钳制 + 线性插值）、Animation 播放推进
# （loop 回绕 / 非 loop 停尾 / evaluate 写回 Transform）、AnimSystem 收集与
# 自动推进、Effect 时间线（loop 回绕 / 自动停 / autoDestroy 延迟销毁）、
# Probe 数据结构、RectTransform 布局与 hitTest、UIBehaviour 命中委托、
# UISystem pick（后绘制优先）与指针事件派发（Enter/Exit/Down/Click/Drag/
# Scroll + interactable 门控 + raycastTarget 排除）。
# 坑规避（doc/10 §6）：List 下标先落局部变量；reverse 循环 > 0 - 1；
# Int32 字段读不做 == 常量断言（用 < 形态或不测）；无 continue。
# ============================================================================
public class SimAnimTest
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

    static bool near( Float32 a, Float32 b )
    {
        Float32 d = a - b
        if d < 0.0f
        {
            d = 0.0f - d
        }
        ret d < 0.001f
    }

    static Application makeWorld()
    {
        Application app = Application()
        app.init()
        app.animSystem = AnimSystem()
        ret app
    }

    # 位置轨道样例 clip：duration 1s，position 0→(10,0,0)
    static AnimationClip makePosClip()
    {
        AnimationClip clip = AnimationClip()
        clip.duration = 1.0f
        clip.loop = false
        AnimationTrack tk = clip.addTrack( "position" )
        Float32_3 k0 = Float32_3( 0.0f, 0.0f, 0.0f )
        Float32_3 k1 = Float32_3( 10.0f, 0.0f, 0.0f )
        tk.addKey( 0.0f, k0 )
        tk.addKey( 1.0f, k1 )
        ret clip
    }

    static GameObject makeNode( Scene scene, string name, Float32 x )
    {
        GameObject go = scene.createObject( name )
        Transform t = go.transform
        t.setPosition( Float32_3( x, 0.0f, 0.0f ) )
        ret go
    }

    # ── AN1 AnimationTrack 采样 ────────────────────────
    static void testTrackSample()
    {
        AnimationTrack tk = AnimationTrack()
        check( tk.keyCount() == 0, "AN1a empty keyCount" )
        Float32_3 k0 = Float32_3( 0.0f, 0.0f, 0.0f )
        Float32_3 k1 = Float32_3( 10.0f, 20.0f, 30.0f )
        tk.addKey( 0.0f, k0 )
        tk.addKey( 1.0f, k1 )
        check( tk.keyCount() == 2, "AN1b keyCount after add" )
        check( tk.binding == "position", "AN1c binding read-back" )

        Float32_3 v = Float32_3.zero()
        bool ok = tk.sample( 0.0f - 1.0f, v )
        check( ok && near( v.x, 0.0f ), "AN1d sample before first clamps to first" )
        ok = tk.sample( 2.0f, v )
        check( ok && near( v.x, 10.0f ), "AN1e sample after last clamps to last" )
        ok = tk.sample( 0.25f, v )
        check( ok && near( v.x, 2.5f ), "AN1f sample mid x interpolated" )
        check( near( v.y, 5.0f ) && near( v.z, 7.5f ), "AN1g sample mid y/z interpolated" )
    }

    # ── AN2 Animation 播放推进 ─────────────────────────
    static void testAnimationPlayback()
    {
        # 非 loop：到尾停住
        AnimationClip clip = makePosClip()
        Animation anim = Animation()
        anim.clip = clip
        check( anim.playing == false, "AN2a starts not playing" )
        anim.play()
        check( anim.playing, "AN2b play sets playing" )
        bool still = anim.advance( 0.5f )
        check( still && near( anim.time, 0.5f ), "AN2c advance mid" )
        still = anim.advance( 1.0f )
        check( still == false, "AN2d non-loop returns false at end" )
        check( anim.playing == false, "AN2e non-loop stops at end" )
        check( near( anim.time, 1.0f ), "AN2f time clamped to duration" )

        # loop：回绕
        AnimationClip lclip = makePosClip()
        lclip.loop = true
        Animation lanim = Animation()
        lanim.clip = lclip
        lanim.play()
        still = lanim.advance( 1.5f )
        check( still && near( lanim.time, 0.5f ), "AN2g loop wraps time" )
        check( lanim.playing, "AN2h loop keeps playing" )

        # 无 clip：advance 短路
        Animation empty = Animation()
        check( empty.advance( 0.1f ) == false, "AN2i advance without clip short-circuits" )
    }

    # ── AN3 evaluate 写回 Transform ────────────────────
    static void testEvaluate()
    {
        Application app = Application()
        app.init()
        GameObject go = makeNode( app.activeScene, "An", 0.0f )
        Animation anim = Animation()
        anim.clip = makePosClip()
        go.addComponent( anim )
        anim.play()
        anim.advance( 0.5f )
        anim.evaluate( anim.time )
        Transform t = go.transform
        Float32_3 p = t.localPosition
        check( near( p.x, 5.0f ), "AN3a evaluate writes position x" )
        check( near( p.y, 0.0f ) && near( p.z, 0.0f ), "AN3b evaluate position y/z" )

        # scale / rotationZ 轨道
        AnimationClip clip = AnimationClip()
        clip.duration = 2.0f
        AnimationTrack sk = clip.addTrack( "scale" )
        Float32_3 s0 = Float32_3( 1.0f, 1.0f, 1.0f )
        Float32_3 s1 = Float32_3( 3.0f, 3.0f, 3.0f )
        sk.addKey( 0.0f, s0 )
        sk.addKey( 2.0f, s1 )
        AnimationTrack rk = clip.addTrack( "rotationZ" )
        Float32_3 r0 = Float32_3( 0.0f, 0.0f, 0.0f )
        Float32_3 r1 = Float32_3( 3.14159f, 0.0f, 0.0f )
        rk.addKey( 0.0f, r0 )
        rk.addKey( 2.0f, r1 )
        # 注意：addComponent 同类型去重（P0 语义）——第二个 Animation 须挂
        # 独立节点，复用 t 读侧不受影响（Transform 属节点不属组件）
        GameObject go2 = makeNode( app.activeScene, "An2", 0.0f )
        Animation a2 = Animation()
        a2.clip = clip
        go2.addComponent( a2 )
        a2.play()
        a2.advance( 1.0f )
        a2.evaluate( 1.0f )
        Transform t2 = go2.transform
        Float32_3 sc = t2.localScale
        check( near( sc.x, 2.0f ), "AN3c evaluate writes scale" )
        check( near( t2.localRotationZ, 3.14159f * 0.5f ), "AN3d evaluate writes rotationZ" )
    }

    # ── AN4 AnimSystem 收集与自动推进 ──────────────────
    static void testAnimSystem()
    {
        Application app = makeWorld()
        GameObject go = makeNode( app.activeScene, "A", 0.0f )
        Animation anim = Animation()
        anim.clip = makePosClip()
        go.addComponent( anim )
        anim.play()
        GameObject idle = makeNode( app.activeScene, "B", 0.0f )
        Animation idleAnim = Animation()
        idleAnim.clip = makePosClip()
        idle.addComponent( idleAnim )

        app.tick( 1.0f / 60.0f )
        check( app.animSystem.animCount == 2, "AN4a animSystem collects both" )
        Transform t = go.transform
        Float32_3 p = t.localPosition
        check( p.x > 0.1f, "AN4b playing animation advanced by tick" )
        Transform ti = idle.transform
        Float32_3 pi = ti.localPosition
        check( near( pi.x, 0.0f ), "AN4c non-playing animation untouched" )

        anim.stop()
        app.tick( 1.0f / 60.0f )
        Float32_3 p2 = t.localPosition
        check( near( p2.x - p.x, 0.0f ), "AN4d stopped animation frozen" )
    }

    # ── AN5 Effect 时间线与自动销毁 ────────────────────
    static void testEffect()
    {
        Application app = Application()
        app.init()
        GameObject go = makeNode( app.activeScene, "Fx", 0.0f )
        Effect fx = Effect()
        fx.duration = 1.0f
        fx.loop = true
        go.addComponent( fx )
        fx.play()
        bool still = fx.advance( 1.5f )
        check( still && near( fx.elapsed, 0.5f ), "AN5a loop effect wraps" )
        fx.loop = false
        still = fx.advance( 1.0f )
        check( still == false, "AN5b non-loop effect stops" )
        check( fx.playing == false, "AN5c non-loop effect playing=false" )

        # autoDestroy：播完登记延迟销毁，tick 收口
        GameObject g2 = makeNode( app.activeScene, "FxDie", 0.0f )
        Effect fx2 = Effect()
        fx2.duration = 1.0f
        fx2.autoDestroy = true
        g2.addComponent( fx2 )
        fx2.play()
        fx2.advance( 1.0f )
        check( g2.pendingDestroy, "AN5d autoDestroy registers deferred destroy" )
        app.tick( 1.0f / 60.0f )
        check( app.activeScene.find( "FxDie" ) == null, "AN5e destroyed node gone after tick" )
    }

    # ── AN6 Probe 数据结构 ─────────────────────────────
    static void testProbes()
    {
        LightProbe lp = LightProbe()
        lp.position = Float32_3( 1.0f, 2.0f, 3.0f )
        lp.ambient = 0.5f
        lp.tintColor = Float32_3( 1.0f, 0.9f, 0.8f )
        check( near( lp.position.x, 1.0f ) && near( lp.ambient, 0.5f ), "AN6a LightProbe fields" )
        check( near( lp.tintColor.y, 0.9f ), "AN6b LightProbe tintColor" )

        ReflectionProbe rp = ReflectionProbe()
        rp.bounds = Bounds.fromCenterSize( Float32_3( 0.0f, 5.0f, 0.0f ), Float32_3( 10.0f, 10.0f, 10.0f ) )
        rp.intensity = 1.5f
        check( near( rp.intensity, 1.5f ), "AN6c ReflectionProbe intensity" )
        Float32_3 bc = rp.bounds.center
        check( near( bc.y, 5.0f ), "AN6d ReflectionProbe bounds center" )
        check( rp.cubemapSlot < 0, "AN6e default cubemapSlot unassigned (-1)" )
    }

    # ── AN7 RectTransform 布局与命中 ──────────────────
    static RectTransform makeRect( Float32 x, Float32 y, Float32 w, Float32 h )
    {
        RectTransform rt = RectTransform()
        rt.setAnchoredPosition( Float32_2( x, y ) )
        rt.setSize( w, h )
        ret rt
    }

    static void testRectTransform()
    {
        RectTransform rt = makeRect( 10.0f, 10.0f, 4.0f, 2.0f )
        check( near( rt.width, 4.0f ) && near( rt.height, 2.0f ), "AN7a width/height getters" )
        Float32_2 tl = rt.topLeft
        check( near( tl.x, 8.0f ) && near( tl.y, 9.0f ), "AN7b topLeft with pivot 0.5" )
        check( rt.hitTest( Float32_2( 10.0f, 10.0f ) ), "AN7c hitTest inside" )
        check( rt.hitTest( Float32_2( 20.0f, 10.0f ) ) == false, "AN7d hitTest outside" )
        check( rt.hitTest( Float32_2( 8.5f, 9.5f ) ), "AN7e hitTest near corner inside" )

        RectTransform c = rt.cloneRect()
        c.setSize( 100.0f, 100.0f )
        check( near( rt.width, 4.0f ), "AN7f cloneRect independent" )

        rt.setPivot( Float32_2( 2.0f, 2.0f ) )
        check( near( rt.pivot.x, 1.0f ), "AN7g setPivot clamps to 1" )

        rt.setAnchor( Float32_2( 0.25f, 0.25f ) )
        check( near( rt.anchorMin.x, 0.25f ) && near( rt.anchorMax.y, 0.25f ), "AN7h setAnchor both corners" )

        rt.stretch()
        check( near( rt.anchorMax.x, 1.0f ) && near( rt.sizeDelta.y, 0.0f ), "AN7i stretch resets" )
    }

    # ── AN8 UIBehaviour 命中委托 ───────────────────────
    static void testUIBehaviourHit()
    {
        UIBehaviour ui = UIBehaviour()
        check( ui.hitTest( Float32_2( 0.0f, 0.0f ) ) == false, "AN8a null rectTransform returns false" )
        ui.rectTransform = makeRect( 0.0f, 0.0f, 4.0f, 4.0f )
        check( ui.hitTest( Float32_2( 1.0f, 1.0f ) ), "AN8b delegates to rectTransform" )
        check( ui.hitTest( Float32_2( 9.0f, 9.0f ) ) == false, "AN8c outside returns false" )
        check( ui.raycastTarget && ui.interactable, "AN8d defaults on" )
        ui.setInteractable( false )
        check( ui.interactable == false, "AN8e setInteractable" )
    }

    # ── AN9 UISystem pick 与事件派发 ───────────────────
    static UIBehaviour addUI( Scene scene, string name, Float32 x, Float32 y, bool raycast )
    {
        GameObject go = scene.createObject( name )
        UIBehaviour ui = UIBehaviour()
        ui.raycastTarget = raycast
        go.addComponent( ui )
        ui.rectTransform = makeRect( x, y, 4.0f, 4.0f )
        ret ui
    }

    static void testUISystem()
    {
        Application app = Application()
        app.init()
        Scene scene = app.activeScene
        UISystem ui = UISystem()

        # 后绘制优先：B 后建（树序在后），同点命中 B
        UIBehaviour a = addUI( scene, "A", 10.0f, 10.0f, true )
        UIBehaviour b = addUI( scene, "B", 10.0f, 10.0f, true )
        UIBehaviour hit = ui.pick( scene, 10.0f, 10.0f )
        check( hit == b, "AN9a pick last-drawn wins" )
        check( ui.pick( scene, 50.0f, 50.0f ) == null, "AN9b pick miss null" )

        # raycastTarget=false 不参与命中
        UIBehaviour c = addUI( scene, "C", 10.0f, 10.0f, false )
        check( ui.pick( scene, 10.0f, 10.0f ) == b, "AN9c raycastTarget=false skipped" )

        # Enter/Exit
        Int32 ev = ui.dispatchPointerMove( scene, 10.0f, 10.0f )
        check( ev == 1 && ui.hovered == b, "AN9d pointer move fires Enter" )
        ev = ui.dispatchPointerMove( scene, 10.0f, 10.0f )
        check( ev == 0, "AN9e same position no event" )
        ev = ui.dispatchPointerMove( scene, 50.0f, 50.0f )
        check( ev == 1 && ui.hovered == null, "AN9f leaving fires Exit" )

        # Down/Up/Click（同体抬起 = Click）
        ui.dispatchPointerMove( scene, 10.0f, 10.0f )
        ev = ui.dispatchPointerDown( scene, 10.0f, 10.0f )
        check( ev == 2 && ui.pressed == b && ui.selected == b, "AN9g down fires Down+Select" )
        ev = ui.dispatchPointerUp( scene, 10.0f, 10.0f )
        check( ev == 2, "AN9h up on same body fires Up+Click" )
        check( ui.pressed == null, "AN9i pressed cleared" )

        # 拖拽 / 滚轮（须 pressed / hovered）
        ui.dispatchPointerDown( scene, 10.0f, 10.0f )
        ev = ui.dispatchDrag( 1.0f, 2.0f )
        check( ev == 1, "AN9j drag while pressed" )
        ev = ui.dispatchScroll( 1.0f )
        check( ev == 1, "AN9k scroll to hovered" )
        ui.dispatchPointerUp( scene, 50.0f, 50.0f )
        ev = ui.dispatchDrag( 1.0f, 1.0f )
        check( ev == 0, "AN9l no drag after release" )

        # interactable=false：Down/Up/Click/Drag/Scroll/Select 门控；
        # Enter/Exit 与旧选中 Deselect 仍发（doc/08 §4 规则）
        UIBehaviour d = addUI( scene, "D", 10.0f, 10.0f, true )
        d.setInteractable( false )
        ev = ui.dispatchPointerMove( scene, 10.0f, 10.0f )
        check( ev == 2 && ui.hovered == d, "AN9m non-interactable gets Exit+Enter" )
        ev = ui.dispatchPointerDown( scene, 10.0f, 10.0f )
        check( ev == 1 && ui.pressed == d && ui.selected == d, "AN9n gates Down/Select, old Deselect still fires" )
    }

    # ── AN10 钩子按名派发到消费方 override ────────────
    static void testHookDispatch()
    {
        Application app = Application()
        app.init()
        Scene scene = app.activeScene
        GameObject go = scene.createObject( "Btn" )
        AnimButton btn = AnimButton()
        go.addComponent( btn )
        btn.rectTransform = makeRect( 10.0f, 10.0f, 4.0f, 4.0f )
        UISystem ui = UISystem()
        ui.dispatchPointerMove( scene, 10.0f, 10.0f )
        check( btn.enterCount > 0, "AN10a onPointerEnter named-dispatch to override" )
        ui.dispatchPointerDown( scene, 10.0f, 10.0f )
        check( btn.downCount > 0, "AN10b onPointerDown received" )
        check( near( btn.lastX, 10.0f ), "AN10c onPointerDown payload x" )
        ui.dispatchPointerUp( scene, 10.0f, 10.0f )
        check( btn.clickCount > 0, "AN10d onClick same-body" )
    }

    public static Int32 passCount()
    {
        ret _pass
    }

    public static Int32 failCount()
    {
        ret _fail
    }

    public static void run()
    {
        testTrackSample()
        testAnimationPlayback()
        testEvaluate()
        testAnimSystem()
        testEffect()
        testProbes()
        testRectTransform()
        testUIBehaviourHit()
        testUISystem()
        testHookDispatch()
        Console.println( "SimAnimTest PASS=" + _pass.toString() + " FAIL=" + _fail.toString() )
    }
}

# 测试用按钮：消费方模块 override（钩子经 SystemSimEngineCallHook 按名派发）
public class AnimButton extends UIBehaviour
{
    public Int32 enterCount = 0
    public Int32 downCount = 0
    public Int32 clickCount = 0
    public Float32 lastX = 0.0f
    public Float32 lastY = 0.0f

    override void onPointerEnter()
    {
        this.enterCount = this.enterCount + 1
    }

    override void onPointerDown( Float32_2 position )
    {
        this.downCount = this.downCount + 1
        this.lastX = position.x
        this.lastY = position.y
    }

    override void onClick( Float32_2 position )
    {
        this.clickCount = this.clickCount + 1
    }
}
