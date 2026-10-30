# Text/RegExp.sl

> 源文件：`Text/RegExp.sl`

## class `RegExpCharSet`

- **说明**：RegExpCharSet - 字符集合（[...] 与 \d\w\s 的公共载体） ASCII 部分（码点 0..127）用 128 槽 0/1 表；非 ASCII 部分用区间表； _negate 为真时结果取反（[^...] / \D\W\S）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Array&lt;Int32&gt; _ascii = null` | 字段 Array（类型见签名）。 |
| 字段 | `public List&lt;Int32&gt; _loList = null` | 字段 List（类型见签名）。 |
| 字段 | `public List&lt;Int32&gt; _hiList = null` | 字段 List（类型见签名）。 |
| 字段 | `public bool _negate = false` | 字段 bool（类型见签名）。 |
| 构造 | `_init_()` | 构造方法，初始化本类型实例。 |
| 方法 | `void addRange(Int32 lo, Int32 hi)` | 加入闭区间 [lo, hi]（码点） |
| 方法 | `void addChar(Int32 cp)` | 加入单个码点 |
| 方法 | `void addDigit()` | 加入 \d 集合（数字） |
| 方法 | `void addWord()` | 加入 \w 集合（数字 + 字母 + 下划线 + 全部非 ASCII，与 Python3/C# 的 Unicode 语义一致） |
| 方法 | `void addSpace()` | 加入 \s 集合（空白） |
| 方法 | `void applyIgnoreCase()` | 忽略大小写模式：把已加入集合的 ASCII 字母补上另一大小写 |
| 方法 | `bool contains(Int32 cp)` | 码点是否属于本集合（考虑 _negate） |

## class `RegExpInst`

- **说明**：RegExpInst - 编译后的指令（字段含义随 op 变化，见 RegExp 类操作码注释）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Int32 op = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 ch = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 x = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 y = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 z = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 w = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 v = 0` | 字段 Int32（类型见签名）。 |
| 构造 | `_init_(Int32 opCode)` | 构造方法，初始化本类型实例。 |

## class `RegExpMatch`

- **说明**：RegExpMatch - 一次成功匹配的结果 index/end 为字节位置；group(0) 为整体匹配；组未参与匹配时 group 返回空串。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string _text = null` | 字段 string（类型见签名）。 |
| 字段 | `public Int32 index = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 end = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Array&lt;Int32&gt; _slots = null` | 字段 Array（类型见签名）。 |
| 字段 | `public Int32 _groupCount = 0` | 字段 Int32（类型见签名）。 |
| 构造 | `_init_(string text, Int32 startIndex, Int32 endIndex, Array&lt;Int32&gt; slots, Int32 groupCount)` | 构造方法，初始化本类型实例。 |
| 方法 | `string value()` | 匹配整体文本 |
| 方法 | `string group(Int32 g)` | 组 g 文本（0 = 整体；未参与匹配返回空串） |
| 方法 | `bool groupOk(Int32 g)` | 组 g 是否参与了本次匹配 |
| 属性 | `get Int32 length()` | 匹配长度（字节数） |

## class `RegExpState`

- **说明**：RegExpState - 单次匹配的执行状态（每次匹配新建，天然并发安全）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public string _text = null` | 字段 string（类型见签名）。 |
| 字段 | `public Int32 _len = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Array&lt;Int32&gt; _slots = null` | 字段 Array（类型见签名）。 |
| 字段 | `public Array&lt;Int32&gt; _guards = null` | 字段 Array（类型见签名）。 |
| 字段 | `public Int32 _cp = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 _clen = 0` | 字段 Int32（类型见签名）。 |
| 构造 | `_init_(string text, Int32 slotCount, Int32 guardCount)` | 构造方法，初始化本类型实例。 |
| 方法 | `Int32 byteAt(Int32 i)` | 读第 i 字节；越界返回 -1 |
| 方法 | `bool readChar(Int32 i)` | 从字节位置 i 解码一个完整 UTF-8 序列，结果写入 _cp/_clen；i 越界返回 false |
| 方法 | `Int32 backChar(Int32 sp)` | 回退：返回 &lt; sp 的最近一个完整 UTF-8 序列起点（贪婪 REP 的逐字符回退用） |
| 方法 | `Array&lt;Int32&gt; copySlots()` | 克隆 / 复制（copySlots）。 |
| 方法 | `void restoreSlots(Array&lt;Int32&gt; src)` | 执行 restoreSlots(src)，行为详见源实现。 |
| 方法 | `Array&lt;Int32&gt; copyGuards()` | 克隆 / 复制（copyGuards）。 |
| 方法 | `void restoreGuards(Array&lt;Int32&gt; src)` | 执行 restoreGuards(src)，行为详见源实现。 |

