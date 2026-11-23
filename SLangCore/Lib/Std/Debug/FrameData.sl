# ============================================================================
# Std/Debug/FrameData.sl —— 帧数据变化记录器
#
# 三个类型（namespace SLang，自 Core/Data/FrameData.sl 空壳 stub 迁入并重构；
# 原计划挂 namespace Data，与 Core 根类 Data 同名——调用链解析 Data.XXX
# 会命中 Core.Data 类导致 FrameData 不可见，故归入 Debug 家族 SLang 命名空间）：
#   FrameData        —— 变化记录基类：每次值变化记录「时间点 + frameCount」
#                       两个数；环形历史缓冲保存最近 N 次变化；全局帧计数器。
#   FrameData<T>     —— 泛型值包装：update(v) 传入任意类型的值，值变化时
#                       自动记录（首次传入 = 初始化基线，不记录；后续同值
#                       不记录，== 为值比较：数值/字符串/布尔按值，类按 equals）。
#   FrameDataManager —— 管理类：注册一批 FrameData 后统一设置历史长度，
#                       按名查找、汇总查询、生成报表。
#
# 全局帧计数：所有 FrameData 实例共享 FrameData._globalFrame；宿主每帧
# 调用 SLang.FrameData.tickFrame()（或 setFrameCount(n) 对齐外部帧号）。
# 每条历史记录的 frameCount 即「变化发生时的全局帧号」。
#
# 用法：
#   import Std;
#   SLang.FrameData<Int32> hp = SLang.FrameData<Int32>( "playerHp", 100 )
#   SLang.FrameDataManager mgr = SLang.FrameDataManager()
#   mgr.register( hp, "playerHp" )
#   mgr.setHistoryLength( 100 )          # 每个已注册项只保留最近 100 次变化
#   SLang.FrameData.tickFrame()          # 游戏主循环每帧推进一次
#   hp.update( 95 )                      # 值变化：记录 (时间点, frameCount)
#   Int64 t1 = hp.lastChangeTime()        # 最近一次变化的时间点（Unix 毫秒）
#   Int64 f1 = hp.lastChangeFrame()       # 最近一次变化的全局帧号
#   Int32  n  = hp.historyCount()         # 现存历史条数（<= 100）
#   Int64 t0 = hp.changeTime( 0 )          # 第 0 条 = 最旧一条
# ============================================================================

namespace SLang
{
    # ================================================================
    # FrameData —— 变化记录基类（非泛型）：
    # 持有「变化时间点 + 变化帧号」双数组环形历史与全局帧计数器。
    # 泛型值包装请用 FrameData<T>。
    # ================================================================
    public class FrameData extends Object
    {
        # ---- 全局帧计数（所有 FrameData 实例共享）----
        static Int64 _globalFrame = 0

        # ---- 实例状态 ----
        # 名称（便于管理类按名索引与输出）
        string    _name      = ""
        # 历史容量（环形缓冲长度）
        Int32     _capacity  = 64
        # 变化时间点历史（Unix 毫秒）
        Array<Int64> _times  = null
        # 变化帧号历史（全局 frameCount 快照）
        Array<Int64> _frames = null
        # 环形缓冲写游标（下一条落点）
        Int32     _head      = 0
        # 现存历史条数（<= _capacity）
        Int32     _kept      = 0
        # 累计变化次数（不因环形覆盖丢失）
        Int64     _changeCount = 0
        # 最近一次变化时间点 / 帧号
        Int64     _lastTime  = 0
        Int64     _lastFrame = 0

        # ---- 构造 ----
        override _init_()
        {
            this._name = ""
            this._capacity = 64
            this._times  = Array<Int64>( 64 )
            this._frames = Array<Int64>( 64 )
            this._head = 0
            this._kept = 0
            this._changeCount = 0
            this._lastTime = 0
            this._lastFrame = 0
        }

        _init_( string name )
        {
            this._name = name
            this._capacity = 64
            this._times  = Array<Int64>( 64 )
            this._frames = Array<Int64>( 64 )
            this._head = 0
            this._kept = 0
            this._changeCount = 0
            this._lastTime = 0
            this._lastFrame = 0
        }

        _init_( string name, Int32 historyLength )
        {
            if historyLength <= 0
            {
                historyLength = 64
            }
            this._name = name
            this._capacity = historyLength
            this._times  = Array<Int64>( historyLength )
            this._frames = Array<Int64>( historyLength )
            this._head = 0
            this._kept = 0
            this._changeCount = 0
            this._lastTime = 0
            this._lastFrame = 0
        }

