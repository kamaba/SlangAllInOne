# SLang 跨平台渲染引擎设计 · 04 原生绑定契约与跨平台策略

- 所属文档集：`Render/doc/`（01 总览 · 02 Unity 参考 · 03 模块详设 · **04 原生绑定与跨平台** · 05 路线图与规范 · 06 图像编解码）
- 版本：v0.4
- 本章定义 SL 侧与 C 渲染后端之间的**全部调用契约**，以及跨平台/跨图形 API 策略。
- 机制依据：SLang FFI（`md/project/ffi.md`）与系统方法（`md/syntax/system_method.md`）。
- **本契约在 M0 冻结 v1；之后只增不改**（新增符号允许，改名/改签名须升版本并同步全部调用点）。
- 图像编解码域（`slr_image_*` / `slr_svg_*` / `slr_blob_*`）的**完整符号表在 06 §5**，本章 §4.8 为索引。

---

## 1. 调用三级策略（D8 展开）

> 原则：**尽量不用字符串分发的 SystemCall，优先使用 FFI 原生对应**；FFI 表达不了的场景才落到系统方法。

### 1.1 T1 —— 原生 FFI 声明式绑定（首选，覆盖 ≥95% 调用）

```sl
@DllStaticImport( "SLangRender", "slr_texture_create", "ptr->i64" )
static Int64 ffi_textureCreate( Int64 descPack )
{
    ret 0    # fallback：后端 DLL 未部署时走这里（返回 0 句柄 -> 上层降级 Software）
}
```

| 特性 | 说明 |
|---|---|
| 绑定机制 | `@DllStaticImport(静态名, C符号, sig)` / `@DllImport(路径或别名, C符号, sig)`；cvm 装配期（run 前）解析符号并把调用点改写为 `CallFFIStatic(77)` |
| 运行开销 | **零 SL 帧**：弹参 → x64 ABI 派发 → 压结果，不进 SL 调用栈 |
| 库生命周期 | jsonc `"static"` 静态名预载，进程级常驻、永不 release |
| 失败语义 | 绑定失败（库缺失/符号缺失/sig 非法）→ 运行期**回退执行 SL 函数体**；函数体即无后端环境的 stub（返回 0/false + 可选日志） |
| 限制 | 仅 x64 ABI；参数 ≤ 6；不支持 varargs；sig 必须是 FFI 短名；带 `Ptr` 必须手写 sig；带绑定的函数不参与自动 inline |

### 1.2 T2 —— 系统方法 SystemMethodCall（兜底，少数场景）

`.jsonc systemCalls[]` 声明（`name`/`returnType`/`params`/`isVariadic`/`cvmFunction` C 符号），VM `EIROpCode.CallSystemMethod` 分发。**仅以下三类场景允许新增 T2**：

1. **构造 SL 对象并返回**：C 侧需要压回一个 SL 对象（着色器反射参数表 `Array<ShaderParameter>`、图像解码返回 `Texture` 等）。
2. **迁移期对象直传**：`Render.cmdDrawMesh(mesh, material, m, vp)` 这类把 SL 对象交给 C 解析的兼容接口（cvm_render_lib 解析对象 → 拆句柄 → 转发 T1）。
3. **变参封装**：`isVariadic` 的窄接口（仅当无法用 ≤6 参 + 描述符表达时）。

> 注意区分：`SystemCallExternalFunction` 本身也是一个（变参的）系统方法。**T2 指「专用签名的窄系统方法」；T3 要淘汰的是「字符串名 + 变参 + 装箱 object」这种用法**，不是系统方法机制本身。

### 1.3 T3 —— `SystemCallExternalFunction("Render.xxx", ...)`（冻结、迁移、删除）

- **冻结**：自本设计通过起，Render 库任何新代码禁止新增 T3 调用。
- **迁移**：存量调用按 §5 映射表迁到 `RenderFFI.sl` 的 T1（个别到 T2）。
- **删除**：M3 验收标准包含「Render 库 .sl 源码中 `SystemCallExternalFunction` 出现次数 = 0」，随后从 Core 移除 `Render.*` 字符串分发注册。

## 2. 绑定面组织（RenderFFI.sl + Render.jsonc）

### 2.1 单一绑定面

