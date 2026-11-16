# 行为组件基类：提供标准生命周期钩子，子类按需 override。
# 继承 Std 库的 Component。
import Std;
public class Behaviour extends Component
{
    public bool isEnabled = true

    # 宿主节点（GameObject.addComponent 挂载时回填，不得手工改；doc/02 §3）
    public GameObject owner = null

    # start() 是否已执行（Application 首次 update 前置调用一次，内部标记）
    public bool started = false

    # ── 生命周期（子类 override）────────────────────────
    # 创建后立即调用一次
    public void awake()
    {
    }

    # 第一帧更新前调用一次
    public void start()
    {
    }

    # 每帧更新
    public void update()
    {
    }

    # 每帧在所有 update 之后调用
    public void lateUpdate()
    {
    }

    # 固定步长更新（物理 / 稳定逻辑）
    public void fixedUpdate()
    {
    }

    # 启用 / 禁用时触发
    public void onEnable()
    {
    }

    public void onDisable()
    {
    }

    # 销毁前清理
    public void dispose()
    {
    }

    # ── 启用控制 ─────────────────────────────────────────
    # isEnabled 读写与 onEnable/onDisable 派发统一走 C VM 系统调用：
    # 跨模块 slb 基类在消费方派生实例上的字段/虚表存在槽位错位
    # （SimEngineTest 实证，doc/10 §6），C 侧按名访问无此问题。
    public void setEnabled( bool value )
    {
        SystemSimEngineSetEnabled( this, value )
    }

    public bool getEnabled()
    {
        ret SystemSimEngineGetEnabled( this )
    }

    override string toString()
    {
        ret String.toFormat( "Behaviour(enabled={0})", this.isEnabled.toString() )
    }
}
