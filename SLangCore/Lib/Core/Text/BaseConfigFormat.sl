#配置文本门面：基于 Map<string, Map<string,string>> 实现的 INI / Linux 系统配置解析与序列化工具。
#只处理文本，不做文件读写；文件相关功能见 Std/Text。
#覆盖两类常见格式：
#  Windows INI -- [节] + key = value（; 与 # 注释、引号值、CRLF 换行）；
#  Linux conf  -- 顶层 key = value（# 注释，如 /etc 下的 sysctl.conf / os-release 风格）。
#解析规则：
#  1) 按行扫描，行首尾空白忽略；空行与注释行（# 或 ; 开头）跳过；
#  2) [name] 切换当前节（同名节重复出现合并）；无 ']' 的非法节头忽略；
#  3) 键值分隔符先 '=' 后 ':'（兼容 key: value），均无时回退首空白
#     （sshd_config 风格 key value）；
#  4) 值被 " 或 ' 整体包裹时去引号并保留内部空白与 #/; 字符；
#     裸值以 " #"、" ;" 起的行内注释截断（无空格前缀的 # 不受影响，如密码）；
#  5) 顶层键值落入空名默认节 ""，省略节名的重载默认读写该节；
#  6) 重复键后者覆盖前者（put 语义）；Map 键集顺序即插入序。
#序列化：默认节键值最前（无节头），其余节按插入序输出，节间空行分隔；
#  值含空白 / # / ; / = / : / [ 等字符时加双引号保护（往返一致）。
#典型用法：BaseConfigFormat c = BaseConfigFormat("[db]\nhost = 127.0.0.1\nport = 3306")
#          c.getStr("db", "host", "") / c.getInt("db", "port", 0)
#          Map<string,string> db = c["db"]; db["port"] / c.toString()。
public class BaseConfigFormat extends Object
{
    #节名 -> (键 -> 值)；空名 "" 节承载顶层键值（Linux conf 无节形态）
    Map<string, Map<string,string>> _sections = new()
    #解析过程中的当前节游标（解析结束后复位为默认节）
    string _curSection = ""

    # ---- 构造 ----

    override _init_()
    {
    }

    #按配置文本构造（等价 parse）
    void _init_( string configText )
    {
        if configText == null { ret }
        this.parseText(configText)
    }

    # ---- 静态工厂 ----

    public static BaseConfigFormat parse( string configText )
    {
        ret BaseConfigFormat(configText)
    }

    # ---- 解析 ----

    #解析配置文本并替换当前内容；文本为 null 时返回 false 且不清空原内容。
    public bool parseText( string configText )
    {
        if configText == null { ret false }
        this.clear()
        int len = configText.length
        int start = 0
        for i = 0, i <= len, i = i + 1
        {
            #以 '\n'(10) 分行；行内 '\r'(13) 由 _trim 统一去除（兼容 CRLF）
            int c = -1
            if i < len
            {
                c = SystemStringCharCodeAt(configText, i)
            }

            if c == 10 || i == len
            {
                if i > start
                {
                    this._parseLine(configText.slice(start, i))
                }
                start = i + 1
            }
        }
        this._curSection = ""
        ret true
    }

    #单行解析：注释 / 节头 / 键值三分派（空白行静默忽略）
    void _parseLine( string line )
    {
        string text = this._trim(line)
        int n = text.length
        if n == 0 { ret }
        int c0 = SystemStringCharCodeAt(text, 0)
        #注释行（# 为主流，; 为 INI 传统风格）
        if c0 == 35 || c0 == 59
        {
            ret
        }

        #节头 [name]：切换当前节并预建容器（保持节顺序，即使暂无键值）
        if c0 == 91
        {
            int close = this._findChar(text, 93)  # ']'(93)
            if close <= 1 { ret }
            this._curSection = this._trim(text.slice(1, close))
            this._sectionOf(this._curSection)
            ret
        }
        #键值行：分隔符先 '='(61) 后 ':'(58)（避免误伤 http://a 之类含 ':' 的值）
        int sep = this._findChar(text, 61)  # '='(61)
        if sep < 0
        {
            sep = this._findChar(text, 58)  # ':'(58)
        }

        #均无分隔符时回退首空白（sshd_config 风格 key value）
        if sep < 0
        {
            sep = this._firstWs(text)
        }

        if sep <= 0 { ret }
        string key = this._trim(text.slice(0, sep))
        if key.length == 0 { ret }
        int vs = sep + 1
        string value = this._cleanValue(this._trim(text.slice(vs, n)))
        Map<string,string> sec = this._sectionOf(this._curSection)
        sec._setItem_(key, value)
    }

