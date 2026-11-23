# Std/Data/FrameData.sl 验收测试（SLang.FrameData / SLang.FrameData<T> / SLang.FrameDataManager）
# 覆盖:
#   F1  基线初始化：首次 update 不记录、hasValue / currentValue
#   F2  变化记录：值变化记录 (时间点 + frameCount) 两个数、changeCount / historyCount
#   F3  同值不记录：重复 update 同值无新历史
#   F4  frameCount 时间线：tickFrame 推进后变化落在对应帧号
#   F5  环形覆盖：容量 3 记 4 次，保留最近 3 条，累计计数不丢
#   F6  管理类设置历史长度 100：超过 100 次变化仅保留最近 100 条数字
#   F7  管理类基础：register / find / remove / count / totalChangeCount / report
#   F8  管理类混装：Int32 + string + Float32 实例同表注册
#   F9  clearHistory：清历史后计数归零
#   F10 时间点合理性：lastChangeTime 为正、changeTime 时序单调不减
# 单跑: csimple_lang run FrameDataProbe.module.json
import Std;
import Core;

FrameDataProbe
{
    static Int32 _fail = 0

    static void check( string tag, bool ok )
    {
        if ok
        {
            SystemPrintln( tag + ": OK" )
        }
        else
        {
            SystemPrintln( tag + ": FAIL" )
            _fail = _fail + 1
        }
    }

    static run()
    {
        SystemPrintln( "===== FrameDataProbe (start) =====" )

        # ---- F1 基线初始化（string 构造 + 继承构造分发）----
        SLang.FrameData<Int32> hp = SLang.FrameData<Int32>( "hp" )
        bool first = hp.update( 100 )
        check( "F1 first update not recorded", first == false )
        check( "F1 hasValue", hp.hasValue() == true )
        check( "F1 currentValue", hp.currentValue() == 100 )
        check( "F1 changeCount 0", hp.changeCount() == 0 )
        check( "F1 historyCount 0", hp.historyCount() == 0 )

        # ---- F2 变化记录两个数 ----
        SLang.FrameData.setFrameCount( 10 )
        SLang.FrameData.tickFrame()
        Int64 frameBefore = SLang.FrameData.frameCount()
        Int64 clockBefore = SystemTimerNowMillis()
        bool changed = hp.update( 95 )
        check( "F2 update returns true", changed == true )
        check( "F2 changeCount 1", hp.changeCount() == 1 )
        check( "F2 historyCount 1", hp.historyCount() == 1 )
        check( "F2 lastChangeFrame", hp.lastChangeFrame() == frameBefore )
        check( "F2 lastChangeTime clock", hp.lastChangeTime() >= clockBefore )
        check( "F2 changeFrame(0)", hp.changeFrame( 0 ) == frameBefore )
        check( "F2 changeTime(0)", hp.changeTime( 0 ) >= clockBefore )

        # ---- F3 同值不记录 ----
        bool same = hp.update( 95 )
        check( "F3 same value not recorded", same == false )
        check( "F3 changeCount still 1", hp.changeCount() == 1 )

        # ---- F4 frameCount 时间线（记录帧号 = 11, 12, 14）----
        SLang.FrameData.tickFrame()
        hp.update( 90 )
        SLang.FrameData.tickFrame()
        SLang.FrameData.tickFrame()
        hp.update( 85 )
        check( "F4 changeFrame(0)", hp.changeFrame( 0 ) == frameBefore )
        check( "F4 changeFrame(1)", hp.changeFrame( 1 ) == frameBefore + 1 )
        check( "F4 lastChangeFrame", hp.lastChangeFrame() == frameBefore + 3 )
        check( "F4 changeCount 3", hp.changeCount() == 3 )

        # ---- F5 环形覆盖（容量 3，记录帧号 = 15,16,17,18，保留 16,17,18）----
        SLang.FrameData<Int32> ring = SLang.FrameData<Int32>( "ring", 3 )
        ring.update( 0 )
        SLang.FrameData.tickFrame()
        ring.update( 1 )
        SLang.FrameData.tickFrame()
        ring.update( 2 )
        SLang.FrameData.tickFrame()
        ring.update( 3 )
        SLang.FrameData.tickFrame()
        ring.update( 4 )
        check( "F5 historyCount capped", ring.historyCount() == 3 )
        check( "F5 changeCount kept", ring.changeCount() == 4 )
        check( "F5 oldest dropped", ring.changeFrame( 0 ) == frameBefore + 5 )
        check( "F5 newest kept", ring.changeFrame( 2 ) == frameBefore + 7 )
        check( "F5 out of range 0", ring.changeFrame( 3 ) == 0 )
        check( "F5 out of range neg", ring.changeTime( -1 ) == 0 )

        # ---- F6/F7/F8 管理类：设置历史长度 100 ----
        SLang.FrameDataManager mgr = SLang.FrameDataManager()
        check( "F7 empty count", mgr.count() == 0 )
        mgr.register( ring, "ring" )
        mgr.register( hp, "hp" )
        SLang.FrameData<string> nameStr = SLang.FrameData<string>( "name", 64 )
        mgr.register( nameStr, "name" )
        SLang.FrameData<Float32> ratio = SLang.FrameData<Float32>( "ratio", 8 )
        mgr.register( ratio, "ratio" )
        check( "F8 mixed count", mgr.count() == 4 )

        # 统一设置历史长度 100（用户场景：记录 100 次）
        mgr.setHistoryLength( 100 )
        check( "F6 ring resized", ring.historyLength() == 100 )
        check( "F6 ratio resized", ratio.historyLength() == 100 )
        check( "F6 ring records kept", ring.historyCount() == 3 )

        # ratio 容量 8 → 100：灌 105 次变化（帧号 19..123），仅保留最近 100 条
        ratio.update( 0.0f )
        Int32 i = 1
        while i <= 105
        {
            SLang.FrameData.tickFrame()
            Float32 v = 1.0f * i
            ratio.update( v )
            i = i + 1
        }
        check( "F6 changeCount 105", ratio.changeCount() == 105 )
        check( "F6 historyCount 100", ratio.historyCount() == 100 )
        check( "F6 oldest is 6th", ratio.changeFrame( 0 ) == frameBefore + 13 )
        check( "F6 newest is 105th", ratio.changeFrame( 99 ) == frameBefore + 112 )
        check( "F6 totalChangeCount", mgr.totalChangeCount() == 4 + 3 + 105 )

        # ---- F7 按名查找 / 移除 ----
        SLang.FrameData fd = mgr.find( "name" )
        check( "F7 find by name", fd == nameStr )
        check( "F7 find missing null", mgr.find( "nobody" ) == null )
        SLang.FrameData fdAt = mgr.at( 1 )
        check( "F7 at(1)", fdAt == hp )
        check( "F7 at oob null", mgr.at( 99 ) == null )
        bool removed = mgr.remove( "name" )
        check( "F7 remove ok", removed == true )
        check( "F7 count after remove", mgr.count() == 3 )
        check( "F7 remove missing false", mgr.remove( "name" ) == false )
        bool single = mgr.setHistoryLength( "ring", 50 )
        check( "F7 setHistoryLength(name)", single == true && ring.historyLength() == 50 )
        check( "F7 setHistoryLength missing", mgr.setHistoryLength( "nobody", 10 ) == false )

        # 报表：首行表头 + 每项一行（首个条目 ring）
        string rpt = mgr.report()
        Array<string> rows = SystemStringSplit( rpt, "\n" )
        check( "F7 report rows", rows.length == mgr.count() + 1 )
        string firstLine = rows[1]
        check( "F7 report first item", SystemStringFront( firstLine, 4 ) == "ring" )
        SystemPrintln( "--- manager report ---" )
        SystemPrintln( rpt )

        # ---- F9 clearHistory ----
        ring.clearHistory()
        check( "F9 changeCount 0", ring.changeCount() == 0 )
        check( "F9 historyCount 0", ring.historyCount() == 0 )
        check( "F9 lastChangeFrame 0", ring.lastChangeFrame() == 0 )
        check( "F9 value kept", ring.currentValue() == 4 )

        # ---- F10 时间点合理性（快速连续变化，时间戳单调不减）----
        SLang.FrameData<Int32> t10 = SLang.FrameData<Int32>( "t10", 64 )
        t10.update( 0 )
        t10.update( 1 )
        t10.update( 2 )
        check( "F10 lastChangeTime positive", t10.lastChangeTime() > 0 )
        Int64 t0 = t10.changeTime( 0 )
        Int64 t1 = t10.changeTime( 1 )
        check( "F10 time monotonic", t0 <= t1 )
        check( "F10 changeTime equals last", t10.changeTime( 1 ) == t10.lastChangeTime() )

        if _fail == 0
        {
            SystemPrintln( "ALL PASS" )
        }
        else
        {
            SystemPrintln( "FAILED count = " + _fail.toString() )
        }
        SystemPrintln( "===== FrameDataProbe (end) =====" )
    }
}