## class `RegExpCompiled`

- **说明**：RegExpCompiled - 编译产物缓存条目（P4-D 模式缓存）

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public Array&lt;Int32&gt; prog = null` | 字段 Array（类型见签名）。 |
| 字段 | `public Array&lt;Int32&gt; cs = null` | 字段 Array（类型见签名）。 |
| 字段 | `public Int32 groupCount = 0` | 字段 Int32（类型见签名）。 |
| 字段 | `public Int32 guardCount = 0` | 字段 Int32（类型见签名）。 |
| 构造 | `_init_(Array&lt;Int32&gt; progArr, Array&lt;Int32&gt; csArr, Int32 gc, Int32 guardN)` | 构造方法，初始化本类型实例。 |

## class `RegExp`

- **说明**：RegExp - 正则表达式主类 模式编译为指令链（List<RegExpInst>，x/y/z/w/v 字段含义见各操作码）， 匹配时经 _run 递归回溯执行；每次匹配新建 RegExpState，实例可复用。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public const static Int32 OP_NOP = 0` | ---- 操作码 ---- |
| 字段 | `public const static Int32 OP_CHAR = 1` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_CLASS = 2` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_DOT = 3` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_SPLIT = 4` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_JMP = 5` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_SAVE = 6` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_MATCH = 7` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_BOL = 9` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_EOL = 10` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_WORDB = 11` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_NWORDB = 12` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_BACKREF = 13` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_CHAR_REP = 14` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_CLASS_REP = 15` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_DOT_REP = 16` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_GUARD = 17` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_LAHEAD_POS = 18` | 字段 const（类型见签名）。 |
| 字段 | `public const static Int32 OP_LAHEAD_NEG = 19` | 字段 const（类型见签名）。 |
| 字段 | `string _pattern = null` | ---- 实例状态 ---- |
| 字段 | `bool _ignoreCase = false` | 字段 _ignoreCase（类型见签名）。 |
| 字段 | `bool _multiline = false` | 字段 _multiline（类型见签名）。 |
| 字段 | `List&lt;RegExpInst&gt; _prog = null` | 字段 _prog（类型见签名）。 |
| 字段 | `List&lt;RegExpCharSet&gt; _charsets = null` | 字段 _charsets（类型见签名）。 |
| 字段 | `Int32 _groupCount = 0` | 字段 _groupCount（类型见签名）。 |
| 字段 | `Int32 _guardCount = 0` | 字段 _guardCount（类型见签名）。 |
| 字段 | `Int32 _patPos = 0` | 字段 _patPos（类型见签名）。 |
| 字段 | `Int32 _patLen = 0` | 字段 _patLen（类型见签名）。 |
| 字段 | `Array&lt;Int32&gt; _flatProgCache = null` | 字段 _flatProgCache（类型见签名）。 |
| 字段 | `Array&lt;Int32&gt; _flatCsCache = null` | 字段 _flatCsCache（类型见签名）。 |
| 字段 | `static Map&lt;string, RegExpCompiled&gt; _cache = null` | ---- P4-D 模式缓存（CPython sre._cache 同款）---- 相同 pattern+flags 的编译产物全局共享（只读：flat 数组仅作 SystemRegExp* 入参，运行期 state 独立）。上限 512 条轮转淘汰。 |
| 字段 | `static Array&lt;string&gt; _cacheKeys = null` | 字段 Array（类型见签名）。 |
| 字段 | `static Int32 _cacheNext = 0` | 字段 Int32（类型见签名）。 |
| 方法 | `RegExpCompiled _cacheGet(string key)` | 执行 _cacheGet(key)，行为详见源实现。 |
| 方法 | `void _cachePut(string key, RegExpCompiled c)` | 执行 _cachePut(key, c)，行为详见源实现。 |
| 方法 | `string _cacheKey(string pattern, bool ignoreCase, bool multiline)` | 缓存键：flags 前缀 + pattern（唯一区分编译语境） |
| 构造 | `_init_(string pattern)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(string pattern, bool ignoreCase)` | 构造方法，初始化本类型实例。 |
| 构造 | `_init_(string pattern, bool ignoreCase, bool multiline)` | 构造方法，初始化本类型实例。 |
| 方法 | `void _commonInit(string pattern, bool ignoreCase, bool multiline)` | 执行 _commonInit(pattern, ignoreCase, multiline)，行为详见源实现。 |
| 方法 | `void _compile()` | ---- 编译 ---- 主链：SAVE(0) &lt;alternation&gt; SAVE(1) MATCH |
| 方法 | `RegExpInst _emit(Int32 op)` | 执行 _emit(op)，行为详见源实现。 |
| 方法 | `Int32 _here()` | 执行 _here()。 |
| 方法 | `Int32 _patAt(Int32 i)` | 读模式第 i 字节；越界返回 -1 |
| 方法 | `Int32 _newGuard()` | 分配一个防空转槽位 |
| 方法 | `void _compileAlt()` | 编译 alternation：分支间以 SPLIT 串联，分支尾 JMP 汇合 布局（a\|b\|c）：SPLIT(1,3) CHAR-a JMP(e) SPLIT(4,6) CHAR-b JMP(e) CHAR-c JMP(e) |
| 方法 | `void _compileSeq()` | 编译顺序序列：直到 '\|'、')' 或串尾 |
| 方法 | `void _compileAtom()` | ---- 原子编译分派 ---- |
| 方法 | `void _applySimpleRepeat(Int32 repOp, Int32 atomStart)` | 简单原子（CHAR/CLASS/DOT）量词：原地改写为单条 *_REP 指令 （每次迭代至少消费 1 字节，无需 SPLIT/GUARD） |
| 字段 | `Int32 _qMin = 0` | ---- 量词解析（结果写入 _qMin/_qMax/_qLazy）---- |
| 字段 | `Int32 _qMax = 0` | 字段 _qMax（类型见签名）。 |
| 字段 | `bool _qLazy = false` | 字段 _qLazy（类型见签名）。 |
| 方法 | `bool _parseQuantifier()` | 当前位置是量词则消费并返回 true；'{' 试解失败不消费（当字面） |
| 方法 | `Int32 _parseNumber()` | 读一个十进制数；无数字返回 -1（不回退位置） |
| 字段 | `Int32 _decLen = 1` | 解码模式中 pos 起的完整 UTF-8 序列，返回码点（字节长写 _decLen） |
| 方法 | `Int32 _decodePatChar(Int32 pos)` | 执行 _decodePatChar(pos)，行为详见源实现。 |
| 方法 | `Int32 _foldCp(Int32 cp)` | 码点折叠（忽略大小写模式下 ASCII 大小写互折） |
| 方法 | `void _compileGroup()` | ---- 分组编译：'(' 由 _compileAtom 分派（未消费），本方法消费 ---- kind: 0=捕获组 1=非捕获组(?:) 2=正前瞻(?=) 3=负前瞻(?!) |
| 方法 | `void _compileEscapeAtom()` | ---- 转义原子编译：进入时 '\' 未消费 ---- |
| 方法 | `void _compileCharClassAtom()` | ---- 字符类编译：进入时 '[' 未消费 ---- |
| 方法 | `void _applyComplexRepeat(Int32 splitPh, Int32 guardPh, Int32 atomStart, Int32 atomEnd)` | ---- 复杂原子（分组/反向引用）量词展开 ---- 进入时体已发射于 [atomStart, atomEnd) 且 _prog 末尾 == atomEnd splitPh/guardPh 为体前两个 NOP 占位；按量词矩阵回填/追加（_qMin/_qMax/_qLazy 已就绪） |
| 方法 | `Int32 _copyBlock(Int32 from, Int32 to)` | ---- 块拷贝：把 _prog[from, to) 追加到末尾，返回拷贝基址 ---- SPLIT/JMP/LAHEAD 的 x/y 指向块内 → 平移 delta；GUARD 分配新槽；其余字段原样 |
| 方法 | `Int32 _isWordByte(Int32 b)` | ---- 执行器 ---- 词字节判断（\w 语义：ASCII 数字/字母/下划线 + 任意多字节首字节） |
| 方法 | `Int32 _repEat(RegExpState st, RegExpInst inst, Int32 pos)` | REP 指令吃进 pos 处一个字符：成功 1（st._clen 已更新），失败 0 |
| 方法 | `Int32 _run(RegExpState st, Int32 pc, Int32 sp, Int32 endPc)` | 回溯执行：endPc&lt;0 主链模式（OP_MATCH 终止）；endPc&gt;=0 子链模式（到达 endPc 即成功） |
| 方法 | `Int32 _flags(bool anchored)` | ---- C 下沉入口 ---- flags 位打包：bit0=ignoreCase, bit1=multiline, bit2=anchored |
| 方法 | `Array&lt;Int32&gt; _flatProg()` | 惰性展平指令链：每指令 7 槽 [op, ch, x, y, z, w, v] |
| 方法 | `Array&lt;Int32&gt; _flatCs()` | 惰性展平字符集段表：[段数, 各段偏移..., 段数据...] 段数据 = 128 个 ascii 标志 + negate + rangeCount + lo/hi 交错 |
| 方法 | `RegExpMatch _runOnCvm(string text, Int32 from, bool anchored)` | 经 C 下沉执行（vm_sys_regexp_run 一次完成整个回溯匹配） anchored=true 只试 from 一处（match 语义）；返回 RegExpMatch 或 null |
| 方法 | `List&lt;RegExpMatch&gt; _findAllOnCvm(string text, Int32 from)` | ---- P4-A 批量下沉（RUNTIME_OPTIMIZATION_PLAN.md §10）---- SystemRegExpFindAll 一次返回全部匹配的扁平结果（每匹配 2+gc*2 个 int32：[start,end,g1s,g1e,...]），null = 无匹配/旧 VM。装配为 List&lt;RegExpMatch&gt;；失败（null）时调用方回退 SL 驱动循环。 |
| 方法 | `string _replaceOnCvm(string text, string rep)` | SystemRegExpReplace：整段驱动 + 模板展开全在 C 侧；返回 null = 旧 VM（未注册）→ 调用方回退 SL 实现。 |
| 方法 | `RegExpMatch _runOnSl(string text, Int32 from, bool anchored)` | 经 SL 解释器执行（性能基线对照；驱动语义与 C 下沉版一致：逐起点尝试 + 每起点新建状态） |
| 方法 | `RegExpMatch _searchFrom(string text, Int32 from)` | ---- 公有 API ---- 从 from 起扫描首个匹配；无匹配返回 null |
| 方法 | `RegExpMatch match(string text)` | 锚定匹配（串首起，不扫描）；失败返回 null |
| 方法 | `RegExpMatch search(string text)` | 扫描首个匹配；无匹配返回 null |
| 方法 | `bool isMatch(string text)` | 是否存在匹配 |
| 方法 | `List&lt;RegExpMatch&gt; matchAll(string text)` | 所有非重叠匹配（含零宽匹配，按 finditer 语义推进游标） P4-A：优先批量下沉（一次调用全收集）；null（旧 VM/无注册）回退 SL 循环 |
| 方法 | `string _expand(string rep, RegExpMatch m)` | 展开替换模板：$& 整体 / $1..$9 组 / $$ 字面 $ |
| 方法 | `string replace(string text, string rep)` | 替换所有匹配（rep 支持 $& $1..$9 $$）；零宽匹配保留原字符 P4-A：优先批量下沉（驱动 + 模板展开全在 C 侧）；无注册（旧 VM）回退 SL 实现 |
| 方法 | `List&lt;string&gt; split(string text)` | 按匹配切分（Python re.split 语义变体：零宽匹配仅在产生新内容处设切点） |
| 属性 | `get Int32 groupCount()` | 捕获组数量（不含组 0） |
| 方法 | `bool isMatch(string text, string pattern)` | ---- 静态便捷 ---- |
| 方法 | `bool isMatch(string text, string pattern, bool ignoreCase)` | 判断状态是否（isMatch）。 |
| 方法 | `RegExpMatch match(string text, string pattern)` | 比较 / 排序 / 相等判定（match）。 |
| 方法 | `RegExpMatch search(string text, string pattern)` | 执行 search(text, pattern)，行为详见源实现。 |
| 方法 | `List&lt;RegExpMatch&gt; matchAll(string text, string pattern)` | 比较 / 排序 / 相等判定（matchAll）。 |
| 方法 | `string replace(string text, string pattern, string rep)` | 执行 replace(text, pattern, rep)，行为详见源实现。 |
| 方法 | `string escape(string s)` | 转义模式特殊字符（ASCII 标点前加 '\'；字母数字保持原样） |
