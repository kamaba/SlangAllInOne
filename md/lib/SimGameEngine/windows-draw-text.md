# Windows 系统 GDI 绘图与字库文本

SimGameEngine 的渲染模块提供两套能力：

- `GdiCanvas`：调用 **Windows 系统自带 GDI** 的离屏画布（由渲染模块的原生层实现，不是语言层软光栅）。
- `Font` → `FontAtlas` → `TextMesh`：从 `.ttf` 字体生成按需动态图集和文字网格。
- `GameManager`：整局游戏的统一入口。

## 1. 何时用哪种

| 需求 | 用哪个 |
|---|---|
| 画 Windows GDI 风格的点/线/矩形/圆/多边形、文字位图，再当纹理用 | `GdiCanvas` |
| 在 3D/2D 场景里显示文字（含中文），字体来自 `.ttf` 文件 | `Font` + `FontAtlas` + `TextMesh` |
| 统一管理场景、帧循环、渲染系统 | `GameManager` |

## 2. GDI 画布 GdiCanvas

```slang
GdiCanvas canvas = GdiCanvas.create( 256, 128 )
if !canvas.isReady()
{
    Console.println( "GDI unavailable" )     # 非 Windows 平台会走这里
}

Int32 clear = GdiCanvas.rgba( 0, 0, 0, 0 )  # 0xAARRGGBB
Int32 red   = GdiCanvas.rgb( 255, 0, 0 )

canvas.clear( clear )
canvas.setPixel( 3, 3, red )
canvas.line( 0, 0, 100, 100, red )
canvas.rect( 10, 10, 40, 40, red )          # 包围盒：(左,上,右,下)
canvas.fillRect( 12, 12, 38, 38, red )
canvas.ellipse( 60, 20, 120, 80, red )      # 椭圆也是包围盒，不是中心+半径
canvas.fillEllipse( 65, 25, 115, 75, red )
canvas.drawText( "Hello GDI", 8, 8, 24, red )  # 系统默认字体，UTF-8 文本
Int32 c = canvas.pixelAt( 3, 3 )            # 越界返回 -1
```

多边形用两条坐标列表：

```slang
List<Float32> xs = List<Float32>( 3 )
List<Float32> ys = List<Float32>( 3 )
xs.add( 3.0f );  ys.add( 3.0f )
xs.add( 30.0f ); ys.add( 3.0f )
xs.add( 3.0f );  ys.add( 30.0f )
canvas.fillPolygon( xs, ys, red, red )      # 描边色、填充色
```

### 2.1 上屏与纹理

```slang
SLang.RenderTexture tex = canvas.createTexture()  # GDI BGRA → RGBA8 上传
canvas.fillRect( 0, 0, 20, 20, red )
canvas.updateTexture( tex )                        # 原位刷新

Int64 pixels = canvas.toRgbaBlock()                # 自建 RGBA8 块 w*h*4
# ... 用完 Memory.free( pixels )
canvas.dispose()                                   # 释放 GDI 画布
```

`createTexture()` 在无渲染上下文时返回 null；`toRgbaBlock()` 不依赖渲染上下文。

### 2.2 可用方法

| 方法 | 说明 |
|---|---|
| `static create(w,h)` / `dispose()` | 创建/释放 GDI 离屏画布 |
| `isReady()` | 平台/原生层是否可用 |
| `static rgba(r,g,b,a)` / `rgb(r,g,b)` / `alphaOf(c)` | 颜色打包与解包 |
| `clear(c)` / `setPixel(x,y,c)` / `pixelAt(x,y)` | 像素操作 |
| `line` / `rect` / `fillRect` / `ellipse` / `fillEllipse` | GDI 笔刷原语，参数 `(x0,y0,x1,y1,c)` |
| `fillPolygon(xs,ys,stroke,fill)` | GDI 多边形填充 |
| `blit(src,x,y)` | GDI 位块拷贝 |
| `drawText(text,x,y,height,c)` | GDI 文本（系统默认字体） |
| `toRgba(dstPtr)` / `toRgbaBlock()` | BGRA → RGBA8 top-down |
| `createTexture()` / `updateTexture(tex)` | 纹理上传/刷新 |

