# SLangImage 模块 —— CPU 图像解码/编码

- 模块名：`SLangImage`（namespace `Image`），jsonc 锚点：`SLImage/Image.jsonc`
- 后端：`sl_image_lib.dll`（stb_image v2.31 + stb_image_write v1.17，公有领域 OR MIT-0 双许可；WIC 系统组件兜底 TIFF/ICO/WebP 解码、TIFF 编码）
- 状态：v0.5，ImageTest 189 项全绿（`SLangCore\test\Other\ImageTest\`）

## 目录结构

```
Image/
├── SLImage/                    # SL 层模块工程（jsonc 锚点在此）
│   ├── Image.jsonc             # 模块清单：compileFiles 16 个 .sl + dllImports + vmDlls + struct
│   ├── Image.sp
│   ├── ImageFormat.sl          # EImageFormat / EPixelFormat / EColorSpace / EInterpolation / EOrientation / ImageErrorCode
│   ├── (Color.sl 已删除)       # 8bit RGBA 颜色合并为 Std 根级 ColorInt（Std/ColorInt.sl），模块经 references 引用 Std
│   ├── ImageBuffer.sl          # 紧密像素容器（纯 SL：读写像素/fill/flipY/crop/convertTo/resize/rotate/paste/pasteMasked/通道拆合/合成混合）
│   ├── ImageInfo.sl            # 头部探测元信息（纯 SL magic 嗅探 + 门面）
│   ├── ImageFfi.sl             # C 层 FFI 静态绑定 + 内存搬运（本模块核心；opFastPathsEnabled 开关见坑 9）
│   ├── ImageIO.sl              # 门面：load/save/probe/encode/decode/convert
│   ├── Png.sl / Jpeg.sl / Webp.sl / Svg.sl   # 容器模型与选项（编解码本体已下沉 FFI）
│   ├── Gif.sl                 # GIF 动画拆解/合成（GifFrame/GifDocument/GifEncoder/Gif 门面）
│   ├── ImageSequence.sl       # 多帧序列遍历（仿 Pillow ImageSequence：ImageSequenceIterator + 门面）
│   ├── ImageFilter.sl         # 3x3 卷积滤镜（仿 Pillow ImageFilter：8 命名滤镜 + convolve3x3 通用核）
│   ├── ImageChops.sl          # 通道运算（仿 Pillow ImageChops 8 法 + softLight/hardLight/overlay）
│   ├── ImageEnhance.sl        # 图像增强（仿 Pillow ImageEnhance：亮度/对比度/饱和度/锐度）
│   ├── ImageMask.sl           # 蒙版技术（渐变/圆形/图案/棋盘蒙版 + applyMaskBlend/transitionBlend）
│   ├── ImageDraw.sl           # 矢量绘制（point/line/rectangle/ellipse/circle/arc/polygon + 3x5 位图 text）
│   └── export/DebugCode/       # Front 调试快照（Code/Token/Node/Meta/IR）
├── cvm_image_lib/              # C 层 VS 工程
│   ├── vm_sl_image.h           # 公开契约（55 个 sli_* 导出：22 静图 + 13 GIF 动画 + 20 op_* 像素批量运算，普通 C ABI）
│   ├── sl_image.c              # 槽表/粘性错误/格式嗅探/probe/解码编码主路 + sli_gif_* 分派
│   ├── sl_image_internal.h
│   ├── Codec/sl_image_stb.c    # stb 唯一 IMPLEMENTATION 编译点（含 stbi_load_gif_from_memory）
│   ├── Codec/sl_image_gif.c    # 自研 GIF89a 编码器（调色板量化 + LZW + NETSCAPE2.0 循环扩展）
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

## GIF 动画（拆解 / 合成）

- **拆解**（GIF → 普通图）：`Image.Gif.decode( bytes )` → `GifDocument`（width/height/
  loopCount/frames），`frames[i]` → `GifFrame`（`image: ImageBuffer` + `delayMs: Int32`）；
  只要帧不要元数据用 `decodeFrames( bytes )` → `List<ImageBuffer>` 一步到位；文件路径版
  `decodeFile( path )`（`Image.Gif.decodeFile`）
