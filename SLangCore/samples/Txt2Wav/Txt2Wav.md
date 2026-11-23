# Txt2Wav —— SLang 文本转语音示例技术文档

> 仿开源神经 TTS（Tacotron 风格）的简版实现。混合路线：**网络结构是真实的神经组件**（Embedding / GRU / softmax 注意力 / Dense，全部经 Tensora 前向计算），但**参数不靠训练**——把"训练要学的音素→声学映射"直接用语音学规则表注入权重。零训练、零外部模型文件、开箱出声。

- 源码目录：`SLangCore/samples/Txt2Wav/`
- 运行方式：`package/win32-release/slang.exe Txt2Wav.jsonc`（编译 + 运行一体）
- 依赖模块：`Tensora`（张量/GRU/注意力/GPU 后端）、`SLangAudio`（AudioBuffer/WAV 编码）、`Core/Std/Math`

---

## 1. 文件结构

| 文件 | 职责 |
|---|---|
| `Txt2Wav.sl` | `Txt2WavEngine`（管线组装 + 快慢路径）与 `Txt2Wav` 控制台 demo |
| `Txt2WavG2p.sl` | `Txt2WavLexicon`（音素声学表 + G2P 规则数据）+ `Txt2WavFrontend`（归一化 / G2P / 编码） |
| `Txt2WavModel.sl` | `Txt2WavEncoder`（Embedding+GRU）+ `Txt2WavDecoder`（注意力+Postnet+F0） |
| `Txt2WavVocoder.sl` | `Txt2WavVocoder`（源-滤波谱合成 + 相位传播 + ISTFT + Griffin-Lim） |
| `Txt2Wav.jsonc` | 工程配置（references 指向 `out/export` 各模块 slb） |

## 2. 数据流总览

```
英文文本
  │ ① 前端：归一化 → 词典/规则发音 → 音素 id
  ▼
ids [P]                 # 音素 id 序列（P = 音素数）
  │ 时长规则：每音素 durMs / 16ms → 帧数 durs[P]
  ▼
  │ ② 编码器：Embedding 查表 → GRU 逐音素递推
  ▼
enc [P,8]               # 协同发音平滑后的音素级声学特征
  │ ③ 解码器：focus 硬对齐 + softmax 注意力展开 + Postnet
  │          （同时生成 f0[T] 韵律轨迹）
  ▼
ctx [T,8]               # 帧级声学参数（T 帧 × 16ms）
  │ ④ 声码器：源-滤波谱合成 → 相位传播 → ISTFT → Griffin-Lim
  ▼
y [M]                   # Float32 波形（M = (T-1)·256 + 512 采样点）
  │ 峰值归一化 0.82 + 淡入淡出 → AudioBuffer → Wav.encode
  ▼
txt2wav_N.wav           # 16kHz 单声道 16bit PCM
```

---

## 3. 文本前端（Txt2WavG2p.sl）

### 3.1 音素声学表

35 个 ARPAbet 子集音素，内置于 `f"""` 块字符串（[Txt2WavG2p.sl:65-101](Txt2WavG2p.sl)），每行 9 列：

```
名称  F1   F2   F3   浊音  振幅  时长ms  噪声占比  带宽系数
AA   730  1090 2440  1   1.00  130    0.00     1.0
S    700  5500 7000  0   0.75  100    1.00     1.6
_    500  1500 2500  0   0.02  160    0.00     1.0
```

- **F1/F2/F3**：共振峰频率（Hz，男性近似值），来自经典语音学图表。这是声码器"滤波器"的参数来源。
- **浊音**：1 = 声带振动（元音/鼻音/浊擦音），0 = 纯噪声激励（清擦音/清塞音）。
- **振幅**：响度（元音 1.0，塞音 ~0.55-0.65，静音 `_` 0.02）。
- **时长 ms**：决定该音素占多少个 16ms 帧（元音 100-140ms，塞音 50-60ms，停顿 160ms）。
- **噪声占比**：摩擦噪声混入比例（擦音 1.0，浊擦音 0.55-0.7，塞音 0.45/0.85）。
- **带宽系数**：共振峰宽度（决定音色"开口度"感知，鼻音 2.0 最宽）。