`Pipeline/RenderFFI.sl` 是 SL 侧**唯一**允许出现 `@DllStaticImport`/`@DllImport`/`SystemFFICallXxx`/`SystemCallExternalFunction` 的文件。其它 .sl 一律调用本文件的静态函数（`RenderFFI.ffi_xxx`）。收益：契约单点维护、审计一目了然、迁移可控。

```sl
# RenderFFI.sl —— 原生绑定面（T1）
# 命名：SL 函数 ffi_<域><动作>；C 符号 slr_<域>_<动作>；sig 用 FFI 短名
# 每个 fallback 体：查询类返回 0/false；创建类返回 0 句柄；void 类空体

public class RenderFFI
{
    # ── 设备 ─────────────────────────────────────────
    @DllStaticImport( "SLangRender", "slr_device_create", "i32,ptr->i64" )
    static Int64 ffi_deviceCreate( Int32 backend, Int64 descPack )
    {
        ret 0    # 无后端 DLL：触发 GfxBackend.selectBest 降级到 Software
    }

    @DllStaticImport( "SLangRender", "slr_device_present", "" )   # 注意：sig 省略返回段
    static void ffi_devicePresent()
    {
    }

    # ── 纹理 ─────────────────────────────────────────
    @DllStaticImport( "SLangRender", "slr_texture_create", "ptr->i64" )
    static Int64 ffi_textureCreate( Int64 descPack ) { ret 0 }

    @DllStaticImport( "SLangRender", "slr_texture_upload", "i64,ptr,i32,i32,i32->bool" )
    static bool ffi_textureUpload( Int64 tex, Int64 pixels, Int32 w, Int32 h, Int32 format )
    { ret false }
    ...   # 全量符号表见 §4
}
```

### 2.2 Render.jsonc 配置

```jsonc
{
  "dllImports": [
    {
      // 后端动态库：随平台部署（win: slang_render.dll / linux: libslang_render.so / mac: libslang_render.dylib）
      "path": "../../out/bin/slang_render.dll",
      "name": "slang_render",
      "alias": "SLangRender",
      "static": "SLangRender"        // @DllStaticImport 的静态名，进程级预载
    }
    // 图像解码等辅助库同段追加（slr_image_*），见 §4.8
  ],
  "systemCalls": [
    // T2 兜底接口（专用签名，非字符串分发）：迁移期 cmdDrawMesh、反射表构造等
    // { "name": "RenderFFIReflectParams", "returnType": "object", "params": [...], "cvmFunction": "slr_t2_reflect_params" }
  ]
}
```

要点：

- `"static": "SLangRender"` 是 T1 的锚；别名 `alias` 供 `@DllImport("SLangRender", ...)` 三级解析兜底。
- `dllImports` 随模块导出自动合并到引用方，宿主工程无需重复配置。
- 平台路径差异：M6 起按目标平台部署对应库文件到同一路径名（构建脚本负责），jsonc 保持单一 path；或构建时按平台生成 jsonc 变体。

## 3. C 侧函数设计规范

### 3.1 命名与形态

- 符号前缀 `slr_`（SLang Render），全小写下划线分词：`slr_<域>_<动作>`，域见表 §4。
- 一律 `extern "C"` 扁平 ABI（FFI 不支持 C++ 成员函数）。
- 句柄类型统一 `int64_t`（容纳原生指针）；描述符堆索引等小整数用 `int32_t`。
- 返回值约定：`bool` = 成功与否；`int64_t` = 句柄（**0 恒为无效**）；`int32_t` = 数量/索引/枚举。
- 枚举值与 SL 侧 `enum`（即 Int32）**逐值一致**，单点定义在后端头 `slr_types.h`（含 04 §4 各表引用的 EGraphicsBackend/EResourceState/ETextureFormat/... 值表）。

### 3.2 参数规则（≤ 6 参）

| 场景 | 处理 |
|---|---|
| 参数 ≤ 6 | 直接平铺进签名，sig 短名标注 |
| 参数 > 6 / 可变结构 | **描述符打包**：SL 侧 `Memory.alloc(n)` + `Memory.writeI32/writeF64/...` 组装，以 `ptr` 传入（布局见 §3.4） |
| 字符串（title/源码/路径） | `utf8` 直传 |
| 矩阵 / CBUFFER 数据 | SL 侧把 16 个 float（或整个 staging）写入原生内存块，`ptr` + `i64 sizeBytes` 传入 |
| 数组（命令流/反射表） | 打包进原生内存块，`ptr` + `i32 count`（或块头自描述） |