- **合成**（普通图 → GIF）：
  - 命令式流式：`Image.GifEncoder( w, h, loopCount )` → `addFrame( buffer )` /
    `addFrameWithDelay( buffer, delayMs )` ×N（帧尺寸必须匹配 ctor 的 w/h）→
    `build()` → `Array<UInt8>`（一次性，build 后编码器失效），`save( path )` 落盘
  - 声明式文档：`GifDocument( w, h )` + `addFrame / addFrameWithDelay` →
    `Image.Gif.encode( doc )` / `Image.Gif.save( doc, path )`
  - 单帧捷径：`ImageIO.encode( buffer, EImageFormat.Gif )`（无循环扩展，loopCount == -1）
- **编码器**：自研 GIF89a（调色板量化 + LZW 满表 CLEAR + NETSCAPE2.0 循环 + 逐帧 GCE 延迟）；
  调色板直命中时 roundtrip 字节精确，量化帧误差受控（测试口径 < 24/通道）

## ImageSequence（仿 Pillow ImageSequence 模块）

对标 <https://www.runoob.com/pillow/imagesequence-module.html>，纯 SL 组合 Gif/ImageIO，
不新增 FFI 绑定。数据源是 `GifDocument`（`Gif.decode` / `Gif.decodeFile` 拆解产物）。

| Pillow (runoob) | SLang 对应 | 说明 |
| --- | --- | --- |
| `ImageSequence.Iterator(im)` | `Image.ImageSequence.iterator( doc )` → `ImageSequenceIterator` | 帧迭代器；`iteratorOf( bytes )` / `iteratorOfFile( path )` 为解码+包装捷径 |
| `for frame in Iterator(im)` | `for f in ImageSequenceIterator( doc )` | 实现 `Core.IIterable/IIterator<GifFrame>`（自迭代），`f : GifFrame` |
| `seek(frame)` | `ImageSequenceIterator.seek( frame )` | 越界返回 false 且游标不动（Pillow 抛 EOFError 的安全版）；成功后 `current` 立即可用 |
| `tell()` | `ImageSequenceIterator.tell()` | 当前帧序号；-1 = 尚未开始 / reset 态 |
| `n_frames` | `ImageSequenceIterator.nFrames` | 帧总数（无效文档 0） |
| `ImageSequence.all_frames(im)` | `Image.ImageSequence.allFrames( doc )` → `List<GifFrame>` | 空文档得空列表；`allFramesOf( bytes )` 一步到位 |
| （静态图当单帧序列） | `ImageSequence.framesOfImage( buffer )` | Pillow `all_frames` 对非动画图返回单元素列表的语义（帧图 clone 隔离） |

补充门面：`allImages( doc )`（只要 `List<ImageBuffer>`）、`frameCount( doc )` /
`frameCountOfImage( buffer )`（n_frames 门面）、`saveFrame( frame, path[, format, quality] )`
与 `saveAllFrames( doc, prefix )`（教程示例 1 的 `frame.save(f'frame_{i}.png')` 落盘）。
游标语义：`_index = -1` 为首帧之前；`moveNext` 先加后取；`seek(k)` 定位后
`tell() == k`（与 Pillow seek 后 tell 一致）。

## ImageBuffer / ImageFilter（仿 Pillow Image 模块方法集）

对标 <https://www.runoob.com/pillow/pillow-image-module.html>，纯 SL 实现，不新增 FFI 绑定。