35 个音素分 6 类：10 元音（AA AE AH AO EH ER IH IY UH UW）、6 塞音（B D G P T K）、3 鼻音（M N NG）、9 擦音（F V TH DH S Z SH ZH HH）、4 近音（L R W Y）、2 塞擦音（CH JH）+ 1 静音（`_`）。

### 3.2 G2P（字母 → 音素）：五级优先规则

`Txt2WavFrontend.g2pWord()` 按以下优先级逐词转换：

1. **例外词典**（90+ 高频词，`DICT_WORDS`/`DICT_PHONES`）：`the→DH AH`、`hello→HH EH L OW`、`world→W ER L D` 等，保证演示句发音正确。
2. **三字母规则**（3 条）：`igh→AA Y`（light）、`tch→CH`（match）、`ear→IH R`（hear）。
3. **双字母规则**（37 条，最长优先）：`ch/sh/th/ph/qu/oo/ee/ea/...` + 双写辅音。含两处修正：
   - `ar/er/ir/or/ur`（规则表 20-24 号）后跟元音时退化逐字母处理，避免误吞 `era`；
   - `kn/wr` 只在词首生效（`know` 不发音的 k/w）。
4. **魔法 e**（`v C e` 词尾，占 3 字母）：`make→EH Y`、`like→AA Y`、`code→AO W`、`use→UW`。
5. **单字母规则**：
   - `c`/`g` 在 e/i/y 前软化：`city→S`、`gem→JH`，否则 K/G；
   - `y` 按位置：词首 Y（yes）、词尾 IY（my）、词中 IH（system）；
   - 词尾静音 e 直接跳过（`table`，be/me 类词已在词典）；
   - `x→K S`，其余单字母直映射。

### 3.3 归一化与韵律标记

`normalize()`：大写→小写；数字逐位展开为单词（`2026→two zero two six`）；标点归一为空格，其中 `?` 置 `risingTail = true`（疑问句升调）。`toPhones()` 在句首、词间、句尾插入停顿音素 `_`（词间短停顿帮助听感分词）。

### 3.4 数字解析的坑

音素表解析用自写 `parseNum()` 逐字符解析（支持负号/小数）——SL 的 `SystemConvertFloat32(string)` 在此语境返回垃圾值（实测教训，已记录在源码注释）。

---

## 4. 编码器：Embedding + GRU = 协同发音（Txt2WavModel.sl）

### 4.1 Embedding 表：音素 → 8 维声学特征

`applyRules()` 直接把音素表的声学参数写入嵌入表（缩放到 |x| ≤ 0.5，避免后续 tanh 失真）：

| 维 | 含义 | 缩放 | 反归一化（声码器侧） |
|---|---|---|---|
| 0 | F1 归一 | F1/2000 | ×2000 |
| 1 | F2 归一 | F2/6000 | ×6000 |
| 2 | F3 归一 | F3/4000 | ×4000 |
| 3 | 浊音标志 | 0/1 | >0.4 → voiced |
| 4 | 振幅 | amp·0.5 | ×2 |
| 5 | 时长 | dur/250 | （时长在引擎层直接用原始 durMs） |
| 6 | 噪声占比 | nmx·0.5 | ×2，clamp 1 |
| 7 | 带宽系数 | bwn·0.5 | ×2，clamp ≥0.5 |

### 4.2 GRU 规则注入：一阶惯性环节

GRUCell 标准前向（Tensora 实现，wAll 形状 `[3h, in+h]`，行 = 门，`forward = concat(x,h)·wAllᵀ + bias`）：

```
z = σ(Wz·[x;h] + bz)      # 更新门
r = σ(Wr·[x;h] + br)      # 重置门
n = tanh(Wn·[x;h] + r⊙Un·h)
h = (1-z)⊙n + z⊙h
```

规则注入（[Txt2WavModel.sl:69-87](Txt2WavModel.sl)）：

