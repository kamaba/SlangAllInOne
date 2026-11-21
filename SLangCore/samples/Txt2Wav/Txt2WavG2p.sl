import Std

# =============================================================
# Txt2WavG2p.sl —— 文本前端（仿 Tacotron frontend + 规则式 G2P）
#
# 职责：
#   1. 英文文本归一化（小写、数字展开、非法字符清理）
#   2. 字母 → 音素（规则式 letter-to-sound，ARPAbet 子集）
#   3. 音素 → id（供 Embedding 查表）
#
# 全部规则数据内置，不依赖任何外部模型文件。
# =============================================================

# ── 音素表（静态数据，运行期解析成数组）──────────────────
# 字段：名称 F1 F2 F3 浊音 振幅 时长ms 噪声占比 带宽系数
# 共振峰频率取自经典语音学图表（男性近似值），浊音=1/清音=0
public class Txt2WavLexicon
{
    # 双字母规则（最长优先匹配；与 OUT2 一一对应）
    Array<string> PAT2 = null
    Array<string> OUT2 = null

    # 三字母规则
    Array<string> PAT3 = null
    Array<string> OUT3 = null

    # 例外词典（常用词，优先于规则）
    Array<string> DICT_WORDS = null
    Array<string> DICT_PHONES = null

    # 数字词（数字展开用，逐位朗读）
    Array<string> DIGIT_WORDS = null

    # ── 解析后的音素表 ────────────────────────────────────
    Array<string> names = null
    Array<Float32> feats = null
    Int32 phoneCount = 0
    Int32 featDim = 8

    _init_()
    {
        Array<string> pat2 = [ "ch", "sh", "th", "ph", "wh", "ck", "ng", "qu", "oo", "ee", "ea", "ai", "ay", "oa", "ow", "ou", "oi", "oy", "au", "aw", "ar", "er", "ir", "or", "ur", "bb", "dd", "ff", "gg", "ll", "mm", "nn", "pp", "rr", "ss", "tt", "zz" ]
        Array<string> out2 = [ "CH", "SH", "TH", "F", "W", "K", "NG", "K W", "UW", "IY", "IY", "EH Y", "AA Y", "AO W", "AA W", "AA W", "AO Y", "AO Y", "AO", "AO", "AA R", "ER", "ER", "AO R", "ER", "B", "D", "F", "G", "L", "M", "N", "P", "R", "S", "T", "Z" ]
        Array<string> pat3 = [ "igh", "tch", "ear" ]
        Array<string> out3 = [ "AA Y", "CH", "IH R" ]
        Array<string> dictWords = [ "the", "a", "to", "of", "is", "was", "are", "you", "one", "two", "do", "does", "what", "this", "that", "hello", "world", "yes", "no", "love", "be", "me", "my", "we", "he", "she", "they", "there", "have", "has", "had", "and", "or", "for", "from", "with", "at", "on", "in", "it", "as", "your", "our", "out", "about", "test", "text", "speech", "speak", "simple", "sample", "engine", "language", "open", "source", "code", "write", "read", "run", "file", "save", "user", "computer", "data", "like", "just", "use", "new", "now", "how", "who", "water", "time", "first", "second", "version", "english", "work", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "zero", "three", "four", "five", "six", "seven", "eight", "nine", "ten" ]
        Array<string> dictPhones = [ "DH AH", "AH", "T UW", "AH V", "IH Z", "W AH Z", "AA R", "Y UW", "W AH N", "T UW", "D UW", "D AH Z", "W AH T", "DH IH S", "DH AE T", "HH EH L OW", "W ER L D", "Y EH S", "N OW", "L AH V", "B IY", "M IY", "M AA Y", "W IY", "HH IY", "SH IY", "DH EH Y", "DH EH R", "HH AE V", "HH AE Z", "HH AE D", "AE N D", "AO R", "F AO R", "F R AH M", "W IH TH", "AE T", "AA N", "IH N", "IH T", "AE Z", "Y AO R", "AA W ER", "AA W T", "AH B AA W T", "T EH S T", "T EH K S T", "S P IY CH", "S P IY K", "S IH M P AH L", "S AE M P AH L", "EH N JH IH N", "L AE NG G W IH J", "AO W P AH N", "S AO R S", "K AO D", "R AA Y T", "R IY D", "R AH N", "F AA Y L", "S EH Y V", "Y UW Z ER", "K AH M P Y UW T ER", "D EH Y T AH", "L AA Y K", "JH AH S T", "Y UW Z", "N UW", "N AA W", "HH AA W", "HH UW", "W AO T ER", "T AA Y M", "F ER S T", "S EH K AH N D", "V ER ZH AH N", "IH NG G L IH SH", "W ER K", "K W IH K", "B R AA W N", "F AA K S", "JH AH M P S", "OW V ER", "L EY Z IY", "D AA G", "Z IY R OW", "TH R IY", "F AO R", "F AY V", "S IH K S", "S EH V AH N", "EY T", "N AY N", "T EH N" ]
        Array<string> digitWords = [ "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" ]

        this.PAT2 = pat2
        this.OUT2 = out2
        this.PAT3 = pat3
        this.OUT3 = out3
        this.DICT_WORDS = dictWords
        this.DICT_PHONES = dictPhones
        this.DIGIT_WORDS = digitWords

        this.parsePhones()
    }