### 3.3 sig 书写规则

- 必须用 **FFI 短名**：`i32 / i64 / f32 / f64 / bool / ptr / utf8`（静态绑定不做 SL 类型名映射）。
- 返回 void 的函数**省略返回段**（`"i32,ptr"`），`"->void"` 是非法写法。
- 任何含 `ptr` 参数/返回的函数**必须手写 sig**（编译期推导排除 Ptr）。

### 3.4 描述符打包布局（示例：GpuTexture 创建）

> 通用规则：字段按 8 字节对齐排布；头部放 `magic(i32) + version(i32)`；变长字段（枚举数组）以「ptr + count」内嵌。完整布局表在 M0 冻结后补入本节附录（实现期产出，与 `slr_types.h` 同步）。

```sl
# SL 侧组装（GpuTexture.create 内部）
Int64 p = Memory.alloc( 64 )
Memory.writeI32( p, 0, 0x53524C54 )        # magic 'SLRT'
Memory.writeI32( p, 4, 1 )                 # version
Memory.writeI32( p, 8, this.width )
Memory.writeI32( p, 12, this.height )
Memory.writeI32( p, 16, this.depth )
Memory.writeI32( p, 20, this.mipLevels )
Memory.writeI32( p, 24, this.arraySize )
Memory.writeI32( p, 28, this.format )      # ETextureFormat
Memory.writeI32( p, 32, this.dimension )
Memory.writeI32( p, 36, this.usageFlags )
Memory.writeI32( p, 40, this.sampleCount )
# utf8 名字（可选）：Memory.newUtf8 -> 指针写偏移 48
this.handle = RenderFFI.ffi_textureCreate( p )
Memory.freeNative( p )
```

### 3.5 cvm_render_lib 的定位（调整）

`cvm_render_lib/*.c` 从「字符串分发粘合层」转型为：

1. **T2 兼容注册器**：承载 §1.2 列出的迁移期系统方法（`cvmFunction` 符号），内部解析 SL 对象后转发 T1 符号；
2. **对象→描述符打包辅助**：为 `Mesh/Material` 等复杂对象提供「对象字段 → 原生内存块」的读取工具（供 T2 内部使用）；
3. 终态（T3 删除后）：仅剩 2 的职责，且逐步被 SL 侧 `Memory.write*` 直接打包取代。

### 3.6 命令流布局（slr_cmd_execute_stream 的 ptr 指向）

```
偏移      类型      含义
0         i32       magic = 0x534C4D43 ('SLMC')
4         i32       version = 1
8         i32       commandCount
12        i32       argOffset      # args 段相对块首的字节偏移
16        i32       floatOffset    # floats 段相对块首的字节偏移
20        (pad 4)
24        i32[]     opcodes[commandCount]      # ECommandOpcode
argOffset   i64[]   args                        # 每命令消费个数由 opcode 决定
floatOffset f32[]   floats                      # 视口/清屏色等浮点参数
```

SL 侧 `CommandQueue.execute()` 负责组装；后端按 opcode 表解释执行（GL 后端直译为 GL 调用，D3D12 后端回放进真正的 GraphicsCommandList）。

## 4. slr_ 符号全量表（T1 契约主体）

> 表中「SL 签名」为 RenderFFI.sl 中的函数形态；「sig」为 `@DllStaticImport` 第 3 实参。返回 void 的函数 sig 省略返回段。枚举一律 `i32` 传值（值表见 `slr_types.h`，与 SL enum 一致）。

