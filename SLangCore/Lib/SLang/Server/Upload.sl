import Std;
import Core;

namespace SLang
{
    # ============================================================================
    # SLang/Server/Upload.sl — 文件上传句柄（P1.5）
    # 设计契约：SERVER_DESIGN.md §4.4（UploadedFile 表）/ §6.5（生命周期与安全剥离）
    #
    # 语义：
    #   - 实例由 BodyParser 解析 multipart 产出（引擎构造期经 Request._ensureMultipart），
    #     用户勿直接 new；
    #   - filename 已剥离路径段（防 ../ 穿越，只留 basename）；空名生成 "upload_<序号>"；
    #   - bytes() 返回 slice 视图（不推进源索引）；内容缓冲归属本对象，请求结束由引擎
    #     统一 _release 回收——勿跨请求持有，需要持久化就 saveAs；
    #   - saveAs / saveInto 落盘（Std.IO.File.writeAllBytes）；目录不存在返回 false
    #     （不自动建目录，显式优于隐式，§6.5）；saveInto 重名自动改名 name(1).ext；
    #   - ext() 仅供业务白名单判断，不作为 MIME 判定依据（MIME 用 part 声明的
    #     contentType，§6.5）。
    # ============================================================================
    public class UploadedFile
    {
        # 表单字段名
        string _field = ""
        # 原始文件名（已剥离路径）
        string _filename = ""
        # part 声明的 Content-Type
        string _contentType = ""
        # 内容缓冲（归属本对象）
        ByteBuffer _data = null

        _init_( string field, string filename, string contentType, ByteBuffer content )
        {
            this._field = field
            this._filename = filename
            this._contentType = contentType
            this._data = content
        }

        # ── 元数据 ──

        public get string field()
        {
            ret this._field
        }

        public get string filename()
        {
            ret this._filename
        }

        public get string contentType()
        {
            ret this._contentType
        }

        # 字节数
        public get Int64 size()
        {
            if this._data == null
            {
                ret 0
            }
            Int64 n = this._data.readableBytes
            ret n
        }

        # 扩展名（小写、无点；无扩展空串；非 ASCII 字节原样保留）
        public string ext()
        {
            string name = this._filename
            Int32 nlen = SystemStringLength( name )
            Int32 dot = -1
            for Int32 i = nlen - 1, i >= 0, i = i - 1
            {
                if SystemStringCharCodeAt( name, i ) == 46
                {
                    dot = i
                    break
                }
            }
            if dot < 0 || dot == nlen - 1
            {
                ret ""
            }
            # String 无 toLowerCase（标准库现状）——逐字节折叠 'A'-'Z' → 'a'-'z'
            ByteBuffer b = ByteBuffer( 8 )
            for Int32 i = dot + 1, i < nlen, i = i + 1
            {
                Int32 c = SystemStringCharCodeAt( name, i )
                if c >= 65 && c <= 90
                {
                    c = c + 32
                }
                b.writeU8( SystemConvertUInt8( c ) )
            }
            string s = b.toString()
            b.release()
            ret s
        }

        # ── 内容 ──

        # 内容视图（slice，不推进源；勿跨请求持有）
        public ByteBuffer bytes()
        {
            if this._data == null
            {
                ret null
            }
            ret this._data.slice()
        }

        # ── 落盘 ──

        # 落盘到指定完整路径（目录须已存在；失败返回 false）
        public bool saveAs( string path )
        {
            if this._data == null
            {
                ret false
            }
            UInt8Array arr = this._data.toArray()
            bool ok = false
            label wBlock
            {
                ok = File.writeAllBytes( path, arr )
            }
            catch
            {
                ok = false
            }
            ret ok
        }

        # 落盘到目录 + 原文件名（重名自动改名 name(1).ext；目录须已存在）
        public bool saveInto( string dir )
        {
            # 目录尾部拼接：统一用 '/'（Path.altDirectorySeparatorChar 两端通用，
            # Windows 侧同样接受；base 是关键字，目录基名用 dirBase）
            string dirBase = dir
            Int32 blen = SystemStringLength( dirBase )
            if blen > 0
            {
                Int32 last = SystemStringCharCodeAt( dirBase, blen - 1 )
                if last == 47 || last == 92
                {
                    dirBase = SystemStringRange( dirBase, 0, blen - 1 )
                }
            }
            # 名字拆 stem + 含点扩展（保原大小写；无扩展整名为 stem）
            string name = this._filename
            Int32 nlen = SystemStringLength( name )
            Int32 dot = -1
            for Int32 i = nlen - 1, i >= 0, i = i - 1
            {
                if SystemStringCharCodeAt( name, i ) == 46
                {
                    dot = i
                    break
                }
            }
            string stem = name
            string extPart = ""
            if dot > 0
            {
                stem = SystemStringRange( name, 0, dot )
                extPart = SystemStringRange( name, dot, nlen )
            }
            # 重名自动改名：dup.txt → dup(1).txt → dup(2).txt ...
            string cand = dirBase + "/" + name
            Int32 n = 1
            while File.exists( cand )
            {
                cand = dirBase + "/" + stem + "(" + n.toString() + ")" + extPart
                n = n + 1
            }
            ret this.saveAs( cand )
        }

        # 内容缓冲回收（引擎请求收尾调用；幂等）
        void _release()
        {
            if this._data != null
            {
                this._data.release()
                this._data = null
            }
        }
    }
}