| Pillow (runoob) | SLang 对应 | 说明 |
| --- | --- | --- |
| `Image.open(fp)` | `Image.ImageIO.load( path )` | 原有；`decode( bytes )` 为内存版 |
| `Image.new(mode, size, color)` | `Image.ImageBuffer.newImage( w, h[, color] )` | Rgba8 纯色图；color=null 得透明图 |
| `Image.save(fp)` | `Image.ImageIO.save( img, path, format, quality )` | 原有；按扩展名推断另有 2 参重载 |
| `Image.show()` | `Image.ImageIO.show( img[, openViewer] )` | 存临时 PNG + `OS.Process.shell("start ...")` 弹查看器；`openViewer=false` 只落盘 |
| `Image.resize(size, resample)` | `buffer.resize( w, h, EInterpolation )` | 原有；Nearest / Bilinear |
| `Image.rotate(angle, expand)` | `buffer.rotate( angleDeg[, expand, mode] )` | 正角逆时针；圈外透明；expand 出旋转包围盒；逆映射 + 双线性采样 |
| `Image.crop(box)` | `buffer.crop( x0, y0, w, h )` | 原有 |
| `Image.paste(im, box)` | `buffer.paste( src, x, y )` | 越界自动裁剪；整块覆盖不混合 |
| `Image.convert(mode)` | `buffer.convertTo( EPixelFormat )` | 原有；`convertTo(Gray8)` 即 `convert('L')` |
| `Image.copy()` | `buffer.clone()` | 原有 |
| `Image.thumbnail(size)` | `Image.ImageIO.thumbnail( img, maxW, maxH )` | 原有；等比只缩不放 |
| `Image.getpixel(xy)` / `putpixel` | `buffer.getPixel(x,y)` / `setPixel(x,y,c)` | 原有 |
| `Image.split()` | `buffer.splitChannels()` → `List<ImageBuffer>` | 每通道一张 Gray8 图（RGBA 出 4 张） |
| `Image.merge('RGBA', bands)` | `Image.ImageBuffer.mergeRgba(r,g,b,a)` / `mergeRgb(r,g,b)` | 同尺寸 Gray8 平面 → 合成 Rgba8 |
| `Image.alpha_composite(dst, src)` | `Image.ImageBuffer.alphaComposite( dst, src )` | 逐像素 `ColorInt.blendOver`（src over dst） |
| `Image.blend(im1, im2, alpha)` | `Image.ImageBuffer.blend( im1, im2, alpha )` | `im1*(1-a) + im2*a` 直算（Pillow 同式） |
| `img.filter(ImageFilter.X)` | `Image.ImageFilter.apply( img, EImageFilter.X )` | 见下 |
| 属性 `size/width/height/mode` | `buffer.width/height/pixelFormat` | 原有；`format` 在 `ImageInfo` |

ImageFilter（`ImageFilter.sl`，核取自 PIL ImageFilter.py 近似值）：`Blur / Contour /
Detail / Emboss / EdgeEnhance / FindEdges / Sharpen / Smooth` 八个命名滤镜 +
`convolve3x3( src, kernel9, scale, offset )` 通用核（≈ `ImageFilter.Kernel`）。
约定：输出恒 Rgba8；RGB 三通道卷积，alpha 保留中心像素；边界像素复制；
除法截断 + clamp8。

## ImageChops / ImageEnhance / ImageMask / ImageDraw（仿 Pillow advanced）

对标 <https://www.runoob.com/pillow/pillow-advanced.html>，四个新类（jsonc
struct 已登记），重循环同样下沉 C 层（SL 循环兜底逐位对齐）。

**ImageEnhance**（`ImageEnhance.sl`）—— PIL 外插同式
`result = degenerate*(1-f) + image*f`（f=1 原图 / f=0 退化图 / f>1 增强）：

| Pillow (runoob) | SLang 对应 | degenerate |
| --- | --- | --- |
| `ImageEnhance.Brightness(im).enhance(f)` | `Image.ImageEnhance.brightness( img, f )` | 纯黑 |
| `ImageEnhance.Contrast(im).enhance(f)` | `Image.ImageEnhance.contrast( img, f )` | 灰度均值纯灰图（`sli_op_luma_mean`） |
| `ImageEnhance.Color(im).enhance(f)` | `Image.ImageEnhance.color( img, f )` | 灰度化原图（`sli_op_grayscale`） |
| `ImageEnhance.Sharpness(im).enhance(f)` | `Image.ImageEnhance.sharpness( img, f )` | Blur 近似 PIL 高斯 |