    #值清洗：引号整体包裹取内部；裸值做行内注释截断
    string _cleanValue( string raw )
    {
        int n = raw.length
        if n >= 2
        {
            int last = n - 1
            int c0 = SystemStringCharCodeAt(raw, 0)
            int cl = SystemStringCharCodeAt(raw, last)
            #"(34) 与 '(39) 成对包裹：保留内部全部字符原样
            if ( c0 == 34 && cl == 34 ) || ( c0 == 39 && cl == 39 )
            {
                ret raw.slice(1, last)
            }
        }
        #行内注释：' #' 与 ' ;' 截断（要求空格前缀，避免误伤含 # 的密码等值）
        int p1 = this._findWsPrefixed(raw, 35)  # ' #'
        int p2 = this._findWsPrefixed(raw, 59)  # " ;"
        int cut = n
        if p1 >= 0 && p1 < cut
        {
            cut = p1
        }

        if p2 >= 0 && p2 < cut
        {
            cut = p2
        }

        if cut < n
        {
            ret this._trim(raw.slice(0, cut))
        }
        ret raw
    }

    #去除两端空白（空格32 / \t9 / \r13 / \n10）
    string _trim( string text )
    {
        if text == null { ret "" }
        int len = text.length
        int s = 0
        int e = len
        while s < e
        {
            int c = SystemStringCharCodeAt(text, s)
            if c == 32 || c == 9 || c == 13 || c == 10
            {
                s = s + 1
            }
            else
            {
                break
            }
        }
        while e > s
        {
            int last = e - 1
            int c = SystemStringCharCodeAt(text, last)
            if c == 32 || c == 9 || c == 13 || c == 10
            {
                e = e - 1
            }
            else
            {
                break
            }
        }
        if s == 0 && e == len
        {
            ret text
        }
        ret text.slice(s, e)
    }

    #第一个空白字符（空格32 / \t9）下标，无则 -1
    int _firstWs( string text )
    {
        int n = text.length
        for i = 0, i < n, i = i + 1
        {
            int c = SystemStringCharCodeAt(text, i)
            if c == 32 || c == 9
            {
                ret i
            }
        }
        ret -1
    }

    #查找第一个字符 ch 的下标，无则 -1（Core 无子串查找系统调用，逐字符扫描）
    int _findChar( string text, int ch )
    {
        int n = text.length
        for i = 0, i < n, i = i + 1
        {
            int c = SystemStringCharCodeAt(text, i)
            if c == ch
            {
                ret i
            }
        }
        ret -1
    }

    #查找第一个带空白前缀（空格32 / \t9）的字符 ch 下标，无则 -1
    #（行内注释定位用：" #" 与 " ;" 语法，防误伤无空格前缀的 # 值）
    int _findWsPrefixed( string text, int ch )
    {
        int n = text.length
        for i = 1, i < n, i = i + 1
        {
            int c = SystemStringCharCodeAt(text, i)
            if c == ch
            {
                int prev = i - 1
                int p = SystemStringCharCodeAt(text, prev)
                if p == 32 || p == 9
                {
                    ret i
                }
            }
        }
        ret -1
    }

    #取节容器，不存在则新建（解析写入 / setStr 共用；null 节名归默认节）
    Map<string,string> _sectionOf( string section )
    {
        string name = section
        if name == null { name = "" }
        Map<string,string> sec = this._sections[name]
        if sec == null
        {
            sec = new()
            this._sections._setItem_(name, sec)
        }
        ret sec
    }

    # ---- 基础属性与结构查询 ----

    #内部容器活引用（节名 -> 键值表，可直接使用 Map 全部能力）
    get Map<string, Map<string,string>> sections()
    {
        ret this._sections
    }

    get bool isEmpty()
    {
        ret this._sections.isEmpty
    }

    get bool isNotEmpty()
    {
        ret this._sections.isNotEmpty
    }

    #节数量（含可能无键值的空节）
    get int sectionCount()
    {
        ret this._sections.length
    }

    #全部键值对总数（各节求和）
    get int keyCount()
    {
        int total = 0
        List<string> names = this._sections.keys
        int n = names.length
        for i = 0, i < n, i = i + 1
        {
            string name = names[i]
            Map<string,string> sec = this._sections[name]
            if sec != null
            {
                total += sec.length
            }
        }
        ret total
    }

    #节名列表（插入序，空名默认节也在其中）
    public List<string> sectionNames()
    {
        ret this._sections.keys
    }

    #指定节的键值表活引用，不存在返回 null
    public Map<string,string> getSection( string section )
    {
        ret this._sections[section]
    }

    #指定节的键列表（插入序），节不存在返回空列表
    public List<string> keys( string section )
    {
        Map<string,string> sec = this._sections[section]
        if sec == null
        {
            ret List<string>()
        }
        ret sec.keys
    }

    public bool hasSection( string section )
    {
        ret this._sections.containsKey(section)
    }

    public bool hasKey( string section, string key )
    {
        Map<string,string> sec = this._sections[section]
        if sec == null { ret false }
        ret sec.containsKey(key)
    }

    #默认节是否存在指定键
    public bool hasKey( string key )
    {
        ret this.hasKey("", key)
    }

    #节名索引器：cfg["db"] 取节表（不存在返回 null）
    #注：节表二次下标请先赋局部变量（Map<string,string> s = cfg["db"]; s["port"]），
    #    临时值链式下标 cfg["db"]["port"] 当前 VM 求值为空，不可用。
    public override Map<string,string> _getItem_( string section )
    {
        ret this._sections[section]
    }