    void parsePhones()
    {
        # 音素表：名称 F1 F2 F3 浊音 振幅 时长ms 噪声占比 带宽系数
        # 共振峰频率取自经典语音学图表（男性近似值）
        string dat = f"""
AA 730 1090 2440 1 1.00 130 0.00 1.0
AE 660 1720 2410 1 1.00 130 0.00 1.0
AH 640 1190 2390 1 0.95 110 0.00 1.0
AO 570 840 2410 1 1.00 130 0.00 1.0
EH 530 1840 2480 1 0.95 120 0.00 1.0
ER 490 1350 1690 1 0.95 140 0.00 1.2
IH 390 1990 2550 1 0.90 100 0.00 1.0
IY 270 2290 3010 1 1.00 130 0.00 1.0
UH 440 1020 2240 1 0.90 100 0.00 1.0
UW 300 870 2240 1 1.00 130 0.00 1.0
B 350 900 2200 1 0.55 50 0.45 1.3
D 350 1700 2600 1 0.55 50 0.45 1.3
G 350 1300 2200 1 0.55 55 0.45 1.3
P 400 1000 2300 0 0.60 60 0.85 1.3
T 400 1800 2700 0 0.65 60 0.85 1.3
K 400 1400 2300 0 0.65 65 0.85 1.3
M 250 1100 2300 1 0.60 75 0.00 2.0
N 250 1500 2500 1 0.60 70 0.00 2.0
NG 250 2000 2600 1 0.60 75 0.00 2.0
F 500 1600 4500 0 0.55 90 1.00 1.8
V 500 1600 4500 1 0.50 65 0.55 1.8
TH 500 1600 4500 0 0.45 90 1.00 2.0
DH 500 1600 4500 1 0.45 60 0.55 2.0
S 700 5500 7000 0 0.75 100 1.00 1.6
Z 700 5500 7000 1 0.70 85 0.70 1.6
SH 800 2700 3400 0 0.75 100 1.00 1.5
ZH 800 2700 3400 1 0.70 80 0.70 1.5
HH 600 1400 2600 0 0.35 65 1.00 2.5
L 350 950 2600 1 0.80 75 0.00 1.2
R 350 1050 1600 1 0.85 80 0.00 1.2
W 300 620 2200 1 0.85 60 0.00 1.1
Y 300 2200 3000 1 0.85 60 0.00 1.1
CH 800 2700 3400 0 0.70 90 0.95 1.5
JH 800 2700 3400 1 0.65 75 0.75 1.5
_ 500 1500 2500 0 0.02 160 0.00 1.0
"""
        Int32 len = SystemStringLength( dat )
        Array<string> lines = Array<string>( 80 )
        Int32 lineCount = 0
        Int32 i = 0
        Int32 lineStart = 0
        while i <= len
        {
            Int32 c = 10
            if i < len
            {
                c = SystemStringCharCodeAt( dat, i )
            }
            if c == 10 || c == 13 || i == len
            {
                if i > lineStart
                {
                    lines[ lineCount ] = SystemStringRange( dat, lineStart, i )
                    lineCount = lineCount + 1
                }
                lineStart = i + 1
            }
            i = i + 1
        }

        this.phoneCount = lineCount
        this.names = Array<string>( lineCount )
        this.feats = Array<Float32>( lineCount * this.featDim )
        Int32 fd = this.featDim
        Int32 p = 0
        while p < lineCount
        {
            Array<string> fields = Txt2WavLexicon.splitSpaces( lines[ p ] )
            this.names[ p ] = fields[ 0 ]
            # 字段：name F1 F2 F3 voiced amp dur noise bw → 9 列
            Int32 rowBase = p * fd
            Int32 col = 0
            Int32 f = 1
            while f < 9
            {
                if col < fd
                {
                    this.feats[ rowBase + col ] = Txt2WavLexicon.parseNum( fields[ f ] )
                }
                col = col + 1
                f = f + 1
            }
            p = p + 1
        }
    }

