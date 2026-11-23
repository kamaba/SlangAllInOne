# ============================================================================
# GameManager — Unity 风格全局主控门面（对外唯一入口）
# ----------------------------------------------------------------------------
# 持有 Application（无头帧循环）+ Systems（渲染/音频/UI 系统），把
# init → 建场景 → tick → sync → frame 收口成一条调用链；宿主只需在
# QTimer 回调里调 update(-1) / sync() / frame(dstPtr)。
# 静态 instance() 全局单例；逻辑层不依赖窗口系统。
# ============================================================================

import Core;
import Std;
import Math;

public class GameManager
{
    static GameManager _instance = null

    Application _app = null
    Systems _systems = null
    Float32 _time = 0.0f
    bool _ready = false
    Int32 _lastSubmitted = 0

    public void _init_()
    {
        this._app = null
        this._systems = null
        this._time = 0.0f
        this._ready = false
        this._lastSubmitted = 0
    }

    public static GameManager instance()
    {
        if GameManager._instance == null
        {
            GameManager._instance = GameManager()
        }
        ret GameManager._instance
    }

    public bool initialize( Int32 width, Int32 height )
    {
        this._app = Application()
        this._app.init()
        this._systems = Systems()
        bool renderOk = this._systems.render.init( width, height )
        this._app.collisionSystem = this._systems.collision
        this._app.audioSystem = this._systems.audio
        this._ready = true
        ret renderOk
    }

    public bool isReady()
    {
        ret this._ready && this._app != null
    }

    public bool renderReady()
    {
        if this._systems == null
        {
            ret false
        }
        ret this._systems.render.ready()
    }

    public Application application()
    {
        ret this._app
    }

    public Systems systems()
    {
        ret this._systems
    }

    public Scene scene()
    {
        if this._app == null
        {
            ret null
        }
        ret this._app.activeScene
    }

    public Scene createScene( string name )
    {
        if this._app == null
        {
            ret null
        }
        Scene s = Scene( name )
        this._app.loadScene( s )
        ret s
    }

    public GameObject instantiate( string name )
    {
        Scene s = this.scene()
        if s == null
        {
            ret null
        }
        ret s.createObject( name )
    }

    public GameObject find( string path )
    {
        Scene s = this.scene()
        if s == null
        {
            ret null
        }
        ret s.find( path )
    }

    public void destroy( GameObject target )
    {
        if target == null
        {
            ret
        }
        target.destroy()
    }

    public void update( Float32 rawDt )
    {
        if this._app == null
        {
            ret
        }
        this._app.tick( rawDt )
        this._time = this._time + this._app.deltaTime
    }

    public void pause()
    {
        if this._app != null
        {
            this._app.paused = true
        }
    }

    public void resume()
    {
        if this._app != null
        {
            this._app.paused = false
        }
    }

    public bool isPaused()
    {
        if this._app == null
        {
            ret true
        }
        ret this._app.paused
    }

    public Float32 elapsedTime()
    {
        ret this._time
    }

    # 场景 → 渲染对象；返回提交对象数（未就绪返回 -1）
    public Int32 sync()
    {
        if this._systems == null || !this.renderReady()
        {
            ret -1
        }
        Scene s = this.scene()
        if s == null
        {
            ret -1
        }
        this._lastSubmitted = this._systems.sync( s, this._time )
        ret this._lastSubmitted
    }

    public Int32 submittedCount()
    {
        ret this._lastSubmitted
    }

    # 出帧到 RGBA8 块（dstPtr = Memory.alloc(w*h*4)）
    public bool frame( Int64 dstPtr )
    {
        if this._systems == null || !this.renderReady()
        {
            ret false
        }
        ret this._systems.frame( this._time, dstPtr )
    }

    public void shutdown()
    {
        if this._systems != null
        {
            this._systems.shutdown()
        }
        if this._app != null
        {
            this._app.shutdown()
        }
        this._ready = false
    }
}