    # ---- 类型化取值（未命中 / 值缺失返回默认值）----

    public string getStr( string section, string key, string defaultValue )
    {
        Map<string,string> sec = this._sections[section]
        if sec == null { ret defaultValue }
        string v = sec[key]
        if v == null { ret defaultValue }
        ret v
    }

    #默认节（顶层键）取字符串值
    public string getStr( string key, string defaultValue )
    {
        ret this.getStr("", key, defaultValue)
    }

    public int getInt( string section, string key, int defaultValue )
    {
        string v = this.getStr(section, key, null)
        if v == null { ret defaultValue }
        ret SystemInt32Parse(v)
    }
    public int getInt( string key, int defaultValue )
    {
        ret this.getInt("", key, defaultValue)
    }

    public Float64 getFloat( string section, string key, Float64 defaultValue )
    {
        string v = this.getStr(section, key, null)
        if v == null { ret defaultValue }
        ret SystemConvertFloat64(v)
    }
    public Float64 getFloat( string key, Float64 defaultValue )
    {
        ret this.getFloat("", key, defaultValue)
    }

    #布尔宽松匹配：true/1/yes/on 为真，false/0/no/off 为假（区分大小写），其余取默认值
    public bool getBool( string section, string key, bool defaultValue )
    {
        string v = this.getStr(section, key, null)
        if v == null { ret defaultValue }

        if v == "true" || v == "1" || v == "yes" || v == "on" { ret true }

        if v == "false" || v == "0" || v == "no" || v == "off" { ret false }
        ret defaultValue
    }
    public bool getBool( string key, bool defaultValue )
    {
        ret this.getBool("", key, defaultValue)
    }

    # ---- 写入 / 删除 ----

    #写入指定节键值（节不存在自动创建，put 语义）
    public void setStr( string section, string key, string value )
    {
        if key == null { ret }
        string v = value
        if v == null { v = "" }
        Map<string,string> sec = this._sectionOf(section)
        sec._setItem_(key, v)
    }

    #写入默认节键值
    public void setStr( string key, string value )
    {
        this.setStr("", key, value)
    }

    #删除节内键值，返回是否存在并已删除
    public bool removeKey( string section, string key )
    {
        Map<string,string> sec = this._sections[section]
        if sec == null { ret false }
        string old = sec.remove(key)
        if old == null { ret false }
        ret true
    }
    public bool removeKey( string key )
    {
        ret this.removeKey("", key)
    }

    #删除整节（含其全部键值），返回是否存在并已删除
    public bool removeSection( string section )
    {
        Map<string,string> old = this._sections.remove(section)
        if old == null { ret false }
        ret true
    }

    public void clear()
    {
        this._sections.clear()
        this._curSection = ""
    }

    # ---- 序列化 ----

    #序列化为配置文本（默认节最前无节头，其余节按插入序，节间空行分隔）
    public string toConfig()
    {
        StringBuilder sb = new()
        this._writeSection(sb, "")
        List<string> names = this._sections.keys
        int n = names.length
        for i = 0, i < n, i = i + 1
        {
            string name = names[i]
            if name.length > 0
            {
                this._writeSection(sb, name)
            }
        }
        string text = sb.toString()
        sb.release()
        ret text
    }

    #写出单个节（空节跳过；默认节无节头）
    void _writeSection( StringBuilder sb, string name )
    {
        Map<string,string> sec = this._sections[name]
        if sec == null { ret }

        if sec.isEmpty { ret }

        if name.length > 0
        {
            if sb.isNotEmpty
            {
                sb.appendLine()
            }
            sb.appendLine("[" + name + "]")
        }
        List<string> ks = sec.keys
        int n = ks.length
        for i = 0, i < n, i = i + 1
        {
            string k = ks[i]
            string v = sec[k]
            sb.appendLine(k + " = " + this._quoteValue(v))
        }
    }

    #值是否需要引号保护（首尾空白 / 注释 / 分隔符 / 节头字符）
    bool _needsQuote( string value )
    {
        int n = value.length
        if n == 0 { ret false }
        int c0 = SystemStringCharCodeAt(value, 0)
        int last = n - 1
        int cl = SystemStringCharCodeAt(value, last)
        if c0 == 32 || c0 == 9 || cl == 32 || cl == 9 { ret true }

        if this._findChar(value, 35) >= 0 { ret true }

        if this._findChar(value, 59) >= 0 { ret true }

        if this._findChar(value, 61) >= 0 { ret true }

        if this._findChar(value, 58) >= 0 { ret true }

        if this._findChar(value, 91) >= 0 { ret true }
        ret false
    }

    string _quoteValue( string value )
    {
        if value == null { ret "" }

        if this._needsQuote(value)
        {
            ret "\"" + value + "\""
        }
        ret value
    }

    override string toString()
    {
        ret this.toConfig()
    }
}