**ImageChops**（`ImageChops.sl`）—— 两图同尺寸、运算作用于全部 4 通道、
输出恒 Rgba8；整数公式（除法截断 + clamp8）与 C 层 `sli_op_chops`（op 0..10）
逐位对齐：

| Pillow (runoob) | SLang 对应 | 公式 |
| --- | --- | --- |
| `ImageChops.add(im1, im2)` | `Image.ImageChops.add( im1, im2 )` | `clamp8(a+b)` |
| `ImageChops.subtract` | `Image.ImageChops.subtract( im1, im2 )` | `max(a-b, 0)` |
| `ImageChops.multiply` | `Image.ImageChops.multiply( im1, im2 )` | `a*b/255` |
| `ImageChops.screen` | `Image.ImageChops.screen( im1, im2 )` | `255-(255-a)(255-b)/255` |
| `ImageChops.difference` | `Image.ImageChops.difference( im1, im2 )` | `abs(a-b)` |
| `ImageChops.invert(im)` | `Image.ImageChops.invert( im )` | `255-a` |
| `ImageChops.lighter` | `Image.ImageChops.lighter( im1, im2 )` | `max(a,b)` |
| `ImageChops.darker` | `Image.ImageChops.darker( im1, im2 )` | `min(a,b)` |
| 教程 custom_blend `soft_light` | `Image.ImageChops.softLight( im1, im2 )` | `(a(255-b) + b²/255)/255` |
| `hard_light` | `Image.ImageChops.hardLight( im1, im2 )` | b<128 正片叠底，否则滤色 |
| `overlay` | `Image.ImageChops.overlay( im1, im2 )` | a<128 正片叠底，否则滤色 |

**ImageMask**（`ImageMask.sl`）—— 蒙版生成（Gray8 直写字节）+ 蒙版合成：
`m=0` 全取 A、`m=255` 全取 B、中间按 `(A(255-m)+B·m)/255` 整数直算

| Pillow advanced 技术 | SLang 对应 |
| --- | --- |
| 渐变蒙版 | `Image.ImageMask.gradientMask( w, h, EMaskDirection.Horizontal/Vertical/Radial/Diagonal, startV, endV )` |
| 圆形蒙版 | `Image.ImageMask.circularMask( w, h, cx, cy, radius )` |
| 图案蒙版 | `Image.ImageMask.patternMask( w, h, EMaskPattern.Grid/Dots/Stripes/Waves, cell )` |
| 棋盘蒙版 | `Image.ImageMask.checkerboardMask( w, h, cell )` |
| 蒙版混合两图 | `Image.ImageMask.applyMaskBlend( a, b, mask )`（`sli_op_mask_blend`；mask 须与 a/b 同尺寸） |
| 过渡混合 | `Image.ImageMask.transitionBlend( a, b, dir )`（梯度蒙版捷径） |
| 棋盘拼贴 | `Image.ImageMask.checkerboardBlend( a, b, cell )` |
| 蒙版贴入 | `buffer.pasteMasked( src, x, y, mask )`（`sli_op_paste_masked`；mask 须与 src 同尺寸） |

**ImageDraw**（`ImageDraw.sl`）—— 画布式矢量绘制（Pillow `ImageDraw` 的静态
无状态版；line/arc 走 Bresenham，polygon 描边 + 扫描线填充）：