## 3. 字库文本

### 3.1 三步走

```slang
Font font = Font.load( "assets/Fonts/MyFont.ttf" )
if !font.isLoaded()
{
    Console.println( font.lastError() )
}

FontAtlas atlas = FontAtlas.create( font, 48 )  # 48 = 字形槽像素高

TextMesh label = TextMesh()
label.attach( atlas )
label.setText( "Hello 世界" )
label.setFontSize( 32 )
label.setPosition( 40.0f, 30.0f )               # 屏幕像素，左上角为原点
label.setColor( 1.0f, 1.0f, 1.0f, 1.0f )

# 渲染帧里，sync 之后 / frame 之前：
label.draw( rs, 7, 4001 )                       # rs = RenderSystem 实例
```

`draw` 会自动把文本里出现的字烘焙进图集、上传纹理并提交网格。换文本只需 `setText` 后再 `draw`，已缓存的字不会重复烘焙。

### 3.2 离线取顶点

```slang
Int32 n = label.buildVertices( 480, 360, 1.3333f )  # 视口宽/高/宽高比
Int64 ptr = label.vertexPtr()                        # n*16 字节，每顶点 x,y,u,v
```

每字 6 个顶点（2 三角形）；空格和缺字不计顶点但会占宽度。

### 3.3 字库 API

| 对象 | 方法 | 说明 |
|---|---|---|
| `Font` | `static load(path)` / `isLoaded()` / `lastError()` / `dispose()` | 读取 `.ttf` 并判定结果 |
| | `unitsPerEm()` / `glyphCount()` / `glyphForCode(code)` / `advanceOf(gid)` | 字体元数据 |
| | `createGlyph(gid, steps)` | 字形轮廓数据 |
| `FontAtlas` | `static create(font, cellSize)` / `ensureGlyph(code)` / `hasGlyph(code)` | 动态图集 |
| | `glyphCount()` / `lastError()` / `syncTexture()` / `texture()` / `dispose()` | 诊断与释放 |
| `TextMesh` | `attach(atlas)` / `setText(s)` / `setFontSize(n)` / `setPosition(x,y)` / `setColor(r,g,b,a)` | 文本与样式 |
| | `buildVertices(w,h,aspect)` / `draw(rs,slot,queue)` / `dispose()` | 组网格与提交 |

## 4. GameManager

```slang
GameManager gm = GameManager.instance()
gm.initialize( 800, 600 )
gm.createScene( "Main" )
GameObject hero = gm.instantiate( "Hero" )

# 每帧：
gm.update( -1.0f )                        # -1 = 自动实测帧间隔
gm.sync()                                 # 场景 → RenderObject；-1 = 未就绪
gm.frame( dstPtr )                        # RGBA8 出帧

gm.pause()
gm.resume()
gm.destroy( hero )
gm.shutdown()
```

## 5. 注意事项与已知限制

1. `GdiCanvas` 依赖 Windows GDI；非 Windows 平台 `create()` 返回未就绪画布，所有绘制安全无操作。
2. GDI 绘图用的是**包围盒**坐标；`drawText` 用系统默认字体，想指定字体文件请走 `.ttf` 字库链。
3. v1 每次 GDI 绘制后，非透明像素的 alpha 统一置 255；`clear(color)` 的 alpha 会被保留。
4. 字库**不是一次生成所有字**：只烘焙文本用到的字。256×256 图集满时 `ensureGlyph()` 返回 false 并报 `atlas full`。
5. 字库支持带 glyf 的 TrueType `.ttf`；OTF/CFF 与复合字形暂不支持；文字无抗锯齿、无 kerning。
6. 文本提交槽只能是 `7..13`，建议队列 `4001`（FairyGUI 用 `4000`）。
7. 释放顺序：`TextMesh.dispose()` → `FontAtlas.dispose()` → `Font.dispose()`；画布 `GdiCanvas.dispose()`。
