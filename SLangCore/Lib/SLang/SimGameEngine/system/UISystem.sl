import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# UISystem - UI pointer event dispatch (P5, doc/08 §4).
# Host feeds screen points to the query-style API; event hooks are named-
# dispatched via SystemSimEngineCallHook/CallHook1 (cross-module slb base
# CallVirt does not dispatch consumer overrides, doc/10 §6):
#   dispatchPointerMove(scene, x, y) : onPointerEnter / onPointerExit
#   dispatchPointerDown(scene, x, y) : onPointerDown(pos) + onSelect
#   dispatchPointerUp(scene, x, y)   : onPointerUp(pos) + onClick (same body)
#   dispatchDrag(dx, dy)             : onDrag(delta) while pressed
#   dispatchScroll(delta)            : onScroll(delta) on hovered
# Hit rules (doc/08 §4): raycastTarget=true AND rectTransform assigned;
# interactable=false still receives Enter/Exit but not Down/Up/Click/Drag/
# Scroll; among multiple hits at one point the LAST-DRAWN wins (last in
# tree pre-order).
# ============================================================================
public class UISystem
{
    public UIBehaviour hovered = null
    public UIBehaviour pressed = null
    public UIBehaviour selected = null

    # pick: explicit stack walk (parent-first = draw order), last hit wins
    UIBehaviour pick( Scene scene, Float32 x, Float32 y )
    {
        UIBehaviour hit = null
        if scene == null
        {
            ret hit
        }
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
            if cur.getActiveInHierarchy() && cur.pendingDestroy == false
            {
                UIBehaviour ui = cur.getComponent<UIBehaviour>()
                if ui != null && ui.raycastTarget
                {
                    Float32_2 p = Float32_2( x, y )
                    if ui.hitTest( p )
                    {
                        hit = ui
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
        ret hit
    }

    # pointer move: Enter/Exit (sent regardless of interactable, doc/08 §4)
    public Int32 dispatchPointerMove( Scene scene, Float32 x, Float32 y )
    {
        UIBehaviour hit = this.pick( scene, x, y )
        Int32 events = 0
        if hit != this.hovered
        {
            if this.hovered != null
            {
                SystemSimEngineCallHook( this.hovered, "onPointerExit" )
                events = events + 1
            }
            if hit != null
            {
                SystemSimEngineCallHook( hit, "onPointerEnter" )
                events = events + 1
            }
            this.hovered = hit
        }
        ret events
    }

    # pointer down: Down + selection switch (interactable gates the hooks)
    public Int32 dispatchPointerDown( Scene scene, Float32 x, Float32 y )
    {
        UIBehaviour hit = this.pick( scene, x, y )
        Int32 events = 0
        if hit != null
        {
            this.pressed = hit
            if hit.interactable
            {
                Float32_2 p = Float32_2( x, y )
                SystemSimEngineCallHook1( hit, "onPointerDown", p )
                events = events + 1
            }
            if hit != this.selected
            {
                if this.selected != null
                {
                    SystemSimEngineCallHook( this.selected, "onDeselect" )
                    events = events + 1
                }
                this.selected = hit
                if hit.interactable
                {
                    SystemSimEngineCallHook( hit, "onSelect" )
                    events = events + 1
                }
            }
        }
        ret events
    }

    # pointer up: Up always (on pressed, if it was interactable);
    # Click only when pressed is still the hit body at release
    public Int32 dispatchPointerUp( Scene scene, Float32 x, Float32 y )
    {
        Int32 events = 0
        UIBehaviour p = this.pressed
        if p != null
        {
            UIBehaviour hit = this.pick( scene, x, y )
            if p.interactable
            {
                Float32_2 pos = Float32_2( x, y )
                SystemSimEngineCallHook1( p, "onPointerUp", pos )
                events = events + 1
                bool same = hit == p
                if same
                {
                    SystemSimEngineCallHook1( p, "onClick", pos )
                    events = events + 1
                }
            }
            this.pressed = null
        }
        ret events
    }

    # drag while pressed (screen-space delta, doc/08 §7.5)
    public Int32 dispatchDrag( Float32 dx, Float32 dy )
    {
        UIBehaviour p = this.pressed
        if p != null && p.interactable
        {
            Float32_2 d = Float32_2( dx, dy )
            SystemSimEngineCallHook1( p, "onDrag", d )
            ret 1
        }
        ret 0
    }

    # scroll to hovered body
    public Int32 dispatchScroll( Float32 delta )
    {
        UIBehaviour h = this.hovered
        if h != null && h.interactable
        {
            SystemSimEngineCallHook1( h, "onScroll", delta )
            ret 1
        }
        ret 0
    }
}