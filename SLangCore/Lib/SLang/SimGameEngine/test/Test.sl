import SimGameEngine;
import Math;
import Std;

# ============================================================================
# Test — SimGameEngine 测试统一入口（单工程单进程，代替原六套独立工程）
# ----------------------------------------------------------------------------
# 选套方式（改完重新编译运行）：
#   1. 常量开关：改下方 runSuite 的值
#        0 = 全部六套顺序跑（回归口径）
#        1 = SimEngineTest    P0/P1 场景/组件/生命周期/查找
#        2 = SimBatchTest     P2 合批数据层
#        3 = SimCollisionTest P3 碰撞与触发器
#        4 = SimModuleTest    双模块（Render/Audio）共存
#        5 = SimSystemsTest   system/ 层（真实 GL 出帧 + 音频）
#        6 = SimFfiTest       C99 原生库 FFI 绑定（时钟/定时器/节点注册表）
#        7 = SimPhysicsTest   P4 轻量物理（落地/弹跳/帧率一致性/休眠）
#        8 = SimAnimTest      P5 动画/特效/UI 事件/探针/RectTransform
#        9 = Sim2DTest        P7 2D 渲染（排序层/精灵收集/Tilemap 烘焙）
#       10 = SimVolumeTest    P8 Volume 参数栈（C 混合核心/掩码/排序/范围）
#       11 = SimImportTest    P8 完整导入器（JSON 建树/组件映射/version 守卫）
#       12 = SimGjkTest       Mesh GJK（C 核心直测/点变换/旋转体/窄相精化）
#       13 = SimShapeTest     固定形状库（11 形状规模/法线/绕序/消费出口/错误路径）
#       14 = SimTimeTest      统一时间同步（推进/固定步长/alpha/域时钟/Application 集成）
#       15 = SimSceneAdditiveTest  Additive 子场景（并入/共存/卸载/主场景不动）
#       16 = SimInputTest     统一输入（键盘边沿/自动重复去重/鼠标/滚轮/帧管线）
#       17 = SimUICanvasTest  UI 画布两模式（系统叠加/相机赋值）+ 引擎层图层叠加
#   2. 注释开关：把 runAll() 里不想要的 runXxx() 调用行注释掉即可
# 汇总：每套跑完打印各自 PASS=/FAIL=，入口末尾打印 TOTAL 并统一判退出码
#      （任何 FAIL → OS.Kernel.exit(1)；原各套不再单独退出）
# 运行：slang compile test/Test.sp → slang run export/Test/Test.module.slb
#      （必须用 Release VM：Debug VM 缺内建符号导出，系统调用钩子全灭）
# ============================================================================