    Int32 nameToId( string name )
    {
        Int32 i = 0
        while i < this.phoneCount
        {
            if Txt2WavLexicon.strEq( this.names[ i ], name )
            {
                ret i
            }
            i = i + 1
        }
        ret 0
    }

    string idToName( Int32 id )
    {
        if id < 0 || id >= this.phoneCount
        {
            ret this.names[ 0 ]
        }
        ret this.names[ id ]
    }

    Int32 durMsOf( Int32 id )
    {
        Int32 fd = this.featDim
        ret SystemConvertInt32( this.feats[ id * fd + 5 ] )
    }

    # ── 工具 ─────────────────────────────────────────────
    static bool strEq( string a, string b )
    {
        if a == null || b == null
        {
            ret false
        }
        Int32 la = SystemStringLength( a )
        Int32 lb = SystemStringLength( b )
        if la != lb
        {
            ret false
        }
        Int32 i = 0
        while i < la
        {
            if SystemStringCharCodeAt( a, i ) != SystemStringCharCodeAt( b, i )
            {
                ret false
            }
            i = i + 1
        }
        ret true
    }

    # 简易数字解析（string→Float32 的 System 转换在此语境不可靠，自行逐字符解析）
    # 支持 "730"、"0.45"、"-1.2e3"（纯 ASCII，负号/小数/指数）
    static Float32 parseNum( string s )
    {
        Int32 len = SystemStringLength( s )
        Float32 sign = 1.0f
        Int32 i = 0
        if len > 0
        {
            Int32 c0 = SystemStringCharCodeAt( s, 0 )
            if c0 == 45
            {
                sign = -1.0f
                i = 1
            }
            elif c0 == 43
            {
                i = 1
            }
        }
        Float32 ip = 0.0f
        bool dotSeen = false
        Float32 frac = 0.0f
        Float32 scale = 0.1f
        while i < len
        {
            Int32 c = SystemStringCharCodeAt( s, i )
            if c >= 48 && c <= 57
            {
                Float32 d = SystemConvertFloat32( c - 48 )
                if dotSeen
                {
                    frac = frac + d * scale
                    scale = scale * 0.1f
                }
                else
                {
                    ip = ip * 10.0f + d
                }
                i = i + 1
            }
            elif c == 46 && !dotSeen
            {
                dotSeen = true
                i = i + 1
            }
            else
            {
                # 非数字（含 e 指数等）直接截断
                i = len
            }
        }
        ret sign * ( ip + frac )
    }

    static Array<string> splitSpaces( string s )
    {
        Int32 len = SystemStringLength( s )
        Array<string> parts = Array<string>( 16 )
        Int32 n = 0
        Int32 i = 0
        Int32 segStart = -1
        while i <= len
        {
            Int32 c = 32
            if i < len
            {
                c = SystemStringCharCodeAt( s, i )
            }
            if c == 32 || c == 9 || i == len
            {
                if segStart >= 0
                {
                    parts[ n ] = SystemStringRange( s, segStart, i )
                    n = n + 1
                    segStart = -1
                }
            }
            else
            {
                if segStart < 0
                {
                    segStart = i
                }
            }
            i = i + 1
        }
        if n == 0
        {
            Array<string> empty = Array<string>( 1 )
            empty[ 0 ] = ""
            ret empty
        }
        if n == parts.length
        {
            ret parts
        }
        Array<string> outV = Array<string>( n )
        Int32 j = 0
        while j < n
        {
            outV[ j ] = parts[ j ]
            j = j + 1
        }
        ret outV
    }
}

