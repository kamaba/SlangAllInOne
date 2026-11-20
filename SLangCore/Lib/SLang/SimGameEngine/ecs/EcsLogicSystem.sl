import Core;
import Std;

# ============================================================================
# EcsLogicSystem — 集中逻辑系统（doc/20 §3）
# ----------------------------------------------------------------------------
# 全部 EcsLogic 的单一调度中心：按 order 稳定插入登记，一帧内统一跑
# fixedUpdate / update / lateUpdate，节点不再逐 Behaviour 派发。
# 资格：组件启用 + entity 有效 + entity 未待销毁 + 层级激活。
# ============================================================================

public class EcsLogicSystem
{
    List<EcsLogic> _items = List<EcsLogic>( 16 )
    List<Int32> _orders = List<Int32>( 16 )
    List<bool> _started = List<bool>( 16 )
    List<bool> _enabledHooks = List<bool>( 16 )

    public Int32 updateCount = 0
    public Int32 lateUpdateCount = 0
    public Int32 fixedUpdateCount = 0

    public Int32 logicCount()
    {
        ret this._items.length
    }

    public EcsLogic logicAt( Int32 idx )
    {
        if idx < 0 || idx >= this._items.length
        {
            ret null
        }
        ret this._items[idx]
    }

    # 登记：order 升序稳定插入；立即 awake，激活态下补 onEnable
    public void add( EcsLogic logic, GameObject owner )
    {
        if logic == null
        {
            ret
        }
        logic.attachTo( owner )
        Int32 pos = this._items.length
        Int32 k = pos - 1
        while k > 0 - 1
        {
            Int32 other = this._orders[k]
            if other > logic.order
            {
                pos = k
                k = k - 1
            }
            else
            {
                k = 0 - 1
            }
        }
        this._items.insert( pos, logic )
        this._orders.insert( pos, logic.order )
        this._started.insert( pos, false )
        bool alive = this._alive( owner )
        this._enabledHooks.insert( pos, alive )
        SystemSimEngineCallHook( logic, "awake" )
        if alive
        {
            SystemSimEngineCallHook( logic, "onEnable" )
        }
    }

    # 注销：派发 onDisable / dispose
    public bool remove( EcsLogic logic )
    {
        Int32 idx = this._items.indexOf( logic )
        if idx < 0
        {
            ret false
        }
        EcsLogic item = this._items[idx]
        if this._enabledHooks[idx]
        {
            SystemSimEngineCallHook( item, "onDisable" )
        }
        SystemSimEngineCallHook( item, "dispose" )
        this._items.removeAt( idx )
        this._orders.removeAt( idx )
        this._started.removeAt( idx )
        this._enabledHooks.removeAt( idx )
        ret true
    }

    public void clear()
    {
        Int32 i = this._items.length - 1
        while i > 0 - 1
        {
            EcsLogic item = this._items[i]
            if this._enabledHooks[i]
            {
                SystemSimEngineCallHook( item, "onDisable" )
            }
            SystemSimEngineCallHook( item, "dispose" )
            i = i - 1
        }
        this._items.clear()
        this._orders.clear()
        this._started.clear()
        this._enabledHooks.clear()
    }

    public void fixedUpdate()
    {
        Int32 i = 0
        Int32 n = this._items.length
        while i < n
        {
            EcsLogic b = this._items[i]
            if this._canRun( i )
            {
                SystemSimEngineCallHook( b, "fixedUpdate" )
                this.fixedUpdateCount = this.fixedUpdateCount + 1
            }
            i = i + 1
        }
    }

    public void update( Float32 dt )
    {
        Int32 i = 0
        Int32 n = this._items.length
        while i < n
        {
            EcsLogic b = this._items[i]
            if this._canRun( i )
            {
                if !this._started[i]
                {
                    this._started[i] = true
                    SystemSimEngineCallHook( b, "start" )
                }
                SystemSimEngineCallHook( b, "update" )
                this.updateCount = this.updateCount + 1
            }
            i = i + 1
        }
    }

    public void lateUpdate( Float32 dt )
    {
        Int32 i = 0
        Int32 n = this._items.length
        while i < n
        {
            EcsLogic b = this._items[i]
            if this._canRun( i )
            {
                SystemSimEngineCallHook( b, "lateUpdate" )
                this.lateUpdateCount = this.lateUpdateCount + 1
            }
            i = i + 1
        }
    }

    bool _canRun( Int32 idx )
    {
        EcsLogic b = this._items[idx]
        bool en = SystemSimEngineGetEnabled( b )
        if !en
        {
            ret false
        }
        GameObject go = b.entity
        ret this._alive( go )
    }

    bool _alive( GameObject go )
    {
        if go == null
        {
            ret false
        }
        if go.pendingDestroy
        {
            ret false
        }
        ret go.getActiveInHierarchy()
    }
}
