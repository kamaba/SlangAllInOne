# Vocab / Tokenizer —— 文本词表与分词
#
# Vocab    ：id <-> 词 双向映射，内置 <pad> <unk> <bos> <eos>
# Tokenizer：词级 / 字符级分词，提供 encode / decode / pad / truncate
#
# 说明：词级分词复用 String.split(sep)（C99 strstr 一次扫描），只保留非空词；
#       字符级仍用 slice(i, i+1) 逐字节扫描（UTF-8 字节语义）。

@Nickname("Vocab")
public class Vocab
{
    public List<string> items = null

    public Int32 padId = 0
    public Int32 unkId = 1
    public Int32 bosId = 2
    public Int32 eosId = 3

    public void _init_()
    {
        this.items = List<string>()
        this.add( "<pad>" )
        this.add( "<unk>" )
        this.add( "<bos>" )
        this.add( "<eos>" )
    }

    # 线性查找词 id：Map<string,Int32> 的值类型下标在 MetaCore 不支持
    # （模板 _getItem_ 解析失败），词表规模小，线性查找可接受
    Int32 findWord( string word )
    {
        List<string> its = this.items
        int n = its.length
        for i = 0, i < n, i++
        {
            string w = its._getItem_( i )
            if w == word
            {
                ret i
            }
        }
        ret -1
    }

    # 返回词的 id；已存在则直接返回旧 id
    public Int32 add( string word )
    {
        Int32 found = this.findWord( word )
        if found >= 0
        {
            ret found
        }
        Int32 id = this.items.length
        this.items.add( word )
        ret id
    }

    public bool contains( string word )
    {
        ret this.findWord( word ) >= 0
    }

    public Int32 idOf( string word )
    {
        Int32 found = this.findWord( word )
        if found >= 0
        {
            ret found
        }
        ret this.unkId
    }

    public string wordOf( Int32 id )
    {
        if id < 0
        {
            ret "<unk>"
        }
        List<string> its2 = this.items
        if id >= its2.length
        {
            ret "<unk>"
        }
        ret its2._getItem_( id )
    }

    public get int size()
    {
        ret this.items.length
    }

    public Array<string> toArray()
    {
        List<string> src = this.items
        Array<string> arr = Array<string>( src.length )
        for i = 0, i < src.length, i++
        {
            arr[i] = src._getItem_( i )
        }
        ret arr
    }
}

@Nickname("Tokenizer")
public class Tokenizer
{
    public Vocab vocab = null
    public Int32 maxLen = 128
    public bool charLevel = false

    # 预留：标准库暂未提供 toLower，后续接入后在此生效
    public bool lower = false

    public void _init_()
    {
        this.vocab = Vocab()
        this.maxLen = 128
        this.charLevel = false
    }

    public void _init_( Vocab vocab )
    {
        this.vocab = vocab
        this.maxLen = 128
        this.charLevel = false
    }

    # ── 建表 ─────────────────────────────────────────────
    # 词级：按空白切分，过滤低频词
    # 计数用平行 List 实现：Map 下标写在 MetaCore 不受支持（ParseDefineMetaType
    # 拒绝非 Array 下标目标），词表规模小，线性查找可接受
    public void build( Array<string> texts, Int32 minFreq )
    {
        List<string> words = List<string>()
        List<Int32> counts = List<Int32>()
        for i = 0, i < texts.length, i++
        {
            Array<string> ws = this.split( texts[i] )
            for j = 0, j < ws.length, j++
            {
                string w = ws[j]
                int pos = -1
                for k = 0, k < words.length, k++
                {
                    string wk = words._getItem_( k )
                    if wk == w
                    {
                        pos = k
                    }
                }
                if pos < 0
                {
                    words.add( w )
                    counts.add( 1 )
                }
                else
                {
                    Int32 ck = counts[pos]
                    counts.fill( ck + 1, pos, 1 )
                }
            }
        }
        for i = 0, i < words.length, i++
        {
            string w = words[i]
            Int32 c = counts[i]
            if c >= minFreq
            {
                this.vocab.add( w )
            }
        }
    }

