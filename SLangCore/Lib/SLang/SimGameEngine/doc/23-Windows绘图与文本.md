# 23 — Windows 系统 GDI 绘图、字库与文本网格（v2.20）

> 状态：【已落盘】Windows GDI 部分在 `SLangRender` 的 CVM/C 原生层实现（`cvm_render_lib/Platform/sl_gdi.c`），SL 侧只有薄门面 `SLangRender/GdiCanvas.sl`；字库/文本仍是纯 SL。第 22 套 `SimTextDrawTest` 54/54。
> 使用者入口文档：`md/lib/SimGameEngine/windows-draw-text.md`（只讲怎么用）。

## 1. 目标与边界

- `GdiCanvas`：**Windows 系统自带 GDI** 的离屏画布——C 侧 `CreateDIBSection` + `CreateCompatibleDC` + GDI 笔/刷/`Polygon`/`BitBlt`/`TextOutW` 真渲染，不是 SL 软光栅。
- `Font`：读 `.ttf`（sfnt）表，按需把字符码映射到字形轮廓数据（cmap 4/12 + glyf + hmtx + loca）。
- `FontAtlas`：动态字形图集——**只烘焙文本里出现的字**，不是全字符集；新字运行期补烘焙。
- `TextMesh`：把每个可见字生成 1 个 quad（2 三角形 / 6 顶点，pos2+uv2），经 `RenderSystem.submitUiMeshTex` 提交透明 UI 队列。
- `GameManager`：Unity 风格全局主控，把 `Application` 帧循环与 `Systems` 渲染/音频/UI 收口成单一入口。

边界（本版明确不做）：

| 项 | 现状 |
|---|---|
| 非 Windows 平台 GDI | C 导出安全降级（create 返回 0），SL 门面 `isReady()==false` |
| GDI 字体选择 | `TextOutW` 用系统默认字体；指定字体文件请用 `.ttf` 字库链 |
| OTF/CFF 字体 / 复合 glyf | 不支持 |
| 字形抗锯齿 / kerning | 无；二值 alpha，按 hmtx 固定宽度 |
| 每绘制原语 alpha | v1 统一置 255；`clear(color)` 的 alpha 保留（见 §4） |

## 2. 分层：CVM 层 GDI 与 SL 门面

```
SL 消费方 (SimGameEngine / 游戏 / 测试)
        │  GdiCanvas.sl（纯转发，无软光栅）
        ▼
RenderFFI.sl  @DllStaticImport("sl_render_lib", "slr_gdi_*", sig)
        ▼
sl_render_lib.dll  Platform/sl_gdi.c
        │  Windows GDI：CreateDIBSection(HDC) + SelectObject + pen/brush
        │               TextOutW / Polygon / BitBlt
        ▼
32bpp 自顶向下 DIB（BGRA 内存） ── to_rgba / *_texture ──> 库统一 RGBA8 top-down
```

导出链：`vm_sl_render.h` 声明（`SLR_API`）→ `Platform/sl_gdi.c` 实现 → `RenderFFI.sl` 绑定 → `GdiCanvas.sl` 门面；新 `.c` 已登记 `cvm_sl_render_lib.vcxproj` + `.filters`。DLL 由 `Render.jsonc` 的 `vmDlls` 在模块导出期自动 MSBuild 并拷到 `out/export/SLangRender/`。

## 3. C 导出速查（实现契约）

