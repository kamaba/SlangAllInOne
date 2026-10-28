# SLang 跨平台渲染引擎设计 · 06 图像编解码（PNG / JPEG / WebP / SVG）

- 所属文档集：`Render/doc/`（01 总览 · 02 Unity 参考 · 03 模块详设 · 04 原生绑定与跨平台 · 05 路线图与规范 · **06 图像编解码**）
- 版本：v0.4
- 本章定义图像**读取与写入**的完整设计：容器探测、像素解码/编码、SVG 解析与光栅化，以及与渲染管线（纹理上传）的集成。
- 调用策略遵循 01 D8：**T1 原生绑定优先（`slr_image_*` / `slr_svg_*` / `slr_blob_*`，完整符号表在本章 §5）→ T2 系统方法兜底（对象返回）→ T3 存量迁移（§5.4）**。

---

## 1. 定位与范围

### 1.1 在引擎中的位置

图像编解码是渲染引擎的**纹理数据源子系统**（对应 Unity 的 `ImageConversion` + `Texture2D.LoadImage` + `Image.LoadImage` 一族）：

```
文件/网络字节 ──► [探测 probe] ──► [解码 decode] ──► ImageBuffer(CPU) / 原生像素块
                                                            │
                                    懒上传（03 §4.11 Texture.gpu）
                                                            ▼
                                                     GpuTexture(GPU)
CPU 侧程序化生成/修改的 ImageBuffer ──► [编码 encode] ──► PNG/JPEG/WebP 文件（截图、烘焙输出）
SVG 文档（矢量）──► [parse 一次] ──► [rasterize 任意尺寸] ──► ImageBuffer（UI 图标）
```

### 1.2 目标

| 目标 | 说明 |
|---|---|
| 读 | PNG（含 16bit/调色板/Adam7）、JPEG（baseline/渐进）、WebP（有损/无损）、SVG（矢量）→ 像素 |
| 写 | ImageBuffer → PNG / JPEG / WebP（截图、CI 对比图、离屏烘焙输出） |
| 探测 | 不解码像素只取宽高/格式/透明（texStreaming、资产扫描） |
| 零拷贝快路 | 文件 → 原生像素块 → `slr_texture_upload`，像素不过 SL 数组 |
| 对象友好路 | T2 直接构造 `ImageBuffer` 返回（与现有 API 形态一致） |
| 统一色域 | v1 一律 sRGB，不做 ICC/CMYK（限制见 §8） |

### 1.3 非目标

- 通用绘图/矢量编辑库（Canvas2D 式 API 是宿主 UI 层职责，见 04 §7.3）
- GIF/AVIF/HEIC/TIFF/ICO/TGA/PPM 的**完整**实现（`EImageFormat` 枚举已含，v1 只保探测；按需在 M6+ 扩）
- 动图帧序列播放（`Image.webpFrames` 探测已有，播放属宿主动画系统）
- 字体光栅化（SVG `<text>` 见 §4.4 限制）

---

## 2. 现状盘点（`Image/` 目录，8 个 .sl）

| 文件 | 纯 SL 已实现 | 依赖后端（T3 存量） |
|---|---|---|
| ImageFormat.sl | EImageFormat / EPixelFormat / EColorSpace / EInterpolation 枚举 | — |
| ImageInfo.sl | 魔数嗅探 sniff（PNG/JPEG/WebP/GIF/BMP/ICO/TIFF 等文件头）+ probe 元信息 | `Image.probe` |
| ImageBuffer.sl | 紧密排布像素容器（10 种像素格式 bpp/通道表）、读写像素、裁剪/翻转、最近邻+双线性 resize、格式互转、预乘 alpha | `Image.decode` / `Image.encode` |
| ImageIO.sl | 门面：detectFormat/formatOfPath/probe/thumbnail/格式能力表/MIME/扩展名 | `Image.probeFile` / `decodeAs` / `encodeAs` / `load` / `save` |
| Png.sl | 容器模型：chunk 语法（关键/私有/安全复制）、IHDR 解析、位深×颜色类型合法性表、通道数 | `Image.pngDecode` / `Image.pngEncode` |
| Jpeg.sl | SOF 探测、编码选项（质量/采样/渐进） | `Image.jpegDecode` / `Image.jpegEncode` / `Image.jpegExif` |
| Webp.sl | VP8/VP8L/VP8X 文件头解析、编码选项 | `Image.webpDecode` / `Image.webpEncode` / `Image.webpFrames` |
| Svg.sl | viewBox 解析、path `d` 命令解析（隐式重复/负号分隔/科学计数法） | `Image.svgParse` / `Image.svgRasterize` |