### 4.1 窗口域 `slr_window_*` / `slr_win32_*` / `slr_wl_*` / `slr_surface_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_window_create | ( system:i32, title:utf8, w:i32, h:i32, flags:i32 ) -> bool | `"i32,utf8,i32,i32,i32->bool"` | flags 位打包 fullscreen/resizable/visible；x/y 默认居中 |
| slr_window_destroy | ( hwnd:i64 ) | `"i64"` | |
| slr_window_resize | ( hwnd:i64, w:i32, h:i32 ) | `"i64,i32,i32"` | |
| slr_window_set_title | ( hwnd:i64, title:utf8 ) | `"i64,utf8"` | |
| slr_window_set_fullscreen | ( hwnd:i64, on:bool ) | `"i64,bool"` | |
| slr_window_pump | ( hwnd:i64 ) -> bool | `"i64->bool"` | false = 收到退出消息 |
| slr_window_poll_event | ( hwnd:i64, index:i32, evOut:ptr ) -> bool | `"i64,i32,ptr->bool"` | 事件结构写出（type/a/b） |
| slr_window_framebuffer_size | ( hwnd:i64, sizeOut:ptr ) | `"i64,ptr"` | 高 DPI 实际可绘制尺寸 |
| slr_win32_create | ( class:utf8, title:utf8, x:i32, y:i32, w:i32, h:i32 ) -> i64 | `"utf8,utf8,i32,i32,i32,i32->i64"` | Win32 特化（6 参上限内） |
| slr_win32_set_dpi_awareness | ( level:i32 ) -> bool | `"i32->bool"` | |
| slr_win32_get_dc / slr_win32_release_dc | ( hwnd:i64 ) -> i64 / ( hwnd:i64, hdc:i64 ) | `"i64->i64"` / `"i64,i64"` | OpenGL 需要 |
| slr_win32_show / slr_win32_peek / slr_win32_post_quit | ( hwnd:i64 ) | `"i64"` | |
| slr_win32_client_size | ( hwnd:i64, sizeOut:ptr ) | `"i64,ptr"` | w/h 写出 |
| slr_x11_create | ( title:utf8, x:i32, y:i32, w:i32, h:i32 ) -> i64 | `"utf8,i32,i32,i32,i32->i64"` | |
| slr_x11_pump | ( display:i64 ) -> bool | `"i64->bool"` | |
| slr_surface_bind | ( system:i32, surface:i64 ) | `"i32,i64"` | Android/iOS/Web 表面注入 |
| slr_surface_changed / slr_surface_destroyed | ( surface:i64, w:i32, h:i32 ) / ( surface:i64 ) | `"i64,i32,i32"` / `"i64"` | |

### 4.2 后端与设备域 `slr_backend_*` / `slr_caps_*` / `slr_device_*` / `slr_gl_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_backend_available | ( backend:i32 ) -> bool | `"i32->bool"` | 进程可用后端探测 |
| slr_backend_current_window_system | ( ) -> i32 | `"->i32"` | |
| slr_backend_api_version | ( ) -> utf8 | `"->utf8"` | 当前 API 版本串 |
| slr_caps_query | ( backend:i32, capsOut:ptr ) -> bool | `"i32,ptr->bool"` | 能力集整块写出，SL 读回填 GfxCapabilities（替代「返回 SL 对象」） |
| slr_device_create | ( backend:i32, descPack:ptr ) -> i64 | `"i32,ptr->i64"` | **统一入口**：D3D12/D3D11/Vulkan/Metal/GL/GLES/WebGPU/Software 按 backend 分发；descPack 含 msaa/vsync/debug/featureLevel/gl 版本/extensions(utf8 指针) |
| slr_device_destroy | ( ) | `""` | |
| slr_device_wait_gpu | ( ) | `""` | |
| slr_device_present | ( ) | `""` | 内部按后端分发：DXGI Present / vkQueuePresentKHR / glSwapBuffers / Canvas2D blit（Software@Web，D7） |
| slr_device_backbuffer_index | ( ) -> i32 | `"->i32"` | SwapChain index 修复 |
| slr_gl_context_create | ( api:i32, major:i32, minor:i32, profile:i32, hwnd:i64, display:i64 ) -> i64 | `"i32,i32,i32,i32,i64,i64->i64"` | WGL/GLX/EGL/CGL |
| slr_gl_context_destroy | ( ctx:i64 ) | `"i64"` | |
| slr_gl_make_current | ( ctx:i64, hwnd:i64 ) | `"i64,i64"` | |
| slr_gl_swap_buffers | ( hwnd:i64 ) | `"i64"` | |
| slr_gl_finish | ( ) | `""` | |
| slr_gl_viewport | ( x:i32, y:i32, w:i32, h:i32 ) | `"i32,i32,i32,i32"` | |
| slr_gl_enable_debug_output | ( on:bool ) | `"bool"` | |
| slr_gl_supports_extension | ( name:utf8 ) -> bool | `"utf8->bool"` | |

> 现状的 `Render.createDeviceD3D12 / createDeviceVulkan / ...` 每后端一函数的设计**收敛**为 `slr_device_create(backend, desc)` 单入口（后端差异内化到 C 层），减少符号面。