# ── 文本前端：归一化 + G2P + 编码 ─────────────────────────
public class Txt2WavFrontend
{
    Txt2WavLexicon lex = null

    # 小写字母查找表（码位 → 字符转换用）
    string LC = "abcdefghijklmnopqrstuvwxyz"

    # 句尾疑问句标记（升调）
    bool risingTail = false

    _init_()
    {
        this.lex = Txt2WavLexicon()
    }

    Txt2WavLexicon lexicon()
    {
        ret this.lex
    }

    # ── 1. 归一化：小写 + 数字展开 + 清理 ─────────────────
    string normalize( string text )
    {
        Int32 len = SystemStringLength( text )
        string s = ""
        Int32 i = 0
        while i < len
        {
            Int32 c = SystemStringCharCodeAt( text, i )
            if c >= 65 && c <= 90
            {
                c = c + 32
            }
            if c >= 97 && c <= 122
            {
                s = s + SystemStringRange( this.LC, c - 97, c - 96 )
            }
            elif c >= 48 && c <= 57
            {
                # 数字逐位展开为单词
                Int32 d = c - 48
                Array<string> digits = this.lex.DIGIT_WORDS
                string w = digits[ d ]
                if SystemStringLength( s ) > 0
                {
                    Int32 lastC = SystemStringCharCodeAt( s, SystemStringLength( s ) - 1 )
                    if lastC != 32
                    {
                        s = s + " "
                    }
                }
                s = s + w + " "
            }
            elif c == 32 || c == 44 || c == 46 || c == 33 || c == 63 || c == 59 || c == 58
            {
                # 空格与标点保留（标点归一为空格 + 记录韵律）
                if c == 63
                {
                    this.risingTail = true
                }
                Int32 lastC = -1
                if SystemStringLength( s ) > 0
                {
                    lastC = SystemStringCharCodeAt( s, SystemStringLength( s ) - 1 )
                }
                if lastC != 32
                {
                    s = s + " "
                }
            }
            i = i + 1
        }
        ret s
    }