- wAll 全零，仅 **n 门输入块（行 2h..3h-1，列 0..h-1）放单位阵** → `n = tanh(x)`（|x|≤0.5 时 tanh(x) ≈ x）；
- **z 门 bias = 0.62** → σ(0.62) ≈ 0.65，即 h 保留 65% 旧态；
- r 门 bias = 4.0 → σ(4.0) ≈ 0.98，重置门近似全开（不影响 n）。

退化结果：

```
h[t] ≈ 0.35·x[t] + 0.65·h[t-1]
```

这正是**一阶惯性环节（指数平滑）**。语音学意义 = **协同发音（coarticulation）**：辅音与元音交替时，共振峰特征连续滑变而非跳变，听感自然。频响截断约为每音素 65% 衰减，3 个音素后旧特征残留 ~27%。

注意：`forward()` 开头 `this.gru.hPrev = Tensor(...)` 每句重置隐状态，避免跨句泄漏。

输出 `enc [P,8]`：每行是一个"平滑后"的音素声学特征向量。

---

## 5. 解码器：注意力时长展开 + 韵律（Txt2WavModel.sl）

### 5.1 时长规则（引擎层）

`Txt2WavEngine.synthesize()` 中：每音素帧数 = `durMsOf(id) / 16`（至少 1 帧）。16ms 来自 `16000Hz / hop 256`。得到 `durs[P]`，总帧数 `T = Σ durs`。

### 5.2 注意力：硬对齐 + softmax 的矩阵化实现

先构造**焦点数组** `focus[t] = 帧 t 所属音素索引`（整数硬对齐，`forward()` 前半段），然后全矩阵化（无逐帧循环，GPU 友好）：

```
fTile  = focusCol[T,1] · ones[1,P]     # 每行重复 focus(t)
jTile  = ones[T,1] · jRow[1,P]         # 每列 0..P-1
logits = (fTile - jTile)² · (-18)
attn   = softmax(logits)               # [T,P]
ctx    = attn · enc                    # [T,P]·[P,8] → [T,8]
```

**数值分析**：`diff=1` 时权重比 `e^-18 ≈ 1.5×10⁻⁸`——softmax 后每个帧几乎完全落在自己的焦点音素上，等效于查表 `ctx[t] = enc[focus(t)]`。真正的"音素边界交叉淡化"并不来自这层注意力，而是**提前在编码器 GRU 完成**（音素特征本身已经平滑）。这里保留 softmax 注意力形式是为了结构与真实 TTS 对齐，且保留把锐度系数调低即可获得软对齐的扩展空间。

### 5.3 Postnet：振幅补偿

Dense(8,8) 恒等阵 + 一处规则：`weight[4,3] = 0.2`——voiced（第 3 维）向振幅（第 4 维）泄漏 0.2，浊音响度补偿。在设备上一次 matmul 完成。

### 5.4 F0 韵律轨迹（规则生成）

`makeF0(frames, rising)`：

```
陈述句: f0(t) = 115·(1 - 0.14·prog)      # 115 → 98.9 Hz 降调
疑问句: f0(t) = 112·(0.86 + 0.34·prog)   # 96.3 → 126.8 Hz 升调
微颤:   vib = 3.5·sin(2π·4.2·t·0.016)    # 4.2Hz vibrato，±3.5Hz
```

`prog = t/(T-1)` 归一进度。微颤避免"机器人味"的恒定音高。`rising` 来自前端 `?` 标记。

---

## 6. 声码器：谱合成 + 相位重构（Txt2WavVocoder.sl）

### 6.1 参数与常量基

```
sampleRate = 16000, nfft = 512, hop = 256, specBins K = 257
binHz = 16000/512 = 31.25 Hz/bin
```

初始化时构造三组**常量矩阵**并上传设备（`buildBases()`）：

- **Hann 窗** `w[0..511]`（周期式）；
- **STFT 分析基** `AC[k,n] = win·cos(2πkn/N)`、`AS[k,n] = -win·sin(...)`（转置后 [N,K] 存放）；
- **ISTFT 合成基**（IDFT 折叠，含 1/N 归一）：`x[n] = (1/N)·[Re₀ + Re_{K-1}·(-1)ⁿ + Σ 2(Re_k·cos - Im_k·sin)]`——直流（k=0）与奈奎斯特（k=K-1）频率特殊处理不乘 2。

