# 引擎入口门面：无头帧循环（doc/09）。
#
# 职责：时间推进 -> fixedUpdate×N -> start/update -> lateUpdate ->
# 变换刷新 -> 帧尾延迟销毁收口。渲染提交（可见性收集 / 合批 /
# RenderObject 同步 / 相机灯光下发，doc/09 §2 步骤 7~10）随 P2 合批器
# 落地后接入；当前 tick 为无头循环（CI / 烘焙 / 逻辑验证可用）。
#
# 宿主接入（doc/09 §3）：QT QTimer(16) 回调里调 app.tick(0.016f)；
# 命令行 / 无头循环直接 while 调 tick。引擎层不绑定窗口系统。
import Std;
import Math;
public class Application
{
    # 当前激活场景（帧序只遍历它）
    public Scene activeScene = null
    # 暂停：dt=0，update/fixedUpdate 不推进（渲染侧仍可自行刷新画面）
    public bool paused = false
    # 时间缩放（只缩放 dt，固定步长本身不变）
    public Float32 timeScale = 1.0f
    # 固定步长（物理 / 稳定逻辑）
    public Float32 fixedDt = 0.0166667f
    # 单帧 fixedUpdate 上限（防螺旋死亡）
    public Int32 maxFixedSteps = 5
    # 单帧 dt 上限（切后台回来一帧巨量 dt 裁剪）
    public Float32 maxDeltaTime = 0.1f
    # 上帧实际推进量（脚本可读；替代 Time.deltaTime 的 v1 形态）
    public Float32 deltaTime = 0.0f

    Float32 _fixedAcc = 0.0f
    List<Behaviour> _frameBehaviours = null

    # ── 构造 / 生命周期 ──────────────────────────────────
    public void _init_()
    {
        this.activeScene = null
        this.paused = false
        this.timeScale = 1.0f
        this.fixedDt = 1.0f / 60.0f
        this.maxFixedSteps = 5
        this.maxDeltaTime = 0.1f
        this.deltaTime = 0.0f
        this._fixedAcc = 0.0f
        this._frameBehaviours = List<Behaviour>(64)
    }

    # 初始化：建默认场景（渲染后端由调用方按需初始化，本类不绑定 Render）
    public bool init()
    {
        this.activeScene = Scene( "Main" )
        ret true
    }

    # 场景切换：旧场景由调用方负责销毁（destroy 根节点 + processDestroys）；
    # 新场景下一帧 tick 生效。固定步长累加器重置。
    public void loadScene( Scene s )
    {
        this.activeScene = s
        this._fixedAcc = 0.0f
        this._frameBehaviours.clear()
    }

    # ── 一帧（doc/09 §2 无头子集：1~6 + 11 步）──────────
    public void tick( Float32 rawDt )
    {
        # 1) 时间推进：上限裁剪 + 暂停 + timeScale
        Float32 dt = rawDt
        if dt > this.maxDeltaTime
        {
            dt = this.maxDeltaTime
        }
        if dt < 0.0f
        {
            dt = 0.0f
        }
        if this.paused
        {
            dt = 0.0f
        }
        dt = dt * this.timeScale
        this.deltaTime = dt

        if this.activeScene == null
        {
            ret
        }

        # 帧序遍历集：深度优先父先子后收集
        this._frameBehaviours.clear()
        this.activeScene.collectBehaviours( this._frameBehaviours )

        # 3) fixedUpdate ×N（固定步长累加器）
        Float32 acc = this._fixedAcc + dt
        Int32 steps = 0
        while acc >= this.fixedDt && steps < this.maxFixedSteps
        {
            Int32 i = 0
            Int32 n = this._frameBehaviours.length
            while i < n
            {
                Behaviour b = this._frameBehaviours[i]
                if this._canUpdate( b )
                {
                    SystemSimEngineCallHook( b, "fixedUpdate" )
                }
                i = i + 1
            }
            acc = acc - this.fixedDt
            steps = steps + 1
        }
        if steps >= this.maxFixedSteps && acc > this.fixedDt
        {
            acc = 0.0f
        }
        this._fixedAcc = acc

        # 4) start（首次）+ update：按树序（dt=0 / paused 时逻辑不推进）
        if dt > 0.0f
        {
            Int32 i = 0
            Int32 n = this._frameBehaviours.length
            while i < n
            {
                Behaviour b = this._frameBehaviours[i]
                if this._canUpdate( b )
                {
                    if !b.started
                    {
                        b.started = true
                        SystemSimEngineCallHook( b, "start" )
                    }
                    SystemSimEngineCallHook( b, "update" )
                }
                i = i + 1
            }

            # 5) lateUpdate：相机跟随等「等别人更新完」的逻辑
            i = 0
            while i < n
            {
                Behaviour b = this._frameBehaviours[i]
                if this._canUpdate( b )
                {
                    SystemSimEngineCallHook( b, "lateUpdate" )
                }
                i = i + 1
            }
        }

        # 6) 变换刷新（一致性入口）
        this.activeScene.updateTransforms()

        # 11) 帧尾：延迟销毁收口
        this.activeScene.processDestroys()
    }

    # ── 收尾 ─────────────────────────────────────────────
    # 销毁激活场景全部根子树（dispose -> 摘树），重置累加器
    public void shutdown()
    {
        if this.activeScene != null
        {
            Array<GameObject> roots = this.activeScene.roots()
            Int32 i = 0
            Int32 n = roots.length
            while i < n
            {
                GameObject root = roots[i]
                if root != null
                {
                    root.destroy()
                }
                i = i + 1
            }
            this.activeScene.processDestroys()
        }
        this.activeScene = null
        this._fixedAcc = 0.0f
        this._frameBehaviours.clear()
        this.deltaTime = 0.0f
    }

    # ── 内部 ─────────────────────────────────────────────
    # 更新资格：组件启用 + 节点激活 + 未挂待销毁
    bool _canUpdate( Behaviour b )
    {
        if b == null
        {
            ret false
        }
        bool en = SystemSimEngineGetEnabled( b )
        if en == false
        {
            ret false
        }
        GameObject owner = b.owner
        if owner == null
        {
            ret false
        }
        if owner.pendingDestroy
        {
            ret false
        }
        ret owner.getActiveInHierarchy()
    }

    override string toString()
    {
        string sceneName = "null"
        if this.activeScene != null
        {
            sceneName = this.activeScene.name
        }
        ret String.toFormat( "Application(scene={0}, paused={1}, timeScale={2})",
            sceneName, this.paused.toString(), this.timeScale.toString() )
    }
}