    # ── 2. G2P：单词 → 音素序列 ──────────────────────────
    Array<string> g2pWord( string word )
    {
        Array<string> res = Array<string>( 64 )
        Int32 n = 0

        # 规则/词典表先取局部引用（下标位置禁用成员链）
        Array<string> dictWords = this.lex.DICT_WORDS
        Array<string> dictPhones = this.lex.DICT_PHONES
        Array<string> pat2 = this.lex.PAT2
        Array<string> out2 = this.lex.OUT2
        Array<string> pat3 = this.lex.PAT3
        Array<string> out3 = this.lex.OUT3
        Int32 nPat2 = pat2.length
        Int32 nPat3 = pat3.length

        # 例外词典优先
        Int32 d = 0
        while d < dictWords.length
        {
            if Txt2WavLexicon.strEq( word, dictWords[ d ] )
            {
                Array<string> ph = Txt2WavLexicon.splitSpaces( dictPhones[ d ] )
                Int32 k = 0
                while k < ph.length
                {
                    res[ n ] = ph[ k ]
                    n = n + 1
                    k = k + 1
                }
                ret Txt2WavFrontend.trimTo( res, n )
            }
            d = d + 1
        }

        Int32 len = SystemStringLength( word )
        if len == 0
        {
            ret Txt2WavFrontend.trimTo( res, n )
        }

        Int32 i = 0
        while i < len
        {
            if n >= 60
            {
                i = len
            }
            # --- 3 字母规则 ---
            bool matched = false
            if i + 3 <= len
            {
                string sub3 = word.slice( i, i + 3 )
                Int32 r = 0
                while r < nPat3
                {
                    if Txt2WavLexicon.strEq( sub3, pat3[ r ] )
                    {
                        Array<string> ph = Txt2WavLexicon.splitSpaces( out3[ r ] )
                        Int32 k = 0
                        while k < ph.length
                        {
                            res[ n ] = ph[ k ]
                            n = n + 1
                            k = k + 1
                        }
                        i = i + 3
                        matched = true
                    }
                    if matched
                    {
                        r = nPat3
                    }
                    else
                    {
                        r = r + 1
                    }
                }
            }

            # --- 2 字母规则 ---
            if !matched && i + 2 <= len
            {
                string sub2 = word.slice( i, i + 2 )
                Int32 r = 0
                while r < nPat2
                {
                    bool ok = Txt2WavLexicon.strEq( sub2, pat2[ r ] )
                    if ok
                    {
                        # r 组合后跟元音时退化（如 "era"），避免误吞
                        if r >= 20 && r <= 24
                        {
                            if i + 3 <= len && Txt2WavFrontend.isVowelChar( SystemStringCharCodeAt( word, i + 2 ) )
                            {
                                ok = false
                            }
                        }
                        # kn / wr 只在词首生效
                        string p2 = pat2[ r ]
                        if Txt2WavLexicon.strEq( p2, "kn" ) || Txt2WavLexicon.strEq( p2, "wr" )
                        {
                            if i != 0
                            {
                                ok = false
                            }
                        }
                    }
                    if ok
                    {
                        Array<string> ph = Txt2WavLexicon.splitSpaces( out2[ r ] )
                        Int32 k = 0
                        while k < ph.length
                        {
                            res[ n ] = ph[ k ]
                            n = n + 1
                            k = k + 1
                        }
                        i = i + 2
                        matched = true
                    }
                    if matched
                    {
                        r = nPat2
                    }
                    else
                    {
                        r = r + 1
                    }
                }
            }

            # --- 魔法 e（v C e 词尾，如 make/like/code）---
            if !matched && i + 3 == len
            {
                Int32 c = SystemStringCharCodeAt( word, i )
                Int32 c1 = SystemStringCharCodeAt( word, i + 1 )
                Int32 c2 = SystemStringCharCodeAt( word, i + 2 )
                bool magicE = false
                if Txt2WavFrontend.isVowelChar( c )
                {
                    if !Txt2WavFrontend.isVowelChar( c1 )
                    {
                        if c2 == 101
                        {
                            magicE = true
                        }
                    }
                }
                if magicE
                {
                    if c == 97
                    {
                        res[ n ] = "EH"
                        res[ n + 1 ] = "Y"
                        n = n + 2
                    }
                    elif c == 105
                    {
                        res[ n ] = "AA"
                        res[ n + 1 ] = "Y"
                        n = n + 2
                    }
                    elif c == 111
                    {
                        res[ n ] = "AO"
                        res[ n + 1 ] = "W"
                        n = n + 2
                    }
                    elif c == 117
                    {
                        res[ n ] = "UW"
                        n = n + 1
                    }
                    else
                    {
                        res[ n ] = "IY"
                        n = n + 1
                    }
                    i = i + 3
                    matched = true
                }
            }

            # --- 单字母规则 ---
            if !matched
            {
                Int32 c = SystemStringCharCodeAt( word, i )
                Int32 nc = -1
                if i + 1 < len
                {
                    nc = SystemStringCharCodeAt( word, i + 1 )
                }
                # 词尾静音 e（be/me 等已在词典）：直接跳过
                bool silentE = false
                if c == 101
                {
                    if i == len - 1
                    {
                        if len > 2
                        {
                            silentE = true
                        }
                    }
                }
                if silentE
                {
                    i = i + 1
                }
                elif c == 99
                {
                    # c: e/i/y 前发 S，否则 K
                    if Txt2WavFrontend.isSoftChar( nc )
                    {
                        res[ n ] = "S"
                    }
                    else
                    {
                        res[ n ] = "K"
                    }
                    n = n + 1
                }
                elif c == 103
                {
                    # g: e/i/y 前发 JH，否则 G
                    if Txt2WavFrontend.isSoftChar( nc )
                    {
                        res[ n ] = "JH"
                    }
                    else
                    {
                        res[ n ] = "G"
                    }
                    n = n + 1
                }
                elif c == 121
                {
                    # y: 词首 Y / 词尾 IY / 词中 IH
                    if i == 0
                    {
                        res[ n ] = "Y"
                    }
                    elif i == len - 1
                    {
                        res[ n ] = "IY"
                    }
                    else
                    {
                        res[ n ] = "IH"
                    }
                    n = n + 1
                }
                elif c == 97
                {
                    res[ n ] = "AE"
                    n = n + 1
                }
                elif c == 101
                {
                    res[ n ] = "EH"
                    n = n + 1
                }
                elif c == 105
                {
                    res[ n ] = "IH"
                    n = n + 1
                }
                elif c == 111
                {
                    res[ n ] = "AA"
                    n = n + 1
                }
                elif c == 117
                {
                    res[ n ] = "AH"
                    n = n + 1
                }
                elif c == 120
                {
                    res[ n ] = "K"
                    res[ n + 1 ] = "S"
                    n = n + 2
                }
                elif c == 113
                {
                    res[ n ] = "K"
                    n = n + 1
                }
                elif c == 106
                {
                    res[ n ] = "JH"
                    n = n + 1
                }
                elif c == 98
                {
                    res[ n ] = "B"
                    n = n + 1
                }
                elif c == 100
                {
                    res[ n ] = "D"
                    n = n + 1
                }
                elif c == 102
                {
                    res[ n ] = "F"
                    n = n + 1
                }
                elif c == 104
                {
                    res[ n ] = "HH"
                    n = n + 1
                }
                elif c == 107
                {
                    res[ n ] = "K"
                    n = n + 1
                }
                elif c == 108
                {
                    res[ n ] = "L"
                    n = n + 1
                }
                elif c == 109
                {
                    res[ n ] = "M"
                    n = n + 1
                }
                elif c == 110
                {
                    res[ n ] = "N"
                    n = n + 1
                }
                elif c == 112
                {
                    res[ n ] = "P"
                    n = n + 1
                }
                elif c == 114
                {
                    res[ n ] = "R"
                    n = n + 1
                }
                elif c == 115
                {
                    res[ n ] = "S"
                    n = n + 1
                }
                elif c == 116
                {
                    res[ n ] = "T"
                    n = n + 1
                }
                elif c == 118
                {
                    res[ n ] = "V"
                    n = n + 1
                }
                elif c == 119
                {
                    res[ n ] = "W"
                    n = n + 1
                }
                elif c == 122
                {
                    res[ n ] = "Z"
                    n = n + 1
                }
                i = i + 1
            }
        }
        ret Txt2WavFrontend.trimTo( res, n )
    }

