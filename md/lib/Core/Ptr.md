# Ptr.sl

> 源文件：`Ptr.sl`

## class `Ptr`

- **说明**：Ptr - Pointer abstraction for native memory access. Inspired by: CLR  : System.IntPtr (Zero, Size, Add, Subtract, ToInt32, ToInt64) Rust : raw pointers (*const T, *mut T) Go   : unsafe.Pointer Provides a safe wrapper around native memory addresses with typed read/write operations.  Memory must be allocated via Ptr.alloc() and freed via Ptr.free() to avoid leaks. Usage: p = Ptr.alloc(64)       # allocate 64 bytes p.writeInt32(0, 42)     # write Int32 at offset 0 v = p.readInt32(0)      # read Int32 at offset 0 -> 42 Ptr.free(p)             # release memory

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _address = 0` | Fields The native memory address (64-bit to support both 32/64-bit platforms). |
| 方法 | `void _init_()` | Constructors Default constructor: zero address (null pointer). |
| 方法 | `void _init_(Int64 address)` | Construct from a 64-bit address. |
| 方法 | `void _init_(Int32 address)` | Construct from a 32-bit address. |
| 方法 | `Ptr zero()` | Static factory and utility methods Returns a Ptr with value zero (null pointer). |
| 方法 | `Int32 size()` | Size of a pointer on the current platform (4 or 8 bytes). |
| 方法 | `Ptr alloc(Int32 byteCount)` | Allocate a block of native memory of the given size. Returns a Ptr pointing to the allocated memory. |
| 方法 | `bool free(Ptr p)` | Free native memory previously allocated by alloc(). Returns true on success. |
| 方法 | `Int64 toInt64()` | Conversion methods Returns the address as a 64-bit integer. |
| 方法 | `Int32 toInt32()` | Returns the address as a 32-bit integer (may truncate on 64-bit). |
| 方法 | `bool equals(Ptr other)` | Equality Check if this pointer equals another. |
| 方法 | `Ptr add(Int32 offset)` | Pointer arithmetic Returns a new Ptr offset by the given number of bytes. |
| 方法 | `Ptr subtract(Int32 offset)` | Returns a new Ptr offset backwards by the given number of bytes. |
| 方法 | `Int32 readByte(Int32 offset)` | Typed read operations Read a single byte at the given offset. |
| 方法 | `Int32 readInt32(Int32 offset)` | Read a 32-bit signed integer at the given offset. |
| 方法 | `Int64 readInt64(Int32 offset)` | Read a 64-bit signed integer at the given offset. |
| 方法 | `Num readFloat64(Int32 offset)` | Read a 64-bit floating-point number at the given offset. |
| 方法 | `Int32 writeByte(Int32 offset, Int32 value)` | Typed write operations Write a single byte at the given offset. Returns 1 on success. |
| 方法 | `Int32 writeInt32(Int32 offset, Int32 value)` | Write a 32-bit signed integer at the given offset. Returns 1 on success. |
| 方法 | `Int32 writeInt64(Int32 offset, Int64 value)` | Write a 64-bit signed integer at the given offset. Returns 1 on success. |
| 方法 | `Int32 writeFloat64(Int32 offset, Num value)` | Write a 64-bit floating-point number at the given offset. Returns 1 on success. |
| 方法 | `string toString()` | Object overrides Returns the address as a decimal string. |

## class `Ptr<T>`

- **说明**：Ptr<T> - Typed pointer for accessing object internals. Inspired by: C++  : T* (typed raw pointer to object) CLR  : System.Runtime.InteropServices.Marshal (PtrToStructure, StructureToPtr) Rust : *const T (typed raw pointer with field access) Wraps a VM object's internal address, allowing typed read/write access to the object's member_data buffer at specific offsets.  This enables direct field manipulation without going through the regular method dispatch path. Usage: class Vec3 { Int32 x = 0; Int32 y = 0; Int32 z = 0 } v = Vec3() p = Ptr<Vec3>( v )       # typed pointer from object p.writeInt32( 0, 10 )    # set x = 10 (offset 0) p.writeInt32( 4, 20 )    # set y = 20 (offset 4) p.writeInt32( 8, 30 )    # set z = 30 (offset 8) obj = p.get()            # recover the original object

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int64 _objAddr = 0` | Fields The internal VMObject address. |
| 方法 | `void _init_(T obj)` | Constructors Construct from an object instance: stores the internal address. |
| 方法 | `void _init_(UInt32 address)` | Construct from a raw address (UInt32). |
| 方法 | `void _init_(Int64 address)` | Construct from a raw address (Int64). |
| 方法 | `T getObject()` | Object recovery Recover the original typed object from the pointer. |
| 方法 | `Int64 toInt64()` | Conversion Returns the internal object address as Int64. |
| 方法 | `Int32 readByte(Int32 offset)` | Typed field read operations (read from member_data + offset) Read a single byte at the given field offset. |
| 方法 | `Int32 readInt32(Int32 offset)` | Read a 32-bit integer at the given field offset. |
| 方法 | `Int64 readInt64(Int32 offset)` | Read a 64-bit integer at the given field offset. |
| 方法 | `Num readFloat64(Int32 offset)` | Read a 64-bit float at the given field offset. |
| 方法 | `Int32 writeByte(Int32 offset, Int32 value)` | Typed field write operations (write to member_data + offset) Write a single byte at the given field offset. Returns 1 on success. |
| 方法 | `Int32 writeInt32(Int32 offset, Int32 value)` | Write a 32-bit integer at the given field offset. Returns 1 on success. |
| 方法 | `Int32 writeInt64(Int32 offset, Int64 value)` | Write a 64-bit integer at the given field offset. Returns 1 on success. |
| 方法 | `Int32 writeFloat64(Int32 offset, Num value)` | Write a 64-bit float at the given field offset. Returns 1 on success. |
| 方法 | `string toString()` | Object overrides |