**Bring-up 缺口（05 §2.2 同步登记）**：

1. `Image/*.sl` **未登记进 `Render.jsonc`** 的 `compileFiles.files` 与 `struct` 段（当前 jsonc 只编根目录 + Camera + Pipeline）——M2 首个任务：登记 8 个文件 + 新增 `{ "namespace": "Image", "children": [...] }`。
2. 全部 18 个 `SystemCallExternalFunction("Image.xxx")` 调用点为 T3，按 §5.4 迁移。

**结论**：数据模型与门面已经设计良好（namespace Image、容器/选项/探测分层清晰），本设计的增量是：**绑定面从字符串分发迁到 T1/T2 + 零拷贝上传路径 + SVG 光栅化落地 + 写出（截图）链路**。

---

## 3. 数据流与内存策略

### 3.1 三条路径

| 路径 | 数据流 | 用途 | 绑定 |
|---|---|---|---|
| **A 零拷贝快路（首选）** | `path` → 后端读文件+解码到**原生像素块** → `slr_texture_upload(ptr)` 直接进 GPU | 纹理加载（最热路径） | 全 T1 |
| **B 对象路** | `path`/`bytes` → T2 构造 `ImageBuffer` 返回 → SL 侧处理（缩略图/像素操作）→ 需要时再上传 | CPU 侧处理、缩略图 | T2 |
| **C 编码路** | SL 侧 `ImageBuffer` → 数据写入原生内存 → `slr_image_encode` → blob → `slr_blob_save` 写盘 | 截图、烘焙、CI 对比图 | T1 |

### 3.2 blob（原生字节块）

编码产物（压缩字节流）与解码入参（内存中的文件字节）需要一个跨 FFI 的字节容器。引入通用 **blob**（与 04 §4.4 反射表写出同模式）：

```sl
# blob 生命周期：句柄 i64；ptr/size 只读；用完必须 free
Int64 blob = RenderFFI.ffi_imageEncode( ... )      # 0 = 失败
Int64 size = RenderFFI.ffi_blobSize( blob )
Int64 dataPtr = RenderFFI.ffi_blobPtr( blob )
bool ok = RenderFFI.ffi_blobSave( blob, "shot.png" )   # 后端 fopen+fwrite
RenderFFI.ffi_blobFree( blob )
```

### 3.3 `Array<UInt8>` ↔ 原生内存批量互转（前置任务）

路径 B 的 `bytes` 入参（网络下载等 SL 侧字节数组）进 T1 前需写入原生内存；blob 读回 SL 数组同理。逐元素 `Memory.writeU8` 对 MB 级数据不可接受——**M2 前置任务：VM 侧补充 `SystemPtrWriteByteArray / SystemPtrReadByteArray` 批量系统方法**（T2，一次拷贝整段）。落地前：路径 B 走 T2 对象接口（后端自读文件），`bytes` 变体标记受限（仅小图）。

---

## 4. 格式详设

### 4.1 PNG（无损，纹理/截图主力）

- **SL 侧（已有，保持）**：签名/chunk/IHDR 模型、位深合法性表、选项（压缩级 0-9、滤波策略、stripAlpha）。
- **native 侧**：zlib inflate/deflate + 5 种行滤波器反演 + Adam7 解交织 + 调色板展开；16bit→8bit 截断（可选保 16bit 输出 `Rgba16`）。
- **解码输出**：`forceRgba`（默认，展开 Gray/Palette/16bit 到 Rgba8 sRGB）或按源格式给（Gray8/Rgb8/Rgba8/Rgba16）。
- **编码输入**：Rgba8/Rgb8/Gray8（其余格式先经 `ImageBuffer.convert` 归一）。

### 4.2 JPEG（有损，照片输入）

- **SL 侧（已有，保持）**：SOF 探测、`JpegEncodeOptions`（quality 1-100、色度采样 420/444、渐进、优化 Huffman）。
- **native 侧**：baseline + 渐进解码；编码按选项。
- **EXIF**：`Image.jpegExif`（方向标记）已有调用点——v1 支持**方向自动旋转**（选项 `autoOrient`，默认开，渲染引擎不希望纹理躺倒）；其余 EXIF 字段忽略。
- **无 alpha**：解码恒为 Rgb8/Rgba8（alpha 填 255）。