| Pillow (runoob) | SLang 对应 |
| --- | --- |
| `draw.point(xy, fill)` | `Image.ImageDraw.point( img, x, y, c )` |
| `draw.line(xy, fill, width)` | `Image.ImageDraw.line( img, x0, y0, x1, y1, c, width )` |
| `draw.rectangle(xy, fill, outline)` | `Image.ImageDraw.rectangle( img, x0, y0, x1, y1, fill, outline [, outlineWidth] )` |
| `draw.ellipse(xy, fill, outline)` | `Image.ImageDraw.ellipse( img, x0, y0, x1, y1, fill, outline [, outlineWidth] )` |
| `draw.ellipse(...)` 画圆 | `Image.ImageDraw.circle( img, cx, cy, radius, fill, outline, outlineWidth )` |
| `draw.arc(xy, start, end, fill)` | `Image.ImageDraw.arc( img, x0, y0, x1, y1, startDeg, endDeg, c, width )` |
| `draw.polygon(xy, fill, outline)` | `Image.ImageDraw.polygon( img, xs, ys, fill, outline )` / `fillPolygon( img, xs, ys, fill )` |
| `draw.text(xy, text, font, fill)` | `Image.ImageDraw.text( img, x, y, s, c )`（3x5 位图 48 字形，同 SimGameEngine DrawCanvas；`textWidth( s ) = n*4-1`、`textHeight() = 5`） |


## C 层像素批量运算（sli_op_*，重循环下沉）

2026-11-28 两批下沉：纯 SL 每像素重循环全部进 `sl_image_lib.dll`（20 个
`sli_op_*` 导出，[vm_sl_image.h]「像素批量运算」段）。与句柄家族不同，这组是
**裸指针运算**（src/dst/out 指向 SL 侧 `Memory.alloc` 块，不占句柄槽）。

| C 导出 | SL 接入点（C 快路径） | SL 循环兜底触发条件 |
| --- | --- | --- |
| `sli_op_convolve3x3` | `ImageFilter.convolve3x3` / 8 命名滤镜 | 绑定失败 / >4MiB / 分配失败 |
| `sli_op_rotate` | `ImageBuffer.rotate`（任意角 + expand） | 同上 + **坑 9 开关关停** |
| `sli_op_resize` | `ImageBuffer.resize`（Nearest/Bilinear） | 同上 + 非 Rgba8 / Bicubic/Lanczos |
| `sli_op_alpha_composite` | `ImageBuffer.alphaComposite` | 同上 |
| `sli_op_blend` | `ImageBuffer.blend` | 同上 + **坑 9 开关关停** |
| `sli_op_split_rgba` | `ImageBuffer.splitChannels` | 同上 + 无 alpha 格式（SL 语义只出 3 平面） |
| `sli_op_merge_rgb` / `sli_op_merge_rgba` | `mergeRgb` / `mergeRgba` | 同上 + 平面非 Gray8 |
| `sli_op_convert` | `ImageBuffer.convertTo` | 同上 + 浮点格式 9/10 |
| `sli_op_paste` | `ImageBuffer.paste` | 同上 + 任一侧非 Rgba8 |
| `sli_op_fill` | `ImageBuffer.fill` / `newImage` | 同上 + 非 Rgba8 |
| `sli_op_flip_y` / `sli_op_flip_x` | `flipY` / `flipX` | 同上 + 非 4 字节像素 |
| `sli_op_premultiply` | `premultiplyAlpha` / `unpremultiplyAlpha` | 同上 + 非 4 字节像素 |
| `sli_op_grayscale` | `ImageEnhance.grayscale` | 同上 |
| `sli_op_luma_mean` | `ImageEnhance.contrast`（灰度均值） | 同上（返回 -1 时兜底） |
| `sli_op_chops` | `ImageChops` 11 法（op 0..10 单分派） | 同上 |
| `sli_op_mask_blend` | `ImageMask.applyMaskBlend` / `transitionBlend` | 同上 + **坑 9 开关关停** + mask 非 Gray8 |
| `sli_op_paste_masked` | `ImageBuffer.pasteMasked` | 同上 + **坑 9 开关关停** + mask 非 Gray8/尺寸不符 |
| `sli_op_blend_factor` | `ImageEnhance` 四增强器（外插混合） | 同上 + **坑 9 开关关停** |

**坑 9 开关**：`ImageFfi.opFastPathsEnabled`（默认 **false**）——VM
`CallFFIStatic` 快路径对部分新签名实参封送有 bug（详见坑 9），rotate/blend/
blend_factor/mask_blend/paste_masked 五个调用点由它门控暂走 SL 兜底；其余
C 路径（convolve/resize/convert/fill/paste/split/merge/flip/premultiply/
grayscale/luma_mean/chops）经 189 测试实测正常不受开关影响。VM 修复后置
true 即全量启用。