    # 字符级：把语料里出现过的每个字符都收进词表
    public void buildChars( Array<string> texts )
    {
        this.charLevel = true
        for i = 0, i < texts.length, i++
        {
            string s = texts[i]
            for k = 0, k < s.length(), k++
            {
                this.vocab.add( s.slice( k, k + 1 ) )
            }
        }
        this.vocab.add( " " )
    }

    # ── 切分 ─────────────────────────────────────────────
    public Array<string> split( string text )
    {
        # 走 String.split（C 层 strstr 一次扫描 + 精确容量数组），滤掉相邻
        # 空格产生的空串；旧版逐字符 slice + 字符串相加是 O(n²)。
        Array<string> raw = text.split( " " )
        List<string> outV = List<string>()
        for i = 0, i < raw.length, i++
        {
            string part = raw[i]
            if part != ""
            {
                outV.add( part )
            }
        }
        Array<string> arr = Array<string>( outV.length )
        for i = 0, i < outV.length, i++
        {
            string token = outV._getItem_( i )
            arr[i] = token
        }
        ret arr
    }

    # ── 编码 / 解码 ──────────────────────────────────────
    public Array<Int32> encode( string text )
    {
        List<string> tokens = List<string>()
        if this.charLevel
        {
            for i = 0, i < text.length(), i++
            {
                tokens.add( text.slice( i, i + 1 ) )
            }
        }
        else
        {
            Array<string> ws = this.split( text )
            for i = 0, i < ws.length, i++
            {
                tokens.add( ws[i] )
            }
        }
        Array<Int32> ids = Array<Int32>( tokens.length )
        for i = 0, i < tokens.length, i++
        {
            string tk = tokens._getItem_( i )
            ids[i] = this.vocab.idOf( tk )
        }
        ret ids
    }

    # 带特殊符号：<bos> ... <eos>
    public Array<Int32> encodeWithSpecial( string text )
    {
        Array<Int32> body = this.encode( text )
        Array<Int32> ids = Array<Int32>( body.length + 2 )
        ids[0] = this.vocab.bosId
        for i = 0, i < body.length, i++
        {
            ids[ i + 1 ] = body[i]
        }
        ids[ body.length + 1 ] = this.vocab.eosId
        ret ids
    }

    public string decode( Array<Int32> ids )
    {
        string s = ""
        for i = 0, i < ids.length, i++
        {
            Int32 idv = ids[i]
            # 跳过 <pad> / <bos> / <eos>
            if idv != this.vocab.padId
            {
                if idv != this.vocab.bosId
                {
                    if idv != this.vocab.eosId
                    {
                        s = s + this.vocab.wordOf( idv )
                    }
                }
            }
        }
        ret s
    }

    # ── 长度规整 ─────────────────────────────────────────
    public Array<Int32> truncate( Array<Int32> ids, Int32 len )
    {
        if ids.length <= len
        {
            ret ids
        }
        Array<Int32> r = Array<Int32>( len )
        for i = 0, i < len, i++
        {
            r[i] = ids[i]
        }
        ret r
    }

    public Array<Int32> pad( Array<Int32> ids, Int32 len )
    {
        Array<Int32> r = Array<Int32>( len )
        for i = 0, i < len, i++
        {
            if i < ids.length
            {
                r[i] = ids[i]
            }
            else
            {
                r[i] = this.vocab.padId
            }
        }
        ret r
    }

    # 编码并补齐到 maxLen
    public Array<Int32> encodePadded( string text )
    {
        ret this.pad( this.truncate( this.encodeWithSpecial( text ), this.maxLen ), this.maxLen )
    }

    public get int vocabSize()
    {
        ret this.vocab.size()
    }
}
