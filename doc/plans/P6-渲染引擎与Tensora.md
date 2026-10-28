# P6 · 渲染引擎 / SLangQT / Tensora 完整版 —— 执行计划

> **定位**：展示型大工程，长期主线。等语言稳定（P0）+ 生态地基（P2）+ 若依标杆（P1）之后再全力投入。
> **总原则**：能借不自研——渲染绑 bgfx/sokol 而非从零写 OpenGL/Vulkan/DX12；数学绑 OpenBLAS 而非自写内核；ML 借 CPython（P4）先展示、Tensora 自研长线补。
> **依赖**：P0（FFI）为 6-A/6-B 共同前置；P5（AOT）为 GPU 后端前置。

---

## 6-A · 渲染引擎

### 现状

`SLangCore\Lib\SLang\Render\` 已有 52 个类型文件：类型层（Mesh/Material/Texture/Shader/Camera/Color/Transform/Vertex/Ray/Bounds）+ 管线层骨架（Pipeline/GfxBackend/GfxDevice/CommandBuffer/CommandQueue/RenderPass/RenderTarget/PipelineState/RootSignature/URP）+ 图像音频（Png/Jpeg/Webp/Svg；Wav/Mp3）+ UI 骨架（RectTransform/UIBehaviour）。**全部是 SL 类型声明，无真实图形后端**。

### 架构：三层切分

```
┌─ 场景/UI 层（SL，已有骨架）
│   Camera / Light / Behaviour / RectTransform / URP 编排
├─ 渲染管线层（SL，已有骨架）
│   RenderPass / PipelineState / CommandBuffer / RenderTarget 语义
└─ RHI 绑定层（本计划新增）
    bgfx 或 sokol —— FFI 直调（P0），跨 D3D12/Vulkan/Metal/OpenGL