### 4.3 WebP（有损/无损，可选体积优势）

- 与 PNG 同一套容器/门面模式：VP8/VP8L 头解析（SL）+ 解码编码（native）。
- `Image.webpFrames`：v1 仅返回帧数（动画探测），不做帧序列解码。

### 4.4 SVG（矢量 → 按需光栅化）

SVG 与位图本质不同：**parse 一次，任意尺寸多次光栅化**（UI 图标按 DPI/控件尺寸出位图）。

```
"icon.svg" ─► slr_svg_parse(xmlUtf8) ─► docHandle(i64)
                                            │ 按 (doc, w, h) 缓存（SvgCache）
                    slr_svg_rasterize(doc, w, h, opts, outPack) ─► 原生像素块(A 路径) / ImageBuffer(B 路径)
```

- **SL 侧（已有，保持）**：viewBox / path `d` 解析（probe 尺寸、SL 侧几何预检）；新增 `SvgDocument` 句柄持有类 + `SvgCache`（键 `path|w|h`，LRU 上限，图标场景典型 <100 项）。
- **native 侧**：XML 解析 → 文档树 → 光栅化（路径填充/偶奇规则、描边、线性/径向渐变、简单裁剪）。
- **v1 限制（选型决定，见 §7）**：`<filter>`（模糊/阴影）、`<text>`（字体）、`<use>` 复杂引用、CSS `style` 块不支持——遇到时降级为「按 viewBox 画个占位色块」并 `Console.log` 告警一次，**不失败**。
- **写出**：SVG 的「写」= 文档树序列化回 XML 文本（SL 侧字符串拼接，`SvgDocument.serialize()`），不涉及光栅化；位图转 SVG 不做（非目标）。

---

## 5. FFI 绑定契约（本域完整符号表）

> 本章是图像编解码域符号表的**唯一权威**（04 §4.8 指向这里）。约定同 04 §3：`extern "C"`、句柄 i64、0 恒无效、枚举 i32 与 SL enum 一致（`slr_types.h` 单点）、描述符/出参块 ptr、sig 用 FFI 短名。全部声明集中在 `Pipeline/RenderFFI.sl`。

### 5.1 探测 `slr_image_probe_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_image_probe_file | ( path:utf8, infoOut:ptr ) -> bool | `"utf8,ptr->bool"` | 读文件头写 ImageInfo 出参块（format/w/h/hasAlpha/isAnimated） |
| slr_image_probe_mem | ( data:ptr, size:i64, infoOut:ptr ) -> bool | `"ptr,i64,ptr->bool"` | 内存字节探测（依赖 §3.3 批量互转） |

### 5.2 解码 `slr_image_decode_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_image_decode_file | ( path:utf8, optsPack:ptr, outPack:ptr ) -> bool | `"utf8,ptr,ptr->bool"` | **A 路径主力**。outPack：{pixelPtr, w, h, pixelFormat, colorSpace}——原生像素块（后端分配） |
| slr_image_decode_mem | ( data:ptr, size:i64, optsPack:ptr, outPack:ptr ) -> bool | `"ptr,i64,ptr,ptr->bool"` | |
| slr_image_free_pixels | ( pixelPtr:ptr ) | `"ptr"` | A 路径用完释放（`slr_texture_upload` 后） |

optsPack（解码选项，共域）：`{magic, version, forceRgba, autoOrient(jpeg), premultiplyAlpha}`。

### 5.3 编码 + blob `slr_image_encode` / `slr_blob_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_image_encode | ( pixels:ptr, w:i32, h:i32, srcFmt:i32, fileFmt:i32, optsPack:ptr ) -> i64 | `"ptr,i32,i32,i32,i32,ptr->i64"` | C 路径；返回 blob 句柄（0=失败）。optsPack：quality/压缩级/滤波策略按格式复用既有选项类字段 |
| slr_blob_ptr | ( blob:i64 ) -> ptr | `"i64->ptr"` | 只读数据指针 |
| slr_blob_size | ( blob:i64 ) -> i64 | `"i64->i64"` | 字节数 |
| slr_blob_save | ( blob:i64, path:utf8 ) -> bool | `"i64,utf8->bool"` | 编码产物落盘（后端 fopen+fwrite） |
| slr_blob_free | ( blob:i64 ) | `"i64"` | |