### 4.3 资源域 `slr_buffer_*` / `slr_cb_*` / `slr_texture_*` / `slr_sampler_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_buffer_create | ( descPack:ptr ) -> i64 | `"ptr->i64"` | sizeBytes/stride/count/heapType/state |
| slr_buffer_destroy | ( buf:i64 ) | `"i64"` | |
| slr_buffer_upload | ( buf:i64, data:ptr, sizeBytes:i64 ) -> bool | `"i64,ptr,i64->bool"` | 交错顶点/索引字节流 |
| slr_cb_update | ( cb:i64, data:ptr, sizeBytes:i64 ) -> bool | `"i64,ptr,i64->bool"` | 常量缓冲刷新（附录 B 布局） |
| slr_texture_create | ( descPack:ptr ) -> i64 | `"ptr->i64"` | 布局见 §3.4 示例 |
| slr_texture_destroy | ( tex:i64 ) | `"i64"` | |
| slr_texture_upload | ( tex:i64, pixels:ptr, w:i32, h:i32, format:i32 ) -> bool | `"i64,ptr,i32,i32,i32->bool"` | CPU 像素上传（含压缩块） |
| slr_texture_generate_mips | ( tex:i64 ) | `"i64"` | |
| slr_texture_view_create | ( tex:i64, viewType:i32, format:i32, mip:i32, mipCount:i32, slice:i32 ) -> i32 | `"i64,i32,i32,i32,i32,i32->i32"` | 返回描述符索引（6 参上限内） |
| slr_sampler_create | ( filter:i32, addrU:i32, addrV:i32, aniso:i32, comparison:i32 ) -> i32 | `"i32,i32,i32,i32,i32->i32"` | |
| slr_resolve_texture | ( src:i64, dst:i64 ) -> bool | `"i64,i64->bool"` | MSAA resolve |

> `Render.resourceBarrier / uploadBuffer / uploadTexture / uploadConstantBuffer` 等旧名并入上表（屏障随命令流走 §4.6 的 opcodes，不再独立符号）。

### 4.4 着色器域 `slr_shader_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_shader_compile | ( name:utf8, source:utf8, entry:utf8, target:utf8, stage:i32 ) -> i64 | `"utf8,utf8,utf8,utf8,i32->i64"` | 5 参，HLSL 源码直传；返回模块句柄 |
| slr_shader_reflect | ( module:i64, outPack:ptr ) -> i32 | `"i64,ptr->i32"` | 反射参数表写出（count + name/utf8Ptr/type/bindPoint/bindSpace/stageFlags 数组），SL 读回组装 `Array<ShaderParameter>` |
| slr_shader_destroy | ( module:i64 ) | `"i64"` | |

### 4.5 状态与绑定域 `slr_pso_*` / `slr_root_*` / `slr_heap_*` / `slr_dset_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_pso_graphics_create | ( descPack:ptr ) -> i64 | `"ptr->i64"` | vs/ps 句柄 + inputLayout/blend/raster/depth + rtFormats(ptr+count) + depthFormat + msaa + topology |
| slr_pso_compute_create | ( name:utf8, cs:i64 ) -> i64 | `"utf8,i64->i64"` | |
| slr_pso_destroy | ( pso:i64 ) | `"i64"` | |
| slr_root_signature_create | ( descPack:ptr ) -> i64 | `"ptr->i64"` | 参数数组 + 静态采样器数组（ptr+count 两段） |
| slr_root_signature_destroy | ( sig:i64 ) | `"i64"` | |
| slr_heap_create | ( type:i32, capacity:i32, shaderVisible:bool ) -> i64 | `"i32,i32,bool->i64"` | |
| slr_dset_apply | ( sig:i64, bindingsPack:ptr ) -> bool | `"i64,ptr->bool"` | CBV/SRV/UAV/Sampler 槽位数组打包 |

