import Core;
import Std;
import Math;
import SLangRender;

# Unity 式场景管理门面（doc/19）：按路径加载 scene.json + 脚本挂载 +
# 持有 Application 驱动帧循环 + 把运行时场景导出回 JSON。
# 消费方：sm.registerScript(name, factory); sm.load(path); sm.tick(-1)
#
# Additive 子场景（2026-11-19，Unity LoadSceneMode.Additive 语义）：
#   sm.loadAdditive(path) / sm.loadAdditiveText(text) —— 子场景根节点
#   **并入 activeScene**（主场景内容不释放、不卸载），多个子场景共存且
#   一并参与帧循环；sm.unloadAdditive(name) 只销毁对应子场景的节点。
#   子场景名 = scene.json 的 name 字段（同名单例，重复加载报错）；
#   单模式 load()/loadText() 会清空全部子场景登记（Unity 单模式语义）。
public class SceneManager
{
    List<string> _scriptNames = null
    List<Function> _scriptFactories = null
    SceneImporter _importer = null
    # 子场景登记（名字 → 并入 activeScene 的根节点集，卸载按名单销毁）
    List<string> _subNames = null
    List<Array<GameObject>> _subRoots = null

    public Application app = null
    public Scene activeScene = null
    public string lastError = ""
    public bool ok = false
    public Int32 nodeCount = 0
    public Int32 scriptCount = 0

    public void _init_()
    {
        this._scriptNames = List<string>( 8 )
        this._scriptFactories = List<Function>( 8 )
        this._subNames = List<string>( 4 )
        this._subRoots = List<Array<GameObject>>( 4 )
        this._importer = SceneImporter()
        this.app = Application()
        this.app.init()
        this.activeScene = this.app.activeScene
        this.lastError = ""
        this.ok = false
    }

    # name = scene.json 的 Script 组件 script 字段；factory 形态
    # void(JsonValue cfg, ScriptResult out)——从 cfg 读自定义参数，把创建的
    # Behaviour 写进 out.value（由 SceneImporter 挂到节点）。
    public void registerScript( string name, Function factory )
    {
        if name == null || name.length == 0 || factory == null
        {
            ret
        }
        if this._scriptNames.indexOf( name ) >= 0
        {
            ret
        }
        this._scriptNames.add( name )
        this._scriptFactories.add( factory )
        this._importer.registerScript( name, factory )
    }

    public Int32 scriptTypeCount()
    {
        ret this._scriptNames.length
    }

    # 按路径加载并激活；失败 lastError 说明原因，返回 null
    public Scene load( string path )
    {
        if path == null || path.length == 0
        {
            this.lastError = "empty path"
            this.ok = false
            ret null
        }
        ImportReport rep = this._importer.loadFile( path )
        if !rep.ok
        {
            this.lastError = rep.lastError
            this.ok = false
            ret null
        }
        Scene s = rep.scene
        if s == null
        {
            this.lastError = "scene is null"
            this.ok = false
            ret null
        }
        this.activeScene = s
        this.app.loadScene( s )
        # 单模式加载：清空子场景登记（旧 activeScene 连同并入的子场景一并
        # 被替换——Unity LoadScene 单模式语义）
        this._subNames.clear()
        this._subRoots.clear()
        this.nodeCount = rep.nodeCount
        this.scriptCount = rep.scriptCount
        this.lastError = ""
        this.ok = true
        ret s
    }

    # 内存文本加载（测试 / 网络下发，无需落盘）
    public Scene loadText( string text )
    {
        if text == null || text.length == 0
        {
            this.lastError = "empty scene text"
            this.ok = false
            ret null
        }
        ImportReport rep = this._importer.parseCore( 1, text )
        if !rep.ok
        {
            this.lastError = rep.lastError
            this.ok = false
            ret null
        }
        Scene s = rep.scene
        if s == null
        {
            this.lastError = "scene is null"
            this.ok = false
            ret null
        }
        this.activeScene = s
        this.app.loadScene( s )
        this._subNames.clear()
        this._subRoots.clear()
        this.nodeCount = rep.nodeCount
        this.scriptCount = rep.scriptCount
        this.lastError = ""
        this.ok = true
        ret s
    }

    # ── Additive 子场景（Unity LoadSceneMode.Additive 语义）────────────
    # 子场景根节点并入 activeScene：主场景内容不释放、不卸载；子场景的
    # Behaviour/物理/动画经 activeScene 照常参与帧循环。子场景名取
    # scene.json 的 name（同名单例，重复加载报错）。

    public Int32 subSceneCount()
    {
        ret this._subNames.length
    }

    public string subSceneName( Int32 index )
    {
        if index < 0 || index >= this._subNames.length
        {
            ret ""
        }
        ret this._subNames[index]
    }