### 5.4 SVG `slr_svg_*`

| C 符号 | SL 签名 | sig | 说明 |
|---|---|---|---|
| slr_svg_parse | ( xmlUtf8:utf8 ) -> i64 | `"utf8->i64"` | 解析为文档句柄（0=失败/含致命错误） |
| slr_svg_rasterize | ( doc:i64, w:i32, h:i32, optsPack:ptr, outPack:ptr ) -> bool | `"i64,i32,i32,ptr,ptr->bool"` | optsPack：{bgColor(rgba)、premultiply、maxTextureSize 钳制}；outPack 同解码 |
| slr_svg_free | ( doc:i64 ) | `"i64"` | |

### 5.5 T2 兜底（对象友好接口）

jsonc `systemCalls[]` 声明、`cvmFunction` 指向 cvm_render_lib（内部读文件/构造对象后转调 T1）：

| 系统方法 | 签名（SL 视角） | 用途 |
|---|---|---|
| RenderImageDecodeFile | ( path:string ) -> ImageBuffer | B 路径：直接构造 SL 对象（`ImageIO.load` 的迁移目标） |
| RenderImageDecodeMem | ( bytes:Array<UInt8> ) -> ImageBuffer | `Image.decode/decodeAs` 的迁移目标 |
| RenderImageEncodeBuffer | ( buffer:ImageBuffer, format:EImageFormat, quality:Int32 ) -> Array<UInt8> | `Image.encode/encodeAs/pngEncode/...` 的迁移目标 |
| RenderImageProbeFile | ( path:string ) -> ImageInfo | `Image.probeFile` 的迁移目标 |

> T2 属 04 §1.2 类别 1（构造 SL 对象返回），**长期保留**（不是过渡品）——A/B 双路径并存是设计意图：热路径零拷贝走 T1，易用性走 T2。

### 5.6 存量 T3 迁移映射（18 个调用点）

| 旧 T3 名（前缀 Image.） | 去向 |
|---|---|
| load | T2 `RenderImageDecodeFile`（ImageIO 内部）/ 热路径改走 T1 A 路径 |
| decode / decodeAs | T2 `RenderImageDecodeMem` |
| encode / encodeAs | T2 `RenderImageEncodeBuffer` |
| probe / probeFile | T1 `slr_image_probe_mem/_file` / T2 `RenderImageProbeFile` |
| save | T1 C 路径：`slr_image_encode` + `slr_blob_save` |
| pngDecode / jpegDecode / webpDecode | 同 decode（格式由探测决定；选项进 optsPack） |
| pngEncode / jpegEncode / webpEncode | 同 encode（选项进 optsPack） |
| jpegExif | 并入 decode 选项 `autoOrient`（独立查询接口取消） |
| webpFrames | 并入 `slr_image_probe_*` 出参块 `isAnimated/frameCount` |
| svgParse / svgRasterize | T1 `slr_svg_parse / slr_svg_rasterize` |

迁移批次随 05 M2：`Render.jsonc` 登记 + T1/T2 铺设 → 各格式 .sl 切换 → `SystemCallExternalFunction` 出现次数清零。

---

## 6. 与渲染管线的集成

### 6.1 纹理上传（Texture.gpu 打通，03 §4.11 补充）

```sl
# Texture.sl 增强（03 §4.11 的 Texture.gpu 懒上传实现细节）：
public void uploadToGpu()
{
    # A 路径：像素全程不过 SL 数组
    Int64 outPack = Memory.alloc( 32 )
    if RenderFFI.ffi_imageDecodeFile( this.path, optsPack, outPack )
    {
        Int64 pixelPtr = Memory.readI64( outPack, 0 )
        Int32 w  = Memory.readI32( outPack, 8 )
        Int32 h  = Memory.readI32( outPack, 12 )
        Int32 fmt = Memory.readI32( outPack, 16 )
        GpuTexture t = GpuTexture( this.path, w, h, ImageCodec.toTextureFormat( fmt ),
                                   ETextureUsage.ShaderResource )
        t.create()
        RenderFFI.ffi_textureUpload( t.handle, pixelPtr, w, h, fmt )   # 04 §4.3
        RenderFFI.ffi_imageFreePixels( pixelPtr )
        t.generateMipmaps()
        this.gpu = t
    }
    Memory.freeNative( outPack )
}
```