### 4.6 命令 / 队列 / 同步 / 交换链域 `slr_cmd_*` / `slr_queue_*` / `slr_fence_*` / `slr_swapchain_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_cmd_begin | ( name:utf8 ) -> i64 | `"utf8->i64"` | 分配后端命令列表 |
| slr_cmd_end | ( cmd:i64 ) | `"i64"` | 封口 |
| slr_cmd_execute_stream | ( queue:i64, cmd:i64, stream:ptr, count:i32 ) -> bool | `"i64,i64,ptr,i32->bool"` | **命令流整包提交**（布局 §3.6，D1） |
| slr_cmd_list_create | ( allocator:i64 ) -> i64 | `"i64->i64"` | 底层列表（高级用途） |
| slr_cmd_list_begin / slr_cmd_list_close / slr_cmd_list_destroy | ( list:i64 ) | `"i64"` | |
| slr_allocator_create | ( type:i32 ) -> i64 | `"i32->i64"` | |
| slr_allocator_reset / slr_allocator_destroy | ( alloc:i64 ) | `"i64"` | |
| slr_queue_create | ( type:i32 ) -> i64 | `"i32->i64"` | Graphics/Compute/Copy |
| slr_queue_destroy | ( queue:i64 ) | `"i64"` | |
| slr_queue_wait / slr_queue_signal | ( queue:i64, fence:i64, value:i64 ) | `"i64,i64,i64"` | |
| slr_queue_wait_idle | ( queue:i64 ) | `"i64"` | |
| slr_fence_create | ( ) -> i64 | `"->i64"` | |
| slr_fence_value | ( fence:i64 ) -> i64 | `"i64->i64"` | |
| slr_fence_wait | ( fence:i64, target:i64 ) | `"i64,i64"` | 阻塞等待 |
| slr_fence_destroy | ( fence:i64 ) | `"i64"` | |
| slr_swapchain_create | ( descPack:ptr ) -> bool | `"ptr->bool"` | w/h/bufferCount/format/hwnd |
| slr_swapchain_present | ( vsync:i32 ) | `"i32"` | |
| slr_swapchain_resize | ( w:i32, h:i32 ) | `"i32,i32"` | |
| slr_swapchain_destroy | ( ) | `""` | |

> 旧的 `Render.cmdSetViewport / cmdClear / cmdDraw / ...` 二十余个逐命令符号**全部取消**——命令语义进命令流（opcodes），只有 begin/end/execute_stream 三个符号。这是 D1+D8 的直接收益：符号面从 ~60 缩到 ~50，且逐命令调用不再逐次跨 FFI。

### 4.7 呈现与统计域

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_stats_draw_calls | ( ) -> i32 | `"->i32"` | 后端统计 |
| slr_stats_reset | ( ) | `""` | |
| slr_gpu_timestamp_begin / slr_gpu_timestamp_end | ( slot:i32 ) | `"i32"` | M5 |
| slr_gpu_timestamp_us | ( slot:i32 ) -> f64 | `"i32->f64"` | M5 |

### 4.8 辅助域（图像编解码 / 回读）——索引

> 本域完整符号表与设计见 **06 §5**（唯一权威，避免双表漂移）。概览：

| 符号族 | 覆盖 | 详见 |
|---|---|---|
| slr_image_probe_file / _mem | 不解码取宽高/格式/透明/动图帧数 | 06 §5.1 |
| slr_image_decode_file / _mem / free_pixels | 解码到原生像素块（A 路径零拷贝） | 06 §5.2 |
| slr_image_encode + slr_blob_ptr/size/save/free | 编码产物 blob 与落盘（截图/CI 对比） | 06 §5.3 |
| slr_svg_parse / rasterize / free | SVG 文档句柄 + 任意尺寸光栅化 | 06 §5.4 |
| T2：RenderImageDecodeFile / DecodeMem / EncodeBuffer / ProbeFile | 构造 SL 对象返回（B 路径，长期保留） | 06 §5.5 |
| slr_device_readback_pixel | 帧缓冲回读（Readback 堆语义，供截图编码） | 06 §6.2 |

## 5. 存量迁移映射（T3 → T1/T2）

迁移规则（覆盖现有 `SystemCallExternalFunction("Render.xxx")` 全部 ~90 个调用点，另加 `Image.*` 18 个调用点）：

