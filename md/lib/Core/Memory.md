# Memory.sl

> 源文件：`Memory.sl`

## class `Memory`

- **说明**：Memory - Memory management and garbage collection API. Inspired by: CLR  : System.GC (Collect, KeepAlive, GetTotalMemory, GetGeneration) Dart : WeakReference, Finalizer, implicit generational GC Go   : runtime.GC, SetGCPercent, tri-color mark-sweep The VM supports two per-object management modes: Manual – the caller controls lifetime via Retain/Release/Free. The GC will NOT sweep objects marked as manual. Auto   – the tri-color GC traces and sweeps the object automatically. Free() and Release() require the object to be in Manual mode first (via Memory.Manual(obj)).  Calling them on an Auto-managed object is a no-op and returns false. Global mode (Memory.SetMode) controls whether the GC runs at all. SetMode(false) – GC disabled (pure manual management). SetMode(true)  – GC enabled, auto-collects when pool exceeds threshold.

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `public const Int32 MODE_MANUAL = 0` | Mode constants (mirror VM_MEM_MODE_* in C). |
| 字段 | `public const Int32 MODE_GC     = 1` | 字段 const（类型见签名）。 |
| 方法 | `Int32 manual(object obj)` | Per-object mode control. Switch an object to manual management.  After this call the GC will not trace or sweep the object; the caller is responsible for calling Release() or Free() when done. Returns 1 on success. |
| 方法 | `Int32 auto(object obj)` | Restore an object to automatic (GC) management.  The GC will resume tracing and may sweep the object when it becomes unreachable. Returns 1 on success. |
| 方法 | `bool isManual(object obj)` | Check whether an object is currently in manual management mode. Returns true if manual, false if auto-managed. |
| 方法 | `Int32 refCount(object obj)` | Reference counting (manual management). Get the current reference count of an object. |
| 方法 | `Int32 retain(object obj)` | Increment the reference count (like CLR WeakReference.TrackResurrection or Objective-C retain).  Returns 1 on success. |
| 方法 | `Int32 release(object obj)` | Decrement the reference count; when it reaches 0 the object is freed. Requires Manual mode.  Returns 1 on success, 0 if rejected (auto mode). |
| 方法 | `Int32 free(object obj)` | Unconditionally free the object immediately. Requires Manual mode.  Returns 1 on success, 0 if rejected (auto mode). |
| 方法 | `Int32 collect()` | GC control (CLR-inspired: GC.Collect, GC.GetTotalMemory). Force a full GC cycle (stop-the-world tri-color mark-sweep). Returns the number of objects freed. |
| 方法 | `Int32 collect(Int32 threshold)` | Force a GC cycle only if the object pool size is &gt;= threshold. Returns the number of objects freed (0 if not triggered). |
| 方法 | `Int32 setGcThreshold(Int32 threshold)` | Set the GC auto-trigger threshold.  When the object pool grows past this size, a collection is automatically triggered on the next allocation (only in GC mode). Returns 1 on success. |
| 方法 | `Int32 gcThreshold()` | Get the current GC auto-trigger threshold. |
| 方法 | `Int32 setMode(Int32 mode)` | Set the global memory mode. Memory.MODE_MANUAL (0) – GC disabled. Memory.MODE_GC     (1) – GC enabled. Returns 1 on success. |
| 方法 | `Int32 objectCount()` | Statistics (CLR-inspired: GC.CollectionCount, GC.GetTotalMemory). Total number of objects currently in the object pool. |
| 方法 | `Int32 GcCycleCount()` | Total number of GC cycles performed. |
| 方法 | `Int32 gcFreedCount()` | Number of objects freed in the most recent GC cycle. |
| 方法 | `Int32 totalAllocated()` | Total objects ever allocated (cumulative). |
| 方法 | `Int32 totalFreed()` | Total objects ever freed, including manual free/release and GC sweep. |
| 方法 | `bool tlsfEnabled()` | TRUE when the TLSF large-object arena is compiled in (P4, design SMALL_BLOCK_ALLOCATOR_DESIGN.md §3.6/§3.7).  Host builds default to FALSE; embedded verification builds opt in via VM_TLSF_ENABLE. |
| 方法 | `Int32 tlsfUsedBytes()` | Bytes currently held by live TLSF arena blocks (0 when disabled). |
| 方法 | `Int32 tlsfFreeBytes()` | Bytes currently sitting in free TLSF arena blocks (0 when disabled). |
| 方法 | `Int32 tlsfFragmentation()` | External fragmentation of the TLSF arena, 0..100 (0 when disabled or when the free space is a single contiguous block). |
| 方法 | `bool mimallocEnabled()` | mimalloc host allocator (P6).  On MMU hosts the whole VM heap (SBA superblocks, LOS fallback, GC, runtime structures) is served by mimalloc; MCU builds keep the TLSF arena instead.  All probes return 0/FALSE when the takeover is compiled out. TRUE when mimalloc owns the process heap. |
| 方法 | `Int32 mimallocVersion()` | mimalloc library version as an int (v3.5 -&gt; 305; 0 when disabled). |
| 方法 | `void mimallocCollect(bool force)` | Release free memory back to the OS.  force=true also abandons thread-owned free pages (heavier, for tests/diagnostics). |
| 方法 | `Int64 mimallocCurrentBytes()` | Bytes currently held by live allocations (normal + huge blocks). |
| 方法 | `Int64 mimallocPeakBytes()` | Peak of mimallocCurrentBytes() since process start. |
| 方法 | `Int64 mimallocRequestedBytes()` | Live bytes the user actually requested (no allocator overhead). |
| 方法 | `Int64 mimallocCommittedBytes()` | Bytes currently committed to the OS by the allocator. |
| 方法 | `Int64 mimallocReservedBytes()` | Bytes currently reserved (committed + free reserved ranges). |
| 方法 | `object ref(object obj)` | Strong / weak references (moved from Object.sl). Strong reference: increments the refcount and returns the object identity pointer.  Pairs with Release() for manual lifetime control. |
| 方法 | `object weakRef(object obj)` | Weak references (Dart-inspired: WeakReference, Finalizer). Register a weak reference to obj.  The returned handle is the object pointer itself; use IsWeakRefValid to check if it is still alive.  When the object is freed, the weak ref is automatically invalidated. |
| 方法 | `bool isWeakRefValid(object obj)` | Check whether a weak reference is still valid (the target object has not been freed).  Returns true if valid. |
| 方法 | `void keepAlive(object obj)` | CLR-inspired: GC.KeepAlive. Keeps an object reachable past the call site, preventing the GC from collecting it before this point.  Increments the refcount so the object survives even in manual mode until explicitly released. |
| 方法 | `object clone(object obj)` | Object cloning (CLR-inspired: ICloneable, MemberwiseClone). Creates a shallow copy of the object.  The clone has the same runtime type and member values as the original.  Reference-type members share the same targets (shallow copy, not deep). The clone is added to the GC pool and returned. |
| 方法 | `Int64 alloc(Int32 byteCount)` | Native memory (moved from FFI.NativeMemory). Build C native content (arrays / scalars / structs) dynamically. cvm: memory_system_method.c (SystemMemoryNative* system calls). Conventions: - Addresses are passed as Int64 (0 = null / invalid). - Type names accept SL names ("Int32"/"string"...) and FFI short names ("i32"/"utf8"...). - Writes: i8==u8, i16==u16, i32==u32, i64==u64==ptr (bit-pattern aliases); reads must pick the sign/zero-extending variant. - Structs use C natural alignment (offset=round_up(cur,align), tail padded to the largest field alignment), e.g. fields "i32,i64,f32,f64" (max 64 fields). - writeUtf8 stores the SL string's data pointer (the string must stay alive; native side is read-only); copyUtf8 copies bytes (self-owned, no lifetime constraint). Allocation / free / type size. Allocate byteCount bytes of zeroed native memory, return the address (0 = failure). |
| 方法 | `bool free(Int64 addr)` | Free a block allocated by alloc (double-free is undefined). Overloads free(object) above; exact-match overload resolution picks this for Int64 args, so both can coexist. |
| 方法 | `Int32 sizeOf(string typeName)` | FFI type storage size in bytes: bool/i8/u8/f8=1, i16/u16/f16=2, i32/u32/f32=4, i64/u64/f64/ptr/utf8=8. Unknown type returns 0. |
| 方法 | `Int64 allocArray(Int32 count, string elemType)` | Allocate a C array of count elements (laid out by element type size, zeroed), return the base address.  Access elements with the read/write series + index*sizeOf offsets. |
| 方法 | `Int64 newInt8(Int32 value)` | Scalar builders (allocate + write, return the address). Build a native Int8 (i8/u8 share the bit pattern). |
| 方法 | `Int64 newInt16(Int32 value)` | Build a native Int16 (i16/u16 share the bit pattern). |
| 方法 | `Int64 newInt32(Int32 value)` | Build a native Int32 (i32/u32 share the bit pattern). |
| 方法 | `Int64 newInt64(Int64 value)` | Build a native Int64 (i64/u64/ptr share the bit pattern). |
| 方法 | `Int64 newFloat32(Float32 value)` | Build a native Float32. |
| 方法 | `Int64 newFloat64(Float64 value)` | Build a native Float64. |
| 方法 | `Int64 newBool(bool value)` | Build a native bool (1 byte). |
| 方法 | `Int64 newUtf8(string value)` | Build a utf8 string slot (8-byte address slot holding a pointer, not bytes).  Equivalent to newInt64 + writeUtf8. |
| 方法 | `bool readBool(Int64 addr, Int32 offset)` | Reads (addr + byte offset). Read a 1-byte bool. |
| 方法 | `Int32 readInt8(Int64 addr, Int32 offset)` | Read 1 byte signed (sign-extended to Int32). |
| 方法 | `Int32 readUInt8(Int64 addr, Int32 offset)` | Read 1 byte unsigned (zero-extended to Int32). |
| 方法 | `Int32 readInt16(Int64 addr, Int32 offset)` | Read 2 bytes signed (sign-extended to Int32). |
| 方法 | `Int32 readUInt16(Int64 addr, Int32 offset)` | Read 2 bytes unsigned (zero-extended to Int32). |
| 方法 | `Int32 readInt32(Int64 addr, Int32 offset)` | Read 4 bytes signed. |
| 方法 | `Int64 readUInt32(Int64 addr, Int32 offset)` | Read 4 bytes unsigned (zero-extended to Int64, keeps &gt; 2^31-1). |
| 方法 | `Int64 readInt64(Int64 addr, Int32 offset)` | Read 8 bytes signed (u64/ptr bit-pattern alias). |
| 方法 | `Int64 readUInt64(Int64 addr, Int32 offset)` | Read 8 bytes unsigned / a native pointer (same as readInt64). |
| 方法 | `Int64 readPtr(Int64 addr, Int32 offset)` | Read 8 bytes as a native pointer (same as readInt64). |
| 方法 | `Float32 readFloat32(Int64 addr, Int32 offset)` | Read a 4-byte single-precision float. |
| 方法 | `Float64 readFloat64(Int64 addr, Int32 offset)` | Read an 8-byte double-precision float. |
| 方法 | `string readUtf8(Int64 addr, Int32 offset)` | Read the char* stored in an 8-byte address slot, copied into an SL string. |
| 方法 | `bool writeBool(Int64 addr, Int32 offset, Int32 value)` | Writes (addr + byte offset). Write a 1-byte bool. |
| 方法 | `bool writeI8(Int64 addr, Int32 offset, Int32 value)` | Write 1 byte (i8/u8 share the bit pattern). |
| 方法 | `bool writeI16(Int64 addr, Int32 offset, Int32 value)` | Write 2 bytes (i16/u16 share the bit pattern). |
| 方法 | `bool writeI32(Int64 addr, Int32 offset, Int32 value)` | Write 4 bytes (i32/u32 share the bit pattern). |
| 方法 | `bool writeI64(Int64 addr, Int32 offset, Int64 value)` | Write 8 bytes (i64/u64/ptr share the bit pattern). |
| 方法 | `bool writeF32(Int64 addr, Int32 offset, Float32 value)` | Write a 4-byte single-precision float. |
| 方法 | `bool writeF64(Int64 addr, Int32 offset, Float64 value)` | Write an 8-byte double-precision float. |
| 方法 | `bool writeUtf8(Int64 addr, Int32 offset, string value)` | Write the SL string's data pointer into an 8-byte address slot (the string must stay alive; native side is read-only; use copyUtf8 when a self-owned copy is needed). |
| 方法 | `Int32 copyUtf8(Int64 addr, Int32 offset, string value, Int32 maxBytes)` | Copy string bytes to addr+offset (NUL-terminated, at most maxBytes-1 payload bytes); returns copied bytes (without NUL). |
| 方法 | `Int32 structSize(string fields)` | Struct layout (C natural alignment). Total struct size (tail padded to the largest field alignment). fields like "i32,i64,f32,f64" (SL or FFI short names, max 64). |
| 方法 | `Int32 structFieldOffset(string fields, Int32 index)` | Byte offset of field index (0-based); -1 on bad fields / index. |
| 方法 | `Int64 newStruct(string fields)` | Dynamically build a struct instance (zeroed allocation, no initialization), return the address.  Fill fields with the write/read series + structFieldOffset. |
| 方法 | `Array&lt;object&gt; dataToArray(object obj)` | data &lt;-&gt; Array&lt;object&gt; conversion. Purpose: structured data at the cvm layer can be converted into C struct data via dataToArray (then written to native memory / passed to special functions), and converted back via arrayToData given the per-node type layout. Convert a data object into a new Array&lt;object&gt;, one slot per member node (in declaration order).  Returns null on failure. |
| 方法 | `object arrayToData(Array&lt;object&gt; values, string fields)` | Build a data object (meta_kind = DATA) from values, laid out by the fields type string (comma-separated node types, e.g. "i32,f64,string,object"; SL or FFI short names, max 64 fields). Array elements are written to the members in order; fields past the array length stay null/zero.  Returns null on failure. |
| 方法 | `Int64 dataToNativeStruct(string structName, object obj)` | Named data (data DataName{...}) &lt;-&gt; C struct conversion. Layout: C natural alignment, matching structSize/structFieldOffset rules.  Member slot mapping: - scalar members (bool/i8..i64/f16..f64): inline, slot width - string member: 8-byte char* slot (native side read-only) - nested data member: recursively inlined (C nested struct) - enum member: 4-byte Int32 slot (underlying constant) - class member: 8-byte object address slot (SystemPtrFromObject semantics; read back via SystemPtrToObject-like restore) The returned native address is NOT managed by SL memory management; the caller owns it (free it when done). Serialize a named data instance into a freshly allocated C struct block (zero-filled then filled).  structName is the corresponding C struct definition name, used for logging only -- the layout is fully driven by the SL data definition, so both sides must agree on it.  Returns the native address, 0 on failure (non-data object / null nested data member). |
| 方法 | `object nativeStructToData(Int64 addr, string typeName)` | Build a new named data instance from native memory, resolving the data class by typeName (full or short name).  The sugar form var dn = Memory.nativeStructToData&lt;DataName&gt;( addr ) injects "DataName" as typeName at the front end, i.e. it calls Memory.nativeStructToData( addr, "DataName" ) Strings are copied into SL-owned objects; class members are restored by address (object must still be alive).  Returns null on failure (unknown type / bad address / layout mismatch). |