| 导出 | sig / 参数 | 语义 |
|---|---|---|
| `slr_gdi_create` / `destroy` | `(w,h)->i64` / `(i64)->bool` | 创建/释放 DIB 画布，句柄 = `SlrGdiCanvas*` |
| `slr_gdi_size` / `bits` | `(i64,ptr)` / `(i64)->i64` | 尺寸查询 / BGRA 位指针 |
| `slr_gdi_clear` / `set_pixel` / `get_pixel` | 颜色 `0xAARRGGBB` | 清屏 / 写点 / 读点（越界 -1） |
| `slr_gdi_line` / `rect` / `fill_rect` / `ellipse` / `fill_ellipse` | `(i64,x0,y0,x1,y1,color)` | 对应 GDI 笔刷原语 |
| `slr_gdi_polygon` | `(i64, const float* x0,y0..., n, stroke, fill)` | `Polygon`，≤4096 点 |
| `slr_gdi_blit` | `(dst,src,x,y)` | `BitBlt(SRCCOPY)` |
| `slr_gdi_text` | `(i64, utf8, x, y, height, color)` | `MultiByteToWideChar` + `TextOutW`（系统默认字体） |
| `slr_gdi_to_rgba` | `(i64, dst_ptr)` | BGRA → RGBA8（不改尺寸/行序） |
| `slr_gdi_create_texture` / `update_texture` | `(i64)` / `(i64,tex)` | 经既有 `slr_texture_create_rgba` / `_update_rgba` 通道上传 |

## 4. 像素与坐标约定

- DIB 用**负高度**创建 → 内存顶行在前；GDI 内存为 **BGRA**，`toRgba()` 交换 R/B 后才符合库 RGBA8 契约。
- `rect` / `fill_rect` / `ellipse` / `fill_ellipse` 收的是**包围盒 `(x0,y0,x1,y1)`**，不是中心+半径（与旧纯 SL `WinDraw` 不同）。
- `clear(color)` 逐像素写 BGRA（含 alpha）；绘图原语经 GDI 落色后由 `apply_opaque` 把非黑像素 alpha 置 255；`get_pixel` 直接读 DIB，保留真实 alpha。
- 非 Windows 编译：全部导出保留符号但返回 0/false；SL 侧 `GdiCanvas.isReady()` 可直接判。

## 5. 字库文本一帧数据流（未变）

```
Font.load(.ttf) → Font.glyphForCode(UTF-8 码点) → Font.createGlyph(gid, steps)
TextMesh.setText(s) → 筛字 → FontAtlas.ensureGlyph(code) → 扫描线偶奇填充进图集
                                      → RenderTexture.createRgba/updatePixels
TextMesh.buildVertices(w,h,aspect) → 6 顶点/字 → RenderSystem.submitUiMeshTex(slot 7..13)
```

`GameManager` 仍是持有门面：`initialize(w,h)` → `createScene` → 每帧 `update(-1)` / `sync()` / `tm.draw(rs,7,4001)` / `frame(dstPtr)` → `shutdown()`。

## 6. 实测与坑

- 验收：`SimTextDrawTest` 54/54（含 DIB 创建、LineTo、Polygon、BitBlt、TextOutW、BGRA→RGBA8、字库/图集/网格/GameManager）；全量 22 套 **1063 PASS / 33 FAIL**（33 为 v2.11 已登记 fixedDt 回归，无新增）；`RenderTest` EXIT=0（d3d11/web PASS）。
- 坑 1：早期把 GDI 绘图写成 `text/WinDraw.sl` 纯软光栅属于层次错误，已删除；GDI 必须在 CVM 层。
- 坑 2：`get_pixel` 若走 `GetPixel` 会丢 alpha（DIB 32bpp 下 GDI 常写 0），改为直读 DIB 字节。
- 坑 3：C 改动后必须重编 `Render.jsonc` 并同步 `sl_render_lib.dll` 到测试/发布槽位（含调试 zip）；旧 DLL 会使 `isReady()==false`。
- 坑 4（SL 词法）：`bind`/`data`/`half` 保留字、`num` 与类名冲突；跨行 `ret a + b`、`ret list[i]`、表达式下标均会触发 Front 解析异常，先落局部变量。

## 7. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-23 | v2.20 初版：CVM 层 Windows GDI 画布（`slr_gdi_*` 18 导出）+ `GdiCanvas` 门面；`Font`/`Glyph`/`FontAtlas`/`TextMesh`/`GameManager` 纯 SL；第 22 套 54/54 |