| 旧 T3 名（前缀 Render.） | 去向 |
|---|---|
| createWindow / win32CreateWindow / x11CreateWindow / bindNativeSurface / ... | `slr_window_* / slr_win32_* / slr_x11_* / slr_surface_*`（§4.1） |
| createDeviceD3D12 / D3D11 / Vulkan / Metal / Software / createWebGLContext | `slr_device_create(backend, desc)`（§4.2 收敛） |
| createGLContext / glMakeCurrent / glSwapBuffers / glFinish / glViewport / glEnableDebugOutput / destroyGLContext | `slr_gl_*`（§4.2） |
| getAvailableBackends / getCurrentWindowSystem / queryCapabilities / getGraphicsApiVersion / supportsGLExtension | `slr_backend_* / slr_caps_query`（§4.2） |
| createResource / destroyResource / uploadBuffer / uploadConstantBuffer | `slr_buffer_* / slr_cb_update`（§4.3） |
| resourceBarrier | 命令流 opcode `ResourceBarrier`（§3.6） |
| createTexture / uploadTexture / generateMipmaps / createTextureView / createSampler | `slr_texture_* / slr_sampler_*`（§4.3） |
| compileHlsl | `slr_shader_compile`（§4.4） |
| createGraphicsPipeline / createComputePipeline / destroyPipeline / createRootSignature / destroyRootSignature / createDescriptorHeap / applyDescriptorSet | §4.5 |
| cmdBegin / cmdEnd / cmdSetViewport / ... / cmdEndEvent / cmdClearCommands | `slr_cmd_begin / slr_cmd_end` + **命令流 opcodes**（§4.6） |
| createCommandQueue / executeCommandBuffer / queueWait / queueSignal / queueWaitIdle / createCommandAllocator / resetCommandAllocator / createCommandList / commandListBegin / commandListClose | §4.6（executeCommandBuffer → `slr_cmd_execute_stream`） |
| createFence / signalFence / getFenceValue / waitFence / destroyFence | §4.6 |
| createSwapChain / presentSwapChain / resizeSwapChain / destroySwapChain | §4.6 |
| initialize / shutdown / isReady / beginFrame / endFrame / present / setViewport / clear / getDrawCallCount / resetStats | SL 侧内部转发（03 §4.12）+ `slr_device_present / slr_stats_*` |
| **cmdDrawMesh（对象直传）** | **T2 迁移期保留**（cvm_render_lib 注册专用系统方法），终态删除（Mesh→VB/IB 上传路径替代） |
| **compileShader / releaseShader / findShader / setUniform*（按名 uniform 族）** | **T2 迁移期保留**（GL 后端直用），终态删除（D2） |
| **loadTexture** | `slr_image_decode` 族（T1，06 §5）+ SL 侧组装 Texture 对象 |
| **`Image.*` 全族（load/save/probe/probeFile/decode/decodeAs/encode/encodeAs/pngDecode/pngEncode/jpegDecode/jpegEncode/jpegExif/webpDecode/webpEncode/webpFrames/svgParse/svgRasterize，共 18 个调用点） | 见 **06 §5.6** 专用迁移表（T1 `slr_image_*/slr_svg_*` + T2 `RenderImage*` 四个对象接口；`jpegExif`/`webpFrames` 并入选项与探测出参） |

迁移批次：M1（窗口/设备/呈现/清屏——跑通三角形所需）→ M2（资源/着色器/状态）→ M3（命令流切换 + 删除 T3）。每批验收 = 对应模块 .sl 中 T3 调用清零。

## 6. 限制与跨架构注意

| 项 | 影响 | 对策 |
|---|---|---|
| FFI 仅 x64 ABI（`slr_ffi_call` 静态展开） | Win/Linux/mac 桌面 OK；**Android arm64 / iOS arm64 暂不可用 T1** | M6 前置任务：VM FFI 层扩展 arm64 派发（`gen_sl_ffi_call.py` 增加目标）；未扩展前移动端降级走 T2 系统方法（语义同表，包装层自动切换） |
| 参数 ≤ 6 | 超参函数无法直连 | 描述符打包（§3.4），契约已按此设计 |
| 库 ≤ 32、回调槽 ≤ 8 | 渲染后端 1-2 个库足够；**不使用 FFI 回调做窗口事件** | 事件一律轮询（`slr_window_poll_event`），无回调依赖 |
| `@DllStaticImport` 函数不参与自动 inline | 无 | 绑定函数保持一行转发形态，不写逻辑 |
| 绑定失败静默回退函数体 | 无后端 DLL 时表现为「全部返回 0/false」 | RenderFFI 首次调用做一次探测（`ffi_backendAvailable` 失败即置全局 `bindingOk=false`），显式告警一次并触发 Software 降级 |

## 7. 跨平台策略