    # ── 3. 句子 → 音素序列（含停顿插入）─────────────────
    Array<string> toPhones( string text )
    {
        this.risingTail = false
        string s = this.normalize( text )
        Array<string> res = Array<string>( 256 )
        Int32 n = 0

        # 首部停顿
        res[ n ] = "_"
        n = n + 1

        Array<string> words = Txt2WavLexicon.splitSpaces( s )
        Int32 w = 0
        while w < words.length
        {
            if n < 180
            {
                if SystemStringLength( words[ w ] ) > 0
                {
                    Array<string> ph = this.g2pWord( words[ w ] )
                    Int32 k = 0
                    while k < ph.length
                    {
                        res[ n ] = ph[ k ]
                        n = n + 1
                        k = k + 1
                    }
                    # 词间短停顿
                    res[ n ] = "_"
                    n = n + 1
                }
            }
            w = w + 1
        }

        # 尾部停顿
        res[ n ] = "_"
        n = n + 1

        ret Txt2WavFrontend.trimTo( res, n )
    }

    # ── 4. 音素 → id 序列 ────────────────────────────────
    Array<Int32> encode( Array<string> phones )
    {
        Array<Int32> ids = Array<Int32>( phones.length )
        Int32 i = 0
        while i < phones.length
        {
            ids[ i ] = this.lex.nameToId( phones[ i ] )
            i = i + 1
        }
        ret ids
    }

    static bool isVowelChar( Int32 c )
    {
        if c == 97
        {
            ret true
        }
        if c == 101
        {
            ret true
        }
        if c == 105
        {
            ret true
        }
        if c == 111
        {
            ret true
        }
        if c == 117
        {
            ret true
        }
        ret false
    }

    # e / i / y（c、g 的软化环境）
    static bool isSoftChar( Int32 c )
    {
        if c == 101
        {
            ret true
        }
        if c == 105
        {
            ret true
        }
        if c == 121
        {
            ret true
        }
        ret false
    }

    static Array<string> trimTo( Array<string> src, Int32 n )
    {
        if n <= 0
        {
            Array<string> empty = Array<string>( 1 )
            empty[ 0 ] = "_"
            ret empty
        }
        if n == src.length
        {
            ret src
        }
        Array<string> outV = Array<string>( n )
        Int32 i = 0
        while i < n
        {
            outV[ i ] = src[ i ]
            i = i + 1
        }
        ret outV
    }
}