架构模式（每个接入点同构）：

1. **快路径**：`_uploadRgba` / `_copyIn`（逐字节上载，≤ `MAX_INLINE_BYTES`）
   → `Memory.alloc` 出参块 + int32 控制块（`_writeCtl`）→ `libOp*` 直调 →
   `_fillBytes` 回填 → `Memory.free`
2. **兜底**：C 调用返回 false / 上载失败 → 原纯 SL 循环原样保留执行
   （语义逐位对齐：整数除法截断、`toInt = clamp8(round)`、BT.601 灰度、
   blendOver 浮点合成 —— T43/T51/T68/T126/T143/T148-T152 字节级验证）

已知边界：4 MiB 搬运墙仍适用（`_copyIn` 逐字节上载成本随尺寸线性）；
超大图与浮点格式恒走 SL 循环（与 v1 行为一致）。

## FFI 绑定链

1. jsonc `dllImports` 段 `"static": "sl_image_lib"` → cvm 加载 SL 模块即预载 DLL 注册进 FFI.StaticLibrary
2. SL 侧 `@DllStaticImport("sl_image_lib", "sli_xxx", "sig")`（55 个 `lib*` 薄封装，含
   `libGif*` 13 个、`libOp*` 20 个）
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
# 再手动落双名（坑 5）：Copy-Item slb/json → *.module.slb/*.module.json