CPU 兜底路径额外保存转置数组 `synBCT/synBST [N,K]`（行主序、内层 k 连续，cache 友好）。

### 6.2 源-滤波幅度谱合成（synthMagnitude）

逐帧逐 bin 的纯数组数值循环（性能设计见 §8）：

```
f0t   = max(f0[t], 20)
b1,b2,b3 = 105·bw, 150·bw, 210·bw          # 共振峰带宽

# 共振峰包络：三个高斯叠加（权重 1 / 0.55 / 0.3）
env = exp(-((f-F1)/b1)²) + 0.55·exp(-((f-F2)/b2)²) + 0.3·exp(-((f-F3)/b3)²)

# 谐波梳齿：O(1) 实现
h   = round(f/f0t)（≥1）                    # 最近谐波号
dd  = f/f0t - h                             # 与谐波的相对偏差
tooth = exp(-20·dd²)                        # 高斯梳齿窗
comb = tooth / h                            # 1/h 谐波衰减

tone  = env · comb · voiced                 # 浊音分量
noise = env · √(f/7800) · noiseMix          # 清音摩擦谱（高频上翘）
hp    = clamp(f/160 + 0.12, 0.12, 1.0)      # 低频滚降（去隆隆声）
mag[t,k] = amp · (tone + noise) · hp
```

**源-滤波模型**：`comb` 是"源"（声带脉冲串的谐波结构，跟着 F0 走），`env` 是"滤波器"（声道共振峰包络，决定元音身份）。梳齿用"最近谐波高斯窗"实现，不需要逐谐波循环——每个 bin 一次 exp。

### 6.3 相位传播（initPhase）

相位决定波形是否可听。随机相位 = 白噪声感；这里用**谐波相位递推**：

```
φ[t,k] = φ[t-1,k] + round(f_k/f0)·2π·f0·hop/sr
```

即：第 k 个 bin 对应第 `round(f_k/f0)` 次谐波，谐波相位每帧前进 `2π·f0·hop/sr`（f0×hop 的相位增量），帧间天然连续。每帧把相位 wrap 到 [0,2π)（Float32 防精度损失），清音帧按 noiseMix 比例混入 `Rng` 随机相位。输出 `re/im [T,K]`。

### 6.4 ISTFT 与 Griffin-Lim

**ISTFT**（`istft`）：

- GPU 路径：`frames = re·synB + im·synBS`（两次 matmul），乘窗，回 CPU；
- CPU 路径：转置数组 DFT（`Σ_k re[t,k]·SBcT[n,k] + im[t,k]·SBsT[n,k]`），避免 Tensor.matmul 在 CPU 上退化到 L0 解释循环的逐元素 `at()`（慢两个数量级）；
- overlap-add：`y[t·256 + n] += fw[t,n]`。

**Griffin-Lim 迭代**（glIters 次）：当前波形 STFT → 幅度谱向目标投影 → 回 ISTFT：

```
Y = STFT(y)
对每个 [t,k]：sc = mag[t,k] / (|Y[t,k]| + 1e-6)
Y' = (Re·sc, Im·sc)          # 保相位、改幅度
y  = ISTFT(Y')
```

投影在 **CPU 数组**上做（GPU 只留 STFT/ISTFT 的 matmul）——张量算子链版本每迭代分配 ~10 个 T×K/T×N 装箱数组触发 GC 风暴，实测每迭代固定 ~15s；数组版 <1s。

### 6.5 后处理

峰值归一化到 **0.82**（留 s16 余量），首尾 **10ms 淡入淡出**（`fade = sampleRate/100 = 160` 采样，clamp 不超过总长 1/4）。

---

## 7. 引擎与控制台（Txt2Wav.sl）

- **设备探测**：`Backends.setCudaEnabled(true)` + `Backends.available(EDeviceKind.GPU)`；有卡走 `Device.gpu(0)`，否则 `Device.cpu()`。
- **快慢路径**（`synthesize()` 内）：