`ImageCodec.toTextureFormat`：EPixelFormat → ETextureFormat 映射（Rgba8→RGBA8_SRGB、Rgba16→RGBA16F、Gray8→R8…；sRGB 决策：纹理默认 sRGB，`RenderTextureDescriptor` 显式线性时用非 SRGB 变体）。

### 6.2 截图 / CI 对比（C 路径收口）

- `GfxDevice.readBackPixel(framebuffer)`（新增 T1：回读到原生像素块，Readback 堆语义）→ `slr_image_encode(Png)` → `slr_blob_save("shot_N.png")`。
- 05 §1 M6 验收的「截图哈希对比」即基于此链路（PNG 无损保证哈希稳定）。

### 6.3 SVG 图标缓存（UI 路径，v1.1）

`SvgCache.get(path, w, h)` → 命中返回 GpuTexture；未命中 parse（按 path 缓存 docHandle）→ rasterize → upload → 入缓存。窗口 resize/DPI 变化只需按新尺寸 rasterize，**无需重新 parse**。

### 6.4 图像解码与 GPU 压缩格式的边界

BC/ETC2/ASTC 的**编码**（离线压缩）不在本章（属资产管线，M7 演进）；本章解码端只处理未压缩像素源。`GpuTexture.uploadCompressed`（03 §4.3）接收的压缩块来自资产管线产物，不来自 PNG/JPEG 解码。

---

## 7. 后端解码库选型（C 层，M0 冻结）

| 格式 | v1 选型 | 备选（质量/性能升级路径） |
|---|---|---|
| 读（PNG/JPEG/WebP/BMP 统一） | **stb_image**（单头文件、零依赖、覆盖全部目标格式读） | libpng / libjpeg-turbo（编码质量与速度要求高时替换） |
| PNG 写 | **libpng**（压缩比/滤波器控制优于 stb）或 miniz | stb_image_write（若依赖最小化优先） |
| JPEG 写 | **libjpeg-turbo**（SIMD，截图编码延迟敏感） | stb_image_write |
| WebP 读写 | **libwebp** | — |
| SVG | **nanosvg**（MIT，路径/渐变/裁剪，≈5k 行） | thorvg（完整度更高，M6+ 评估）；v1 限制见 §4.4 |

选型原则：**读路径求覆盖面（stb 一次性解决三种位图读）**；**写路径求质量与速度（截图/烘焙产物可信）**；SVG 求小（nanosvg），限制显式告警降级。

---

## 8. 限制与已知边界

| 项 | 说明 |
|---|---|
| 色彩管理 | v1 一律 sRGB；PNG 的 iCCP/gAMA、JPEG 的 ICC profile 忽略（读入按 sRGB 解释） |
| 大图上限 | 解码前用 probe 校验 `w*h` ≤ `GfxCapabilities.maxTextureSize`² 与进程内存预算，超限返回失败而非 OOM |
| 渐进加载 | 不做（Unity 的 progressive JPEG 流式解码非 v1 目标） |
| 多线程 | v1 解码在调用线程同步执行；异步解码（Loading 线程 + 回调）列 M7 |
| SVG `<text>` | 依赖字体系统（非目标），遇到按 §4.4 降级 |
| `Array<UInt8>` 批量互转 | 依赖 §3.3 前置任务；落地前 mem 变体仅建议小图 |

---

## 9. 验收标准（挂 05 §1 M2，扩展）

1. **Roundtrip**：程序化生成 ImageBuffer（棋盘 + 渐变 + 半透明）→ encode PNG → decode → 像素逐字节相等；JPEG quality=100 → PSNR ≥ 40dB。
2. **A 路径零拷贝**：RenderDoc 抓帧确认纹理上传来源为原生指针（无 SL 数组中转的临时分配峰值）。
3. **SVG**：一份含 path/线性渐变/描边的图标，在 32/64/128/256 四档尺寸光栅化，边缘无锯齿错位（抗锯齿开启），同 docHandle 只 parse 一次。
4. **迁移完成**：`Image/` 目录 `SystemCallExternalFunction` 出现次数 = 0；`Render.jsonc` 登记 8 文件 + Image namespace struct。
5. **降级**：后端无 slang_render.dll 时，`ImageIO.load` 返回 null 且 Console 告警一次（绑定探测，05 §3.2-18），不崩溃。