# 端到端测试（stage 模块 slb/json 进 package\win32-debug\SLangImage\；
# DLL 不在 *.module.* 通配内，须手动 Copy-Item sl_image_lib.dll，见坑 5 末尾）
dotnet run --no-launch-profile --project D:\project\lang\SlangAllInOne\Project\CSimpleVMTest\CSimpleVMTest.csproj -- `
  D:\project\lang\SlangAllInOne\SLangCore\test\Other\ImageTest\ProjectTest -test
# 改了 ImageTest.sl 后须「跑一遍 → Copy-Item 刷新测试双名 → 再跑」，否则跑旧测试
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
4. FFU 签名不要带括号；`data` / `out` / `next` / `as` 是 SL 关键字（`next` 用于 switch 的
   next-case、`as` 用于类型转换，作变量名会报"不允许在Else后增加任何代码" /
   "变量定义的名称不允许使用关键字"诡异解析错）；局部变量名 `fc` 会撞编译器类函数
   临时名（"定义变量名称与类函数临时名称一样"）；enum 成员行内注释会致解析中断；
   跨行长链表达式必失败（单行多操作符链 OK）。
5. **改模块后跑 ImageTest 双名落位 ×2**（产物命名简化遗留）：Front 只导出 `<名>.slb/.json`
   新命名，而测试链路（CSimpleVMTest stage 通配 `*.module.*` + C VM 引用相对解析）认旧名
   `<名>.module.slb`。**两处都要刷**：① 模块侧 `out\export\SLangImage\`（`Copy-Item
   SLangImage.slb SLangImage.module.slb`、`json → module.json`）；② 测试侧
   `out\export\ImageTest\`（`ImageTest.slb → ImageTest.module.slb` 等，改了 ImageTest.sl
   后必刷，否则 stage 拿旧 module.slb，跑的是旧测试、新断言根本没执行——本次踩过：
   改完测试显示仍是 95 项）。`package\win32-debug\<模块>\` 由 CSimpleVMTest 自动 stage，
   无需手动同步。诊断：`$env:SL_VM_LOG="on"` 后跑 slang.exe，看
   `<测试目录>\build\logs\VM.txt`（`DllStaticImport: not preloaded` / `LoadLibrary failed`
   即命中此坑）。Gif.sl 用 `List<GifFrame>` 而非 `Array`（定长无 add）。
   **DLL 不在 stage 通配内**：CSimpleVMTest 只拷 `*.module.*`，`sl_image_lib.dll`
   须手动 `Copy-Item out\export\SLangImage\sl_image_lib.dll package\win32-debug\SLangImage\`；
   DLL 缺失时 55 个绑定全部静默兜底 SL、测试照样绿但 C 层完全没跑（v0.4 的
   "152 全绿"事后发现实为全兜底——C 调用返回 false 被当普通回落吞掉）。
6. **for-in 帧迭代可跨模块实现 Core.IIterator**：`ImageSequenceIterator interface
   Core.IIterable<GifFrame>, Core.IIterator<GifFrame>`（自迭代，`iterator()` 返回 this）
   后 `for f in it` 直接可用；for-in 的 IR 是 `obj.iterator() → reset() → {moveNext →
   current}` 动态按名派发（IRWhileStatements），接口句柄 `Core.IIterable` 跨模块经
   TryResolveTypeAlias 解析（ProjectReferenceModuleLoader）。
7. **泛型索引器表达式不能直接作跨模块静态方法实参**：模块方法返回 `List<ImageBuffer>`
   后 `List[i]` 索引器表达式直接放进**另一个模块**静态调用实参位（如
   `Image.ImageBuffer.mergeRgba( chans[0], ... )`）→ MetaCore 报"节点[mergeRgba]
   没有在类[ImageBuffer]没有被找到"（模板参数类型在方法重载匹配处不命中，报错
   误导成方法缺失）。传普通变量 / null 字面量都正常。**绕开**：先赋类型化局部
   `Image.ImageBuffer mr = chans[ 0 ]` 再传参（赋值走的隐式转换路径无此问题）。
   同款症状也可用于快速判断：报"方法 not found"但导出 json 方法表齐全 → 先查实参
   是不是泛型索引器表达式。
8. **Std 的 ColorInt.lerp 对下行插值是坏的**：`lerp` 公式 `this.r + toInt((other.r -
   this.r) * t)` 里 `toInt = clamp8(round(v))` 把**中间 delta** 钳到 0..255——负方向
   （255→0）插值 delta<0 被钳成 0，通道永远停在 this 值（上行不受影响）。本模块
   `ImageBuffer.blend` 不用 lerp，改 `im1*(1-a) + im2*a` 最终值直算（结果天然 0..255
   钳制无害）。若要复用 lerp 语义需先修 Std（round+钳 delta），动 Std 要重编译其
   模块链，暂绕开。
9. **VM CallFFIStatic 快路径封送 bug（csimple_lang 侧未修，开关绕开）**：DLL 与
   绑定本身正确（P/Invoke 直测 0 mismatch、毫度旋转 12 项全对），但 VM
   `CallFFIStatic` 对部分新签名实参装载错位——`sli_op_rotate/blend/blend_factor/
   mask_blend/paste_masked` 的 C 调用返回 true 却**不写出参块**，SL 侧读回的是
   `Memory.alloc` 残影（诊断实证：rot180 输出透明黑、blend 输出前一测试的纯蓝、
   brightness 输出全白）；f32 实参版本更严重，触发栈下溢断言（`Caller stack
   underflow binding argument runtime slot`）乃至宿主 AccessViolation 崩溃。
   **绕开**：① 全部 f32 实参改 i32 定点（角度×1000 毫度、alpha/factor×1000）；
   ② `ImageFfi.opFastPathsEnabled`（默认 **false**）门控上述 5 个调用点改走 SL
   兜底，其余 `libOp*`（convolve/resize/convert/fill/paste/split/merge/flip/
   premultiply/grayscale/luma_mean/chops）189 项实测正常不受开关影响。根治须修
   csimple_lang VM 的 CallFFIStatic 实参装载，修好后置 `true` 即全量启用。
   诊断技巧：绑定返回值不足为凭，须直接抽查写出参像素（残影 = 前序测试数据回显）。

## 许可

- stb：公有领域 OR MIT-0（`cvm_image_lib/third_party/stb/LICENSE.md`）
- WIC：Windows 系统组件（COM 接口直调，无再分发负担）