public class Test
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    # ── 选套开关：0=全部；1..17=单套（套件表见文件头注释）──
    static Int32 runSuite = 0

    static bool selected( Int32 no )
    {
        if runSuite == 0
        {
            ret true
        }
        ret runSuite == no
    }

    static void runEngine()
    {
        if !selected( 1 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [1] SimEngineTest -----" )
        SimEngineTest.run()
        _pass = _pass + SimEngineTest.passCount()
        _fail = _fail + SimEngineTest.failCount()
    }

    static void runBatch()
    {
        if !selected( 2 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [2] SimBatchTest -----" )
        SimBatchTest.run()
        _pass = _pass + SimBatchTest.passCount()
        _fail = _fail + SimBatchTest.failCount()
    }

    static void runCollision()
    {
        if !selected( 3 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [3] SimCollisionTest -----" )
        SimCollisionTest.run()
        _pass = _pass + SimCollisionTest.passCount()
        _fail = _fail + SimCollisionTest.failCount()
    }

    static void runModule()
    {
        if !selected( 4 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [4] SimModuleTest -----" )
        SimModuleTest.run()
        _pass = _pass + SimModuleTest.passCount()
        _fail = _fail + SimModuleTest.failCount()
    }

    static void runSystems()
    {
        if !selected( 5 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [5] SimSystemsTest -----" )
        SimSystemsTest.run()
        _pass = _pass + SimSystemsTest.passCount()
        _fail = _fail + SimSystemsTest.failCount()
    }

    static void runFfi()
    {
        if !selected( 6 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [6] SimFfiTest -----" )
        SimFfiTest.run()
        _pass = _pass + SimFfiTest.passCount()
        _fail = _fail + SimFfiTest.failCount()
    }

    static void runPhysics()
    {
        if !selected( 7 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [7] SimPhysicsTest -----" )
        SimPhysicsTest.run()
        _pass = _pass + SimPhysicsTest.passCount()
        _fail = _fail + SimPhysicsTest.failCount()
    }

    static void runAnim()
    {
        if !selected( 8 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [8] SimAnimTest -----" )
        SimAnimTest.run()
        _pass = _pass + SimAnimTest.passCount()
        _fail = _fail + SimAnimTest.failCount()
    }

    static void run2D()
    {
        if !selected( 9 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [9] Sim2DTest -----" )
        Sim2DTest.run()
        _pass = _pass + Sim2DTest.passCount()
        _fail = _fail + Sim2DTest.failCount()
    }

    static void runVolume()
    {
        if !selected( 10 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [10] SimVolumeTest -----" )
        SimVolumeTest.run()
        _pass = _pass + SimVolumeTest.passCount()
        _fail = _fail + SimVolumeTest.failCount()
    }

    static void runImport()
    {
        if !selected( 11 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [11] SimImportTest -----" )
        SimImportTest.run()
        _pass = _pass + SimImportTest.passCount()
        _fail = _fail + SimImportTest.failCount()
    }

    static void runGjk()
    {
        if !selected( 12 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [12] SimGjkTest -----" )
        SimGjkTest.run()
        _pass = _pass + SimGjkTest.passCount()
        _fail = _fail + SimGjkTest.failCount()
    }

    static void runShape()
    {
        if !selected( 13 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [13] SimShapeTest -----" )
        SimShapeTest.run()
        _pass = _pass + SimShapeTest.passCount()
        _fail = _fail + SimShapeTest.failCount()
    }

    static void runTime()
    {
        if !selected( 14 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [14] SimTimeTest -----" )
        SimTimeTest.run()
        _pass = _pass + SimTimeTest.passCount()
        _fail = _fail + SimTimeTest.failCount()
    }

    static void runSceneAdditive()
    {
        if !selected( 15 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [15] SimSceneAdditiveTest -----" )
        SimSceneAdditiveTest.run()
        _pass = _pass + SimSceneAdditiveTest.passCount()
        _fail = _fail + SimSceneAdditiveTest.failCount()
    }

    static void runInput()
    {
        if !selected( 16 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [16] SimInputTest -----" )
        SimInputTest.run()
        _pass = _pass + SimInputTest.passCount()
        _fail = _fail + SimInputTest.failCount()
    }

    static void runUICanvas()
    {
        if !selected( 17 )
        {
            ret
        }
        Console.println( "" )
        Console.println( "----- [17] SimUICanvasTest -----" )
        SimUICanvasTest.run()
        _pass = _pass + SimUICanvasTest.passCount()
        _fail = _fail + SimUICanvasTest.failCount()
    }

    public static void run()
    {
        Console.println( "=== SimGameEngine Test harness (runSuite=" + runSuite.toString() + "; 0=all, 1..17=single) ===" )
        runEngine()
        runBatch()
        runCollision()
        runModule()
        runSystems()
        runFfi()
        runPhysics()
        runAnim()
        run2D()
        runVolume()
        runImport()
        runGjk()
        runShape()
        runTime()
        runSceneAdditive()
        runInput()
        runUICanvas()
        Console.println( "" )
        Console.println( "=== TOTAL PASS=" + _pass.toString() + " FAIL=" + _fail.toString() + " ===" )
        if _fail > 0
        {
            OS.Kernel.exit( 1 )
        }
    }
}
