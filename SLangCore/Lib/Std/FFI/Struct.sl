#!
 * Std/FFI/Struct.sl
 * FFI 结构体布局（FFI.Struct，布局注册 / native 内存块 / 双向 marshal）
 * 的 SL 封装（Dart 风格，见 md/project/ffi.md）。
 * 分层：cvm src/lib/ffi/sl_ffi_struct.{h,c}（布局 sig 解析 + 注册表 +
 * native 内存块，C 自然对齐 / "packed:" 前缀紧凑布局）+
 * src/vm/system_method_call/ffi_system_method.c（VM 适配层，弹参压结果）。
 *
 * 布局 sig 为逗号分隔的“类型短名 字段名”对（FFI 短名，不做 SL 名映射）：
 *   "i32 width, i32 height, f64 ratio, utf8 name"
 * "packed:" 前缀取消对齐（紧凑布局）。字段名与 native 侧结构体成员
 * 同名时 marshal 按名逐字段拷贝（utf8 指针字段进附属字符串池）。
 * 注意：sig 只接受 FFI 短名（i32/u8/utf8/ptr/f64...），传 SL 名
 * （Int32/string...）会解析失败返回 0。
!#

#! 单个 native 内存块封装：地址 + 布局 id + marshal 双向进出。 !#
public class FFI.Struct extends Object
{
    Int64 _addr = 0
    Int32 _id = 0

    public override void _init_()
    {
    }

    #! 按布局 id 分配 native 内存块（0 = 失败）。 !#
    public void _init_( Int32 id )
    {
        this._id = id
        this._addr = SystemFFIStructAlloc( id )
    }

    #! native 块地址（0 = 无效 / 未分配）。 !#
    get Int64 address()
    {
        ret this._addr
    }

    #! 布局 id（<=0 = 未绑定）。 !#
    get Int32 layoutId()
    {
        ret this._id
    }

    #! 释放本块 native 内存（false = 地址无效）。 !#
    public bool free()
    {
        bool ok = SystemFFIStructFree( this._addr )
        if ( ok )
        {
            this._addr = 0
        }
        ret ok
    }

    #! SL 对象字段按名写入本块（返回本块地址，0 = 失败）。 !#
    public Int64 marshalOut( object obj )
    {
        ret SystemFFIStructMarshalOut( obj, this._id )
    }

    #! 本块内容按名写回 SL 对象（false = 失败）。 !#
    public bool marshalIn( object obj )
    {
        ret SystemFFIStructMarshalIn( this._addr, this._id, obj )
    }

    #! 布局注册：sig 幂等复用，返回布局 id（<=0 失败）。 !#
    public static Int32 define( string sig )
    {
        ret SystemFFIStructDefine( sig )
    }

    #! 布局内存块大小（id 无效返回 <=0）。 !#
    public static Int32 size( Int32 id )
    {
        ret SystemFFIStructSize( id )
    }

    #! native 内存块分配（0 = 失败）。 !#
    public static Int64 alloc( Int32 id )
    {
        ret SystemFFIStructAlloc( id )
    }

    #! native 内存块释放（false = 地址无效）。 !#
    public static bool free( Int64 addr )
    {
        ret SystemFFIStructFree( addr )
    }

    #! SL 对象 -> native 内存块（0 = 失败）。 !#
    public static Int64 marshalOut( object obj, Int32 id )
    {
        ret SystemFFIStructMarshalOut( obj, id )
    }

    #! native 内存块 -> SL 对象（false = 失败）。 !#
    public static bool marshalIn( Int64 addr, Int32 id, object obj )
    {
        ret SystemFFIStructMarshalIn( addr, id, obj )
    }
}
