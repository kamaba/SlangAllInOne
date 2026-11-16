# 12 — 环境查询与诊断（已实现）

> 对应实现：`Environment.sl`（RenderEnvironment）+ `sl_render_lib.c` 计数绑定。
> 验收：RenderTest Phase ENV。

## 1. RenderEnvironment（一次性快照）

```sl
RenderEnvironment env = RenderEnvironment.query()
```

静态 `query()` 从 C 侧拉一份只读快照；实例字段可直接读写（草稿层），但
运行时危险操作请仅用于诊断打印。

| 字段 | 含义 |
|---|---|
| `available` / `initialized` | 渲染库探测 / 初始化状态 |
| `backend` | 当前实际生效后端（"gl"/"d3d11"/"vk"/"gles"） |
| `gpuRenderer` / `gpuVersion` | GPU 描述串（透传 Render.gpuName 等） |
| `contextCount` / `contextCapacity` | 上下文计数 / 上限（16） |
| `pipelineCount` / `pipelineCapacity` | 管线计数 / 上限（32） |
| `textureCount` / `textureCapacity` | 纹理计数 / 上限（64） |
| `commandCapacity` / `argCapacity` / `floatCapacity` | 命令缓冲三段容量（256/2048/8192） |
| `transparentQueueMin` | 透明队列分界（2500） |
| `lastErrorText` | 最近一次错误串（"ok" = 无错） |

## 2. 静态查询 API

```sl
bool   ok   = RenderEnvironment.isAvailable()
string list = RenderEnvironment.backendList()        # "gl,d3d11,vk,gles"
string cur  = RenderEnvironment.currentBackend()
bool   sup  = RenderEnvironment.isBackendSupported( "vk" )
string gpu  = RenderEnvironment.gpuName()
string ver  = RenderEnvironment.gpuVersion()
```

与 `SLang.Render.*` 门面等价（RenderEnvironment 内部透传），二者任选。

## 3. 诊断实践

1. **初始化失败排查**：`Render.initialize()` 返回 false 后读
   `Render.errorString()` / `RenderEnvironment.query().lastErrorText`；
2. **后端降级感知**：vk/gles 库缺失时 `currentBackend()` 仍是上次成功后端，
   `initializeBackend` 返回 false——上层应比较 `backendList()` 与
   `currentBackend()` 决定 SKIP；
3. **资源余量监控**：`textureCount` 逼近 64、`pipelineCount` 逼近 32 时应
   显式 `destroy()` 复用；
4. **命令流容量**：单帧命令总数受 `commandCapacity=256` 约束（多 Pass
   顺序录制共享一条流时尤其注意，见 `11-Pass-System.md`）。
