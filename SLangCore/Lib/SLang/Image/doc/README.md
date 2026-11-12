# SLangImage 模块 —— CPU 图像解码/编码

- 模块名：`SLangImage`（namespace `Image`），jsonc 锚点：`SLImage/Image.jsonc`
- 后端：`sl_image_lib.dll`（stb_image v2.31 + stb_image_write v1.17，公有领域 OR MIT-0 双许可；WIC 系统组件兜底 TIFF/ICO/WebP 解码、TIFF 编码）
- 状态：v0.1，ImageTest 54 项全绿（`SLangCore\test\Other\ImageTest\`）

## 目录结构

```
Image/
├── SLImage/                    # SL 层模块工程（jsonc 锚点在此）
│   ├── Image.jsonc             # 模块清单：compileFiles 10 个 .sl + dllImports + vmDlls + struct
│   ├── Image.sp
│   ├── ImageFormat.sl          # EImageFormat / EPixelFormat / EColorSpace / EInterpolation / EOrientation / ImageErrorCode
│   ├── (Color.sl 已删除)       # 8bit RGBA 颜色合并为 Std 根级 ColorInt（Std/ColorInt.sl），模块经 references 引用 Std
│   ├── ImageBuffer.sl          # 紧密像素容器（纯 SL：读写像素/fill/flipY/crop/convertTo/resize）
│   ├── ImageInfo.sl            # 头部探测元信息（纯 SL magic 嗅探 + 门面）
│   ├── ImageFfi.sl             # C 层 FFI 静态绑定 + 内存搬运（本模块核心）
│   ├── ImageIO.sl              # 门面：load/save/probe/encode/decode/convert
│   ├── Png.sl / Jpeg.sl / Webp.sl / Svg.sl   # 容器模型与选项（编解码本体已下沉 FFI）
│   └── export/DebugCode/       # Front 调试快照（Code/Token/Node/Meta/IR）
├── cvm_image_lib/              # C 层 VS 工程
│   ├── vm_sl_image.h           # 公开契约（22 个 sli_* 导出，普通 C ABI）
│   ├── sl_image.c              # 槽表/粘性错误/格式嗅探/probe/解码编码主路
│   ├── sl_image_internal.h
│   ├── Codec/sl_image_stb.c    # stb 唯一 IMPLEMENTATION 编译点
│   ├── Codec/sl_image_wic.c    # WIC 兜底（纯 C lpVtbl 调用，零外部依赖）
│   ├── cvm_sl_image_lib.vcxproj(.filters)   # VS 工程（Release|x64 → sl_image_lib.dll）
│   ├── third_party/stb/        # stb_image.h / stb_image_write.h + LICENSE.md
│   └── x64/Release/            # 本地构建输出
└── doc/README.md               # 本文档
```

## 核心契约

- **像素**：恒 RGBA8、4 字节/像素、top-down；非 RGBA8 buffer 编码前经 `convertTo(Rgba8)`
- **句柄**：图像/blob 句柄 1 起始，0 = 无效；用完必须 `libImageFree` / `libBlobFree`
- **错误**：C 层粘性错误码（`sli_last_error` / `sli_error_detail`），SL 侧 `ImageFfi.lastErrorText()`
- **上限**：16384×16384 / 256M 像素 / 单文件 512MB（`vm_sl_image.h`）
- **内存路径**（`*Mem`）：SL `Array<UInt8>` ↔ 原生指针用 `Memory.alloc` + 逐字节
  `writeI8/readUInt8` 搬运，上限 `ImageFfi.MAX_INLINE_BYTES`（4 MiB）；大图走文件路径
  API（`probeFile` / `decodeFile` / `saveMem` 落盘段）零搬运直通 C 层

## FFI 绑定链

1. jsonc `dllImports` 段 `"static": "sl_image_lib"` → cvm 加载 SL 模块即预载 DLL 注册进 FFI.StaticLibrary
2. SL 侧 `@DllStaticImport("sl_image_lib", "sli_xxx", "sig")`（22 个 `lib*` 薄封装）
3. 装配期 payload 重写绑定表 → 运行期 `CallFFIStatic` 直调；**绑定失败静默回退 SL 函数体兜底**
   （false/0/""，`ensureReady() == false` 即兜底征兆）
4. 签名格式：无括号 Cuda 风格 `"i32,i32,i32,i32,ptr->i64"`；零参写 `"->utf8"`
   （带括号会解析失败 → 静默兜底）

## 构建与测试

```powershell
# 编译模块（自动 MSBuild Release|x64 重建 DLL 并拷到导出目录）
dotnet run --no-launch-profile --project D:\project\lang\simple_language\source\SimpleLanguageFront.csproj -- `
  compile -p D:\project\lang\SlangAllInOne\SLangCore\Lib\SLang\Image\SLImage\Image.jsonc `
  -e ir --no-banner --format binary+json
# 产物 → D:\project\lang\SlangAllInOne\out\export\SLangImage\（slb + json + sl_image_lib.dll）

# 端到端测试（自动 stage 模块与 DLL 进 package\win32-debug\modules\SLangImage\）
dotnet run --no-launch-profile --project D:\project\lang\SlangAllInOne\Project\CSimpleVMTest\CSimpleVMTest.csproj -- `
  D:\project\lang\SlangAllInOne\SLangCore\test\Other\ImageTest\ProjectTest.jsonc
```

注意 `--no-launch-profile` 必须带：launchSettings 的 profile 会覆盖命令行参数。

## 已踩过的坑（维护必读）

1. **SL 类级 const 必须写 `static const`**：无 `static` 的 const 成员在 static 方法里经类名
   访问（`ImageFfi.MAX_INLINE_BYTES`）编译成 `LoadNotStaticField`（实例字段加载，static 方法
   无 this 栈对象），**编译不报错但运行期取值无效**（读到的可能是 0/垃圾值）。`static const`
   才走编译期常量内联。参考 `IRVariable.cs` CreateLoadVariable：`mv.isStatic` 才有 const 折叠分支。
2. **SL enum 不自动递增**：未显式赋值的枚举成员默认值 0（全部成员冲突为 0）。所有枚举必须
   逐成员显式赋值（`ImageFormat.sl` 已修）。
3. **C 层 fourcc 是定长 4 字节比较**：`fourcc(p,n,1,"PNG")` 的字面量第 4 字节是 NUL，与 PNG
   magic 第 5 字节 0x0D 不匹配 → 嗅探永不命中。PNG 用完整 8 字节 magic 逐字节比较；
   TIFF 的 `"II"` 同理改两字节显式比较。
4. FFU 签名不要带括号；`data` / `out` 是 SL 关键字；enum 成员行内注释会致解析中断；
   跨行长链表达式必失败（单行多操作符链 OK）。

## 许可

- stb：公有领域 OR MIT-0（`cvm_image_lib/third_party/stb/LICENSE.md`）
- WIC：Windows 系统组件（COM 接口直调，无再分发负担）
