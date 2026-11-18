import Core;
import Std;
import Math;
import SLangRender;

# Unity 式场景管理门面（doc/19）：按路径加载 scene.json + 脚本挂载 +
# 持有 Application 驱动帧循环 + 把运行时场景导出回 JSON。
# 消费方：sm.registerScript(name, factory); sm.load(path); sm.tick(-1)
public class SceneManager
{
    List<string> _scriptNames = null
    List<Function> _scriptFactories = null
    SceneImporter _importer = null

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
        this.nodeCount = rep.nodeCount
        this.scriptCount = rep.scriptCount
        this.lastError = ""
        this.ok = true
        ret s
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
        ret String.toFormat( "SceneManager(scene={0}, nodes={1}, scripts={2}, ok={3})",
            sn, n, sc, this.ok.toString() )
    }
}