        # ---- 全局帧计数 ----

        # 全局帧号 +1（宿主主循环每帧调用一次）
        public static void tickFrame()
        {
            _globalFrame = _globalFrame + 1
        }

        # 直接设置全局帧号（与外部帧号对齐时用）
        public static void setFrameCount( Int64 frame )
        {
            _globalFrame = frame
        }

        # 当前全局帧号
        public static Int64 frameCount()
        {
            ret _globalFrame
        }

        # ---- 实例查询 ----

        # 名称
        public string name()
        {
            ret this._name
        }

        public void setName( string name )
        {
            this._name = name
        }

        # 历史容量（最多保留多少次变化）
        public Int32 historyLength()
        {
            ret this._capacity
        }

        # 累计变化次数（含已被环形覆盖掉的）
        public Int64 changeCount()
        {
            ret this._changeCount
        }

        # 现存历史条数（<= 历史容量）
        public Int32 historyCount()
        {
            ret this._kept
        }

        # 第 idx 条变化的时间点（idx 从 0 起 = 最旧一条；越界返回 0）
        public Int64 changeTime( Int32 idx )
        {
            Int32 pos = this._phys( idx )
            if pos < 0
            {
                ret 0
            }
            ret this._times[pos]
        }

        # 第 idx 条变化的全局帧号（idx 从 0 起 = 最旧一条；越界返回 0）
        public Int64 changeFrame( Int32 idx )
        {
            Int32 pos = this._phys( idx )
            if pos < 0
            {
                ret 0
            }
            ret this._frames[pos]
        }

        # 最近一次变化的时间点（从未变化返回 0）
        public Int64 lastChangeTime()
        {
            ret this._lastTime
        }

        # 最近一次变化的全局帧号（从未变化返回 0）
        public Int64 lastChangeFrame()
        {
            ret this._lastFrame
        }

        # 清空历史（累计计数一并归零；当前值不动的语义由派生类保证）
        public void clearHistory()
        {
            this._head = 0
            this._kept = 0
            this._changeCount = 0
            this._lastTime = 0
            this._lastFrame = 0
        }

        # ---- 配置 ----

        # 调整历史容量：保留最近 min(新容量, 现存条数) 条记录
        public void setHistoryLength( Int32 n )
        {
            if n <= 0
            {
                ret
            }
            if n == this._capacity
            {
                ret
            }
            Int32 keep = this._kept
            if keep > n
            {
                keep = n
            }
            Array<Int64> newTimes  = Array<Int64>( n )
            Array<Int64> newFrames = Array<Int64>( n )
            Int32 i = 0
            while i < keep
            {
                # 源记录的时序下标：现存条数 - 保留条数 + i（从旧到新）
                Int32 src = this._kept - keep + i
                Int32 srcPos = this._phys( src )
                Int32 dstPos = i
                newTimes[dstPos]  = this._times[srcPos]
                newFrames[dstPos] = this._frames[srcPos]
                i = i + 1
            }
            this._times  = newTimes
            this._frames = newFrames
            this._capacity = n
            this._kept = keep
            this._head = keep
            if this._head >= n
            {
                this._head = 0
            }
        }

        # ---- 内部 ----

        # 记录一次变化：时间点 + 当前全局帧号（FrameData<T>.update 检测到变化时调用）
        void _recordChange()
        {
            Int64 now = SystemTimerNowMillis()
            Int64 frame = _globalFrame
            Int32 head = this._head
            this._times[head]  = now
            this._frames[head] = frame
            head = head + 1
            if head >= this._capacity
            {
                head = 0
            }
            this._head = head
            if this._kept < this._capacity
            {
                this._kept = this._kept + 1
            }
            this._changeCount = this._changeCount + 1
            this._lastTime = now
            this._lastFrame = frame
        }

        # 时序下标 -> 物理下标（idx 0 = 最旧现存记录；越界返回 -1）
        Int32 _phys( Int32 idx )
        {
            if idx < 0
            {
                ret -1
            }
            if idx >= this._kept
            {
                ret -1
            }
            if this._kept >= this._capacity
            {
                # 满环：最旧记录位于写游标处
                Int32 pos = ( this._head + idx ) % this._capacity
                ret pos
            }
            # 未满环：记录按时序落满 [0, _kept)
            ret idx
        }
    }