```
GPU 且 synthCount >= 2 → glIters = 2（后续句 GL 精修）
否则                   → glIters = 0（前两句/CPU 跳过 GL）
```

前两句用相位传播版已保证帧间连续性，跳过 GL 换首响应速度；之后开 2 轮 GL 打磨音质。CPU 恒跳 GL（其 STFT/ISTFT 是慢路径）。

- **输出统计**：每句打印 phones/frames/duration、frontend/neural/vocoder 分段耗时、RMS 能量（静音自检）。
- **WAV 写盘**：`AudioBuffer(16000, 1, n)` → `Wav.encode` → `File.writeAllBytes`（16kHz mono s16 PCM，无 ffmpeg 依赖）。
- **交互模式**：内置 4 句演示（前两句最短，保证首响应）；之后输入英文合成，`cpu:` / `gpu:` 前缀强制切换设备（切换时重建引擎），空行/quit 退出。
- **异步计算（默认开）**：解码器注意力中两个互不依赖的 tile 矩阵乘通过 `TensorAsync.matmulAsync` + `waitAll` 并发提交，默认协程模式；需要后台线程时设 `eng.decoder.computeMode = EComputeMode.Iso`。
- **Isolate 幅度谱分片（可选）**：设 `eng.vocoder.asyncMag = true` 后，幅度谱逐帧循环按行块拆给 isolate 后台线程，`magChunks` 控制分片数（默认 2）。结果数值与默认路径一致；但当前 isolate 消息只支持 `List<T>`，`T×K` 结果的逐元素装箱开销在本机实测比默认路径慢 8~18%，因此默认关闭。

## 8. 性能设计（实测教训）

| 问题 | 原因 | 解法 | 效果 |
|---|---|---|---|
| 谱合成 21s | `square/scale/round` 无 GPU 分支，算子链被拉回 CPU 解释循环；`tile()` 走 CPU matmul 的 T×K 次 `at()` | `synthMagnitude` 改纯数组数值循环，一次构造、一次上传 | 21s → 0.2s（98×） |
| GL 每迭代 ~15s | 张量链每迭代分配 ~10 个 T×K/T×N 装箱数组 → GC 风暴 | 投影改 CPU 数组循环，GPU 只留 matmul | 30s → 1.7s |
| CPU 模式跑不完 | SIMD 探测为空时 matmul 退化 L0 解释循环 | ISTFT 加转置数组 DFT 分支 + CPU 强制 gl=0 | 2-8.5s/句 |
| 句间音高断裂 | 每句独立合成、相位随机 | 相位传播 + GPU 快路径前两句免 GL | 帧间连续 |
| 幅度谱 isolate 分片 | 回传只能走 `List<T>`，大结果逐元素装箱 | 默认 Array 直算，`asyncMag=true` 才分片 | 数值一致；本机实测慢 8~18% |

**设计原则**：批量线性代数（matmul/exp/sqrt/softmax）交 Tensora（GPU kernel / CPU SIMD / L0 兜底自动分派）；逐元素热循环用裸 `Array<Float32>`（装箱数组逐元素操作 ~1μs/次，避免张量分配触发 GC）。

## 9. 已验证结果

- GPU（CUDA）：内置前两句 ~0.34s/句（gl=0），长句（16 词）~2.7s（gl×2）；
- CPU：2-8.5s/句（视句长）；
- 4 个 wav 产物经 python `wave` 校验：16kHz/mono/s16 格式正确，peak 0.82 满幅未削顶，淡入淡出生效，rms 非零（非静音）；
- 疑问句（`?` 结尾）F0 轨迹上行、陈述句下行，符合预期。

## 10. 已知限制与扩展方向

- 仅英文；G2P 是规则式，词典外生词按字母规则发音（人名/缩写可能失真）。
- 无训练：韵律单一（固定降/升调 + 均匀时长），无重音/语调词级变化。
- v1 仅 FLOAT 权重、无声调语言支持；节点图解析 / 前向执行器（加载真实 ONNX 声学模型）是 Tensora Cvm §8 立项方向。
- 音质上限受制于 Griffin-Lim（相位仅近似），后续可换声码器式神经上采样或 WaveNet 风格自回归采样。