    public bool isSubLoaded( string name )
    {
        if name == null
        {
            ret false
        }
        ret this._subNames.indexOf( name ) >= 0
    }

    public Scene loadAdditive( string path )
    {
        if path == null || path.length == 0
        {
            this.lastError = "empty path"
            ret null
        }
        if this.activeScene == null
        {
            this.lastError = "no active scene"
            ret null
        }
        ImportReport rep = this._importer.loadFile( path )
        if !rep.ok
        {
            this.lastError = rep.lastError
            ret null
        }
        ret this._adoptSub( rep )
    }

    public Scene loadAdditiveText( string text )
    {
        if text == null || text.length == 0
        {
            this.lastError = "empty scene text"
            ret null
        }
        if this.activeScene == null
        {
            this.lastError = "no active scene"
            ret null
        }
        ImportReport rep = this._importer.parseCore( 1, text )
        if !rep.ok
        {
            this.lastError = rep.lastError
            ret null
        }
        ret this._adoptSub( rep )
    }

    Scene _adoptSub( ImportReport rep )
    {
        Scene sub = rep.scene
        if sub == null
        {
            this.lastError = "scene is null"
            ret null
        }
        string nm = sub.name
        if this._subNames.indexOf( nm ) >= 0
        {
            this.lastError = "sub scene already loaded: " + nm
            ret null
        }
        Array<GameObject> roots = sub.roots()
        Int32 i = 0
        Int32 n = roots.length
        while i < n
        {
            GameObject r = roots[i]
            if r != null
            {
                this.activeScene.addRoot( r )
                this._rewalkScene( r, this.activeScene )
            }
            i = i + 1
        }
        this._subNames.add( nm )
        this._subRoots.add( roots )
        this.nodeCount = this.nodeCount + rep.nodeCount
        this.scriptCount = this.scriptCount + rep.scriptCount
        this.lastError = ""
        ret sub
    }

    # 子树 _scene 重指（销毁登记/摘树要落到 activeScene，不能留在被
    # 弃用的装载临时 Scene 上）
    void _rewalkScene( GameObject go, Scene to )
    {
        go._scene = to
        Int32 j = 0
        Int32 m = go.childCount
        while j < m
        {
            GameObject ch = go.getChild( j )
            if ch != null
            {
                this._rewalkScene( ch, to )
            }
            j = j + 1
        }
    }

    # 卸载子场景：只销毁该子场景并入的根子树（延迟销毁链复用——
    # destroy 登记 → processDestroys 帧级收口），主场景内容不动
    public bool unloadAdditive( string name )
    {
        Int32 idx = this._subNames.indexOf( name )
        if idx < 0
        {
            this.lastError = "sub scene not loaded: " + name
            ret false
        }
        Array<GameObject> roots = this._subRoots[idx]
        Int32 i = 0
        Int32 n = roots.length
        while i < n
        {
            GameObject r = roots[i]
            if r != null && !r.pendingDestroy
            {
                this.activeScene.destroy( r )
            }
            i = i + 1
        }
        this.activeScene.processDestroys()
        this._subNames.removeAt( idx )
        this._subRoots.removeAt( idx )
        this.lastError = ""
        ret true
    }

    # 导出（scene=null 走 activeScene）
    public bool save( string path, Scene scene )
    {
        Scene target = scene
        if target == null
        {
            target = this.activeScene
        }
        if target == null
        {
            this.lastError = "no active scene"
            ret false
        }
        bool done = SceneExporter.save( target, path )
        if !done
        {
            this.lastError = "write failed: " + path
        }
        ret done
    }

    public string toJson( Scene scene )
    {
        Scene target = scene
        if target == null
        {
            target = this.activeScene
        }
        if target == null
        {
            ret ""
        }
        string text = SceneExporter.toJson( target )
        ret text
    }

    # rawDt=-1 = 引擎单调钟实测（与 Application.tick 同语义）
    public void tick( Float32 rawDt )
    {
        this.app.tick( rawDt )
    }

    public void unload()
    {
        this.app.shutdown()
        this.activeScene = null
        this.ok = false
        this.nodeCount = 0
        this.scriptCount = 0
        this._subNames.clear()
        this._subRoots.clear()
    }

    override string toString()
    {
        string sn = "null"
        if this.activeScene != null
        {
            sn = this.activeScene.name
        }
        string n = this.nodeCount.toString()
        string sc = this.scriptCount.toString()
        string sb = this.subSceneCount().toString()
        ret String.toFormat( "SceneManager(scene={0}, nodes={1}, scripts={2}, subs={3}, ok={4})",
            sn, n, sc, sb, this.ok.toString() )
    }
}