    # ================================================================
    # FrameData<T> —— 泛型值包装：
    # update(v) 传入任意值；首次传入为初始化基线（不记录），之后每次
    # 值变化自动记录「时间点 + frameCount」。== 为值比较。
    # ================================================================
    public class FrameData<T> extends FrameData
    {
        # 当前值
        T    _value    = null
        # 是否已初始化基线
        bool _hasValue = false

        # 传入新值。返回 true 表示值发生变化且记录了一次历史；
        # 首次传入（初始化基线）与同值重复传入均返回 false。
        public bool update( T v )
        {
            if !this._hasValue
            {
                this._value = v
                this._hasValue = true
                ret false
            }
            if this._value == v
            {
                ret false
            }
            this._value = v
            this._recordChange()
            ret true
        }

        # 当前值（未初始化时为 null）
        public T currentValue()
        {
            ret this._value
        }

        # 是否已建立基线
        public bool hasValue()
        {
            ret this._hasValue
        }
    }

    # ================================================================
    # FrameDataManager —— FrameData 管理类：
    # 注册一批 FrameData（任意 T 的实例以基类引用收纳），统一配置
    # 历史长度、按名查找、汇总统计与文本报表。
    # ================================================================
    public class FrameDataManager extends Object
    {
        List<FrameData> _items = null
        List<string>    _names = null

        override _init_()
        {
            this._items = List<FrameData>()
            this._names = List<string>()
        }

        # 注册（同名不覆盖，find 返回先注册者）
        public void register( FrameData fd, string name )
        {
            if fd == null
            {
                ret
            }
            fd.setName( name )
            this._items.add( fd )
            this._names.add( name )
        }

        # 已注册数量
        public Int32 count()
        {
            ret this._items.length
        }

        # 按序号取（越界返回 null）
        public FrameData at( Int32 idx )
        {
            if idx < 0
            {
                ret null
            }
            if idx >= this._items.length
            {
                ret null
            }
            List<FrameData> items = this._items
            ret items[idx]
        }

        # 按名查找（未找到返回 null）
        public FrameData find( string name )
        {
            Int32 i = 0
            while i < this._items.length
            {
                List<string> names = this._names
                if names[i] == name
                {
                    List<FrameData> items = this._items
                    ret items[i]
                }
                i = i + 1
            }
            ret null
        }

        # 按名移除（返回是否找到并移除）
        public bool remove( string name )
        {
            Int32 i = 0
            while i < this._items.length
            {
                List<string> names = this._names
                if names[i] == name
                {
                    this._items.removeAt( i )
                    this._names.removeAt( i )
                    ret true
                }
                i = i + 1
            }
            ret false
        }

        # 全部已注册项的历史容量统一调整（如 100 = 各保留最近 100 次变化）
        public void setHistoryLength( Int32 n )
        {
            Int32 i = 0
            while i < this._items.length
            {
                List<FrameData> items = this._items
                FrameData fd = items[i]
                fd.setHistoryLength( n )
                i = i + 1
            }
        }

        # 单项调整历史容量（未找到返回 false）
        public bool setHistoryLength( string name, Int32 n )
        {
            FrameData fd = this.find( name )
            if fd == null
            {
                ret false
            }
            fd.setHistoryLength( n )
            ret true
        }

        # 所有已注册项的累计变化次数总和
        public Int64 totalChangeCount()
        {
            Int64 total = 0
            Int32 i = 0
            while i < this._items.length
            {
                List<FrameData> items = this._items
                FrameData fd = items[i]
                total = total + fd.changeCount()
                i = i + 1
            }
            ret total
        }

        # 清空注册表（不改动各 FrameData 自身历史）
        public void clear()
        {
            this._items.clear()
            this._names.clear()
        }

        # 文本报表：每项一行（名称 / 累计变化 / 现存历史 / 最近变化帧号）
        public string report()
        {
            StringBuilder sb = StringBuilder()
            sb.append( "[FrameDataManager] count=" )
            Int32 n = this._items.length
            sb.append( n.toString() )
            Int32 i = 0
            while i < n
            {
                List<FrameData> items = this._items
                FrameData fd = items[i]
                List<string> names = this._names
                sb.append( "\n" )
                sb.append( names[i] )
                sb.append( ": changes=" )
                sb.append( fd.changeCount().toString() )
                sb.append( ", history=" )
                sb.append( fd.historyCount().toString() )
                sb.append( "/" )
                sb.append( fd.historyLength().toString() )
                sb.append( ", lastFrame=" )
                sb.append( fd.lastChangeFrame().toString() )
                i = i + 1
            }
            ret sb.toString()
        }
    }
}