### 7.1 平台 × 后端矩阵

| 平台 | 首选 | 降级链 | 窗口系统 |
|---|---|---|---|
| Windows 桌面 | D3D12 | D3D11 → OpenGL | Win32 |
| Linux 桌面 | Vulkan | OpenGL | X11（Wayland v1.1） |
| macOS | Metal | — | Cocoa |
| iOS | Metal | — | UIKit surface |
| Android | Vulkan | OpenGLES 3.0 | ANativeWindow |
| Web | WebGPU | WebGL2 → WebGL1 → Canvas2D(Software 光栅) | HTMLCanvasElement（OffscreenCanvas 为 M7 演进） |
| CI/无头 | Software | — | Headless |

### 7.2 能力降级表（GfxCapabilities → 管线行为）

| 能力位 | 关闭时管线行为 |
|---|---|
| supportsCompute | 禁用 compute 路径（mipmap 生成走后端内置算法） |
| supportsMSAA / sampleCount | 自动降到 1x，跳过 ResolvePass |
| supportsGeometryShader / Tessellation | 忽略（v1 不用） |
| supportsRayTracing / MeshShader / VRS | 预留，v1 不用 |
| BC/ETC2/ASTC | 纹理上传时按平台选压缩格式；不支持则解码为 RGBA8 |
| supportsBindless | 关（v1 全部走描述符表） |
| supportsTimelineFence | WebGPU 无完整时间线围栏 → 降级为 OnSubmittedWorkDone 事件轮询 |
| WebGPU adapter 可选特性（timestamp-query 等） | 关闭对应能力：GPU 时间戳统计退化为 CPU 侧近似 |
| constantBufferOffsetAlignment(256) | CBUFFER 写入按该值对齐（附录 B 的平台差异项） |

### 7.3 后端实现策略（C 层）

| 后端 | 策略 |
|---|---|
| D3D12 | 契约的本义目标：DescriptorHeap/RootSignature/PSO/Barrier/Fence 一一对应 |
| Vulkan | RootSignature→PipelineLayout+DescriptorSetLayout；HLSL 经 DXC 转 SPIR-V；屏障由后端按命令流状态机推导（v1 显式屏障透传） |
| Metal | RootSignature→Argument Buffer；HLSL 经 Metal 后端转 MSL（或直接写 MSL 变体，M6 决策） |
| WebGPU | RootSignature→BindGroupLayout/PipelineLayout；PSO→GPURenderPipeline；DescriptorHeap/Set→BindGroup；HLSL→WGSL 转译（DXC→SPIR-V→Tint 或 Tint 直转，M6 定单点方案）；Fence→OnSubmittedWorkDone；PSO 用 createRenderPipelineAsync 预热避免首帧卡顿 |
| D3D11 | 半显式：PSO→状态对象缓存；DescriptorSet→绑定槽翻译；Fence→D3D11 Fence 扩展或事件查询 |
| OpenGL/GLES/WebGL | 全模拟：VAO+Program 状态缓存、屏障为空操作、`glFlush` 当 fence；PSO 首绑定时应用状态差量 |
| Canvas 2D（Software@Web 呈现） | Software 光栅帧缓冲 → putImageData/drawImage 呈现到 H5 Canvas；不封装 Canvas2D 矢量绘制 API（那是宿主 UI 层职责）；Worker + OffscreenCanvas 列 M7 |
| Software | 同 D3D12 语义的 CPU 实现：足够跑通全流程做单元测试与 CI 截图对比；Web 平台上其帧缓冲即 Canvas 2D 呈现的像素来源 |

**SL 侧统一语义**（D5）：SL 代码不出现 `if isGlStyle()` 的管线分支；差异全部下沉 C 层。现存的 GL 分支（GfxDevice.swapBuffers/present/waitForGpu）收敛到后端 `slr_device_present`/`slr_device_wait_gpu` 内部。

### 7.4 坐标系与裁剪约定

- 右手系，+Y 上，+Z 前（与现有 Camera/Float32_3.forward 一致）。
- 投影：DX 风格深度 [0,1]（剔除平面提取已按此写，near=row2）。
- NDC：v1 统一 DX 风格；GL 后端在投影矩阵里做 Z 翻转（后端或 MatrixUtil 统一处理，单点决策）。
- UV：左上原点；fullscreen VS 里已做 `1-y` 翻转，保持。