```

### 任务分解

**T1 · RHI 后端选型（1 周）**

| 候选 | 优势 | 劣势 |
|------|------|------|
| **bgfx**（首选） | 跨 12 个后端（D3D12/11/Vulkan/Metal/GL/ES）、C API、回调少、MIT | 体积 ~1MB、调试层一般 |
| **sokol** | 单头文件、极简、贴合 C99 | 后端少（无 D3D12）、功能面窄 |

验证点：P0 FFI 下 Windows D3D11 + Linux GL 双平台各画一个三角形。

**T2 · RHI 绑定层（2~3 周，依赖 P0）**

1. `Project/cvm_gfx_lib/`（vcxproj，仿 cvm_math_lib）：动态装载 bgfx.dll，暴露 SL 稳定 API（同 P3 webview 模式——后端升级不重编 VM）；
2. `.slffi.json` 契约：init/frame/draw/创建顶点缓冲/纹理/着色器核心集；
3. 回调桥：bgfx 的截图/调试回调 → P0 trampoline → SL；
4. **帧循环集成**：bgfx frame 与 VM 协程共存模型——渲染线程独立 isolate，逻辑帧经 Channel 投递命令（**与 isolate 消息模型天然契合，渲染引擎是 isolate 的最佳实战**）。

**T3 · 管线层落地（2~3 周）**

1. 现有 Pipeline/*.sl 骨架对接 T2：CommandBuffer 语义 → bgfx 调用序列；PipelineState → bgfx 程序/状态块；
2. Shader 跨编译：bgfx 自带着色器编译器（shaderc），`.sl` 工程集成：jsonc 声明 `.sc` 着色器源 → 编译期产出平台变体；
3. 第一帧里程碑：**加载 Mesh + 贴图 + 光照着色器的完整 URP 单帧**。

**T4 · 场景与 2D 先行（2 周）**

1. 软件光栅先行验证数学层（Ray.sl / Int32_2/3 / 矩阵已有）：Canvas 绘图示例（samples/GUI 已有）扩展为 2D 图形库（画线/填充/文字/图集）；
2. 2D Demo：TankGame（test 里已有 TankGame 用例）升级硬件加速版——**第一个可玩的展示项目**；
3. 3D 后续：网格加载（obj/glTF）→ 摄像机控制 → 光照/阴影。

**T5 · 图像/音频补全（按需）**

- Png/Jpeg/Webp 编解码 FFI 绑定（libpng/libjpeg-turbo/webp——spm 包分发）；
- Audio：miniaudio 绑定（单头，播放/采集）。

### 验收（6-A）

- [ ] 双平台硬件加速三角形 → 完整 URP 一帧（Mesh+Texture+Light）；
- [ ] TankGame 硬件版可玩，帧率 ≥60；
- [ ] 渲染 isolate 与逻辑 isolate 经 Channel 通信，帧循环不阻塞 VM；
- [ ] RHI 绑定以 spm 包分发（gfx 包 + 平台原生库）。

---

## 6-B · Tensora（张量库）

### 现状

`SLangCore\Lib\SLang\Tensora\` 30 个文件：Tensor（Float32 扁平存储 + 广播）/ Shape / Autograd / Optimizer / Layer 系（Dense/Conv/Attention/Transformer）/ Trainer / Dataset / Metrics——**纯 SL 实现，无 BLAS，只能教学演示**。定位建议：**教学 / 嵌入式推理优先，训练端短期不与 PyTorch 竞争**（P4 CPython 插件是逃生通道）。

### 任务分解

**T1 · OpenBLAS 绑定（1~2 周，依赖 P0，性价比最高）**

1. `Project/cvm_blas_lib/`：动态装载 OpenBLAS（`cblas_sgemm / sgemv / saxpy / sscal` 核心集）；
2. Tensor.matmul / 广播矩阵运算下沉：`systemCalls` 走 cvmFunction（同 math_lib 模式，R7 四处同步）；
3. 性能目标：matmul 1024×1024 对比纯 SL 版 ≥ **20 倍**提升（BLAS SIMD + 多线程）；
4. spm 分发：blas 包（`lib\windows\libopenblas.dll` 等）。

**T2 · CPU 完善版（2~3 周）**

1. 算子补全：反池化/转置卷积/组归一化/掩码 softmax 等推理必需算子；
2. 内存布局：NHWC/NCHW 转换工具 + contiguous/detach 语义（已有 copyFrom 基础）；
3. 序列化：模型保存/加载（复用 Core 序列化 + Protobuf）；
4. 精度：Float16 推理路径（语言已有 Float16 原生语义——**差异化卖点**）。

**T3 · numpy 互通（1~2 周，依赖 P4）**

1. Tensor 底层 `Array<Float32>` ↔ numpy ndarray **缓冲区协议零拷贝**（P4-T3 的性能路径）；
2. `Tensor.fromNumpy / toNumpy`；pandas 读数据 → SL Table → Tensor 全链。

**T4 · 推理 Demo（2 周）**

1. 端到端：PyTorch 训练（经 P4）→ 导出权重 → Tensora 加载推理（教学闭环故事："训练在 Python，推理在 SLang"）；
2. 嵌入式叙事：小模型 + Float16 + AOT（P5 M1）→ 裁剪运行时（对接 target.md 的 ESP32-P4 愿景）。

**T5 ·（远期）GPU 后端**

- 依赖 P5 AOT：kernel 编译路径（或 WebGPU/wgpu 绑定先行评估）；
- 与 6-A RHI 层共享 GpuResource 抽象（Render/Pipeline/GpuResource.sl 已有占位）。

### 验收（6-B）

- [ ] matmul 走 BLAS 后 1024³ 基准 ≥20 倍提升，数据公布；
- [ ] Transformer 推理 Demo（PyTorch 训练 → Tensora 推理）端到端；
- [ ] numpy 零拷贝互通验证（大 tensor 无拷贝时延）；
- [ ] blas 包 spm 可装。

---

## 6-C · SLangQT（条件立项）

**立项条件**（全部满足才启动）：
1. P3 webview 验证 GUI 需求真实存在且**原生控件是刚需**（非 Web 能覆盖）；
2. P0 FFI struct 描述符 + 回调稳定；
3. clang/libclang 绑定脚手架可用（见下）。

**制作要点**：
1. **libclang 脚手架先行**（不属于用户级插件，属开发工具）：用 libclang 解析 QT 头文件 → 自动生成 `.slffi.json` 契约 + SL 侧类声明（QObject 子类/枚举/信号槽签名）——**不手写 QT 绑定**；
2. 值转换层：QString ↔ SL string（经 UTF-8）、QList/QVariant 专用 marshal（P0 L3 复合层扩展）；
3. signal-slot：QT 信号 → P0 trampoline → SL 闭包（连接管理：QObject 销毁时自动断连——生命周期对齐是最大风险点，需成文）；
4. 事件循环：QT exec 与 isolate 渲染线程模型对齐（同 6-A T2 的帧循环问题）；
5. 分发：qt 包按模块拆分（qt-core / qt-widgets / qt-quick），spm 平台矩阵。

**验收**：非手写绑定覆盖 QObject 核心 + widgets 常用控件，自动生成率 ≥90%；最小 QMainWindow 应用可跑。

---

## 执行顺序与依赖

```
P0 (FFI) ──► 6-A T1/T2 (RHI 绑定) ──► T3 管线 ──► T4 2D/3D ──► T5 图像音频
    │    ──► 6-B T1 (OpenBLAS) ──► T2 CPU 完善 ──► T3 numpy 互通 ──► T4 推理 Demo
    │                                                                    │
    └──► (条件) 6-C libclang 脚手架 ──► SLangQT                          ▼
P5 (AOT) ──► 6-B T5 GPU 后端 / 嵌入式叙事                        P4 (CPython)
```

## 风险与对策

| 风险 | 对策 |
|------|------|
| 渲染/Tensora 双线摊薄精力 | 串行：先 6-B T1（OpenBLAS 一周见效）再 6-A；同一时间只推一条 |
| bgfx API 面大绑定周期长 | T2 只绑核心 20 函数跑通三角形，按需增量扩 |
| QT 生命周期对齐复杂 | 6-C 条件立项硬门槛；libclang 脚手架先行验证再投入 |
| Tensora 训练端生态竞争 | 定位锁死教学/推理/嵌入式，训练叙事交给 P4 |
