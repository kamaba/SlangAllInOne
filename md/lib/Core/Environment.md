# Environment.sl

> 源文件：`Environment.sl`

## class `OSVersionNumber`

- **说明**：OSVersionNumber - numeric OS version (§13.5: numeric layer, for >=).

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 major()` | 获取 major 的值。 |
| 属性 | `get Int32 minor()` | 获取 minor 的值。 |
| 属性 | `get Int32 build()` | 获取 build 的值。 |
| 属性 | `get Int32 patch()` | 获取 patch 的值。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `ProbeOSVersionNumber`

- **说明**：ProbeOSVersionNumber - numeric OS version, raw probe (§8.5.6). Mirrors OSVersionNumber but reads the probe channel, so it ignores the "osversion" SET override. Used by probe.osVersionNumber.

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 major()` | 获取 major 的值。 |
| 属性 | `get Int32 minor()` | 获取 minor 的值。 |
| 属性 | `get Int32 build()` | 获取 build 的值。 |
| 属性 | `get Int32 patch()` | 获取 patch 的值。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `Cpu`

- **说明**：Cpu / Ai / Render / Network / Script / Embedded - six new category detail objects (PLATFORM_CAPABILITY_DESIGN §12.12-12.17, P2.7b). Bound to Environment.current (effective view) or Environment.probe (raw values). Members are instance getters — reach them through Environment.current.cpu.physicalCores Environment.current.script.has( "python", "3.8" ) Enum-typed members return Int32 — compare against the Platform member (e.g. Environment.Platform.ai.cann). ── cpu topology (§12.12; current channel) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 topology()` | 0=unknown 1=single 2=smp 3=bigLittle 4=hybrid 5=numa. |
| 属性 | `get Int32 physicalCores()` | 获取 physicalCores 的值。 |
| 属性 | `get Int32 logicalCores()` | 获取 logicalCores 的值。 |
| 属性 | `get bool hasHyperThreading()` | 获取 hasHyperThreading 的值。 |
| 属性 | `get Int32 numaNodes()` | 获取 numaNodes 的值。 |
| 属性 | `get Int32 freqMHz()` | 获取 freqMHz 的值。 |
| 属性 | `get Int32 maxFreqMHz()` | 获取 maxFreqMHz 的值。 |
| 属性 | `get Int32 cacheL1KB()` | 获取 cacheL1KB 的值。 |
| 属性 | `get Int32 cacheL2KB()` | 获取 cacheL2KB 的值。 |
| 属性 | `get Int32 cacheL3KB()` | 获取 cacheL3KB 的值。 |
| 属性 | `get Int32 perfCores()` | 获取 perfCores 的值。 |
| 属性 | `get Int32 efficiencyCores()` | 获取 efficiencyCores 的值。 |

## class `ProbeCpu`

- **说明**：── cpu topology (§12.12; probe channel — raw values) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 topology()` | 获取 topology 的值。 |
| 属性 | `get Int32 physicalCores()` | 获取 physicalCores 的值。 |
| 属性 | `get Int32 logicalCores()` | 获取 logicalCores 的值。 |
| 属性 | `get bool hasHyperThreading()` | 获取 hasHyperThreading 的值。 |
| 属性 | `get Int32 numaNodes()` | 获取 numaNodes 的值。 |
| 属性 | `get Int32 freqMHz()` | 获取 freqMHz 的值。 |
| 属性 | `get Int32 maxFreqMHz()` | 获取 maxFreqMHz 的值。 |
| 属性 | `get Int32 cacheL1KB()` | 获取 cacheL1KB 的值。 |
| 属性 | `get Int32 cacheL2KB()` | 获取 cacheL2KB 的值。 |
| 属性 | `get Int32 cacheL3KB()` | 获取 cacheL3KB 的值。 |
| 属性 | `get Int32 perfCores()` | 获取 perfCores 的值。 |
| 属性 | `get Int32 efficiencyCores()` | 获取 efficiencyCores 的值。 |

## class `Ai`

- **说明**：── ai stacks (§12.13; current channel) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool has(Int32 stackId)` | Whether the AI stack member is available (effective view: honours --disable / --enable ai.&lt;name&gt; overrides). 参数名 stackId：stack 是小写容器构造糖（stack() =&gt; Stack），避免使用 |
| 方法 | `string version(Int32 stackId)` | Detected version of the AI stack ("" when unknown or absent). |
| 方法 | `bool any()` | Whether any AI stack is available. |
| 属性 | `get string preferred()` | Best available AI stack name ("" when none, §12.13). |

## class `ProbeAi`

- **说明**：── ai stacks (§12.13; probe channel — raw values) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool has(Int32 stackId)` | 参数名 stackId：stack 是小写容器构造糖（stack() =&gt; Stack），避免使用 |
| 方法 | `string version(Int32 stackId)` | 执行 version(stackId)，行为详见源实现。 |
| 方法 | `bool any()` | 执行 any()。 |
| 属性 | `get string preferred()` | 获取 preferred 的值。 |

## class `Render`

- **说明**：── render (§12.14; current channel) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 api()` | Preferred render backend enum value (0 = none; §12.21 M: hosts without a GPU report Software instead of failing). |
| 方法 | `Array&lt;string&gt; apiList()` | All available render backend names, in value order. |
| 属性 | `get Int32 shaderModel()` | Shader model code: 0=unknown 50=sm_5_0 60/65/66/67 (§12.14). |
| 属性 | `get bool hasRayTracing()` | 获取 hasRayTracing 的值。 |
| 属性 | `get bool hasMeshShader()` | 获取 hasMeshShader 的值。 |
| 属性 | `get bool hasCompute()` | 获取 hasCompute 的值。 |
| 属性 | `get bool hasHdr()` | 获取 hasHdr 的值。 |
| 属性 | `get Int32 maxTextureSize()` | 获取 maxTextureSize 的值。 |
| 属性 | `get Int32 displays()` | 获取 displays 的值。 |
| 属性 | `get Int32 primaryWidth()` | 获取 primaryWidth 的值。 |
| 属性 | `get Int32 primaryHeight()` | 获取 primaryHeight 的值。 |
| 属性 | `get Int32 refreshHz()` | 获取 refreshHz 的值。 |

## class `ProbeRender`

- **说明**：── render (§12.14; probe channel — raw values) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 api()` | 获取 api 的值。 |
| 方法 | `Array&lt;string&gt; apiList()` | 执行 apiList()。 |
| 属性 | `get Int32 shaderModel()` | 获取 shaderModel 的值。 |
| 属性 | `get bool hasRayTracing()` | 获取 hasRayTracing 的值。 |
| 属性 | `get bool hasMeshShader()` | 获取 hasMeshShader 的值。 |
| 属性 | `get bool hasCompute()` | 获取 hasCompute 的值。 |
| 属性 | `get bool hasHdr()` | 获取 hasHdr 的值。 |
| 属性 | `get Int32 maxTextureSize()` | 获取 maxTextureSize 的值。 |
| 属性 | `get Int32 displays()` | 获取 displays 的值。 |
| 属性 | `get Int32 primaryWidth()` | 获取 primaryWidth 的值。 |
| 属性 | `get Int32 primaryHeight()` | 获取 primaryHeight 的值。 |
| 属性 | `get Int32 refreshHz()` | 获取 refreshHz 的值。 |

## class `Network`

- **说明**：── network (§12.15; current channel) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 netType()` | 0=None 1=Loopback 2=Ethernet 3=WiFi 4=Cellular 5=Unknown. (§12.15 names this "type"; renamed to netType because Object.type is final and cannot be overridden.) |
| 属性 | `get Int32 linkState()` | 0=Down 1=Local 2=Online. |
| 属性 | `get bool isOnline()` | linkState == Online (§12.21 N: L1/L2 must not block offline use). |
| 属性 | `get bool isLocalOnly()` | 获取 isLocalOnly 的值。 |
| 属性 | `get Int32 interfaces()` | 获取 interfaces 的值。 |
| 属性 | `get bool hasProxy()` | 获取 hasProxy 的值。 |
| 属性 | `get string proxyUrl()` | 获取 proxyUrl 的值。 |

## class `ProbeNetwork`

- **说明**：── network (§12.15; probe channel — raw values) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 netType()` | (§12.15 "type" renamed: Object.type is final.) |
| 属性 | `get Int32 linkState()` | 获取 linkState 的值。 |
| 属性 | `get bool isOnline()` | 获取 isOnline 的值。 |
| 属性 | `get bool isLocalOnly()` | 获取 isLocalOnly 的值。 |
| 属性 | `get Int32 interfaces()` | 获取 interfaces 的值。 |
| 属性 | `get bool hasProxy()` | 获取 hasProxy 的值。 |
| 属性 | `get string proxyUrl()` | 获取 proxyUrl 的值。 |

## class `Script`

- **说明**：── script runtimes (§12.16; current channel) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool has(string name)` | Whether the script runtime is present (effective view; name is case-insensitive, e.g. "python"). |
| 方法 | `bool has(string name, string minVersion)` | Whether the runtime is present AND version &gt;= minVersion (empty minVersion = presence only; unknown version never rejects the check, §9.2). |
| 方法 | `string version(string name)` | Detected version ("" when absent). |
| 方法 | `string path(string name)` | Detected install path ("" when absent). |
| 方法 | `Array&lt;string&gt; available()` | Names of all detected script runtimes, in probe table order. |

## class `ProbeScript`

- **说明**：── script runtimes (§12.16; probe channel — raw values) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool has(string name)` | 判断 / 校验是否（has）。 |
| 方法 | `bool has(string name, string minVersion)` | 判断 / 校验是否（has）。 |
| 方法 | `string version(string name)` | 执行 version(name)，行为详见源实现。 |
| 方法 | `string path(string name)` | 执行 path(name)，行为详见源实现。 |
| 方法 | `Array&lt;string&gt; available()` | 判断状态是否（available）。 |

## class `Embedded`

- **说明**：── embedded (§12.17; current channel) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 family()` | MCU family enum value (0 = not embedded, general platform). |
| 属性 | `get string chip()` | 获取 chip 的值。 |
| 属性 | `get string vendor()` | 获取 vendor 的值。 |
| 属性 | `get string coreName()` | 获取 coreName 的值。 |
| 属性 | `get bool bareMetal()` | 获取 bareMetal 的值。 |
| 属性 | `get Int32 rtos()` | RTOS kind enum value (0 = none, §12.17). |
| 属性 | `get string rtosVersion()` | 获取 rtosVersion 的值。 |
| 属性 | `get Int32 flashKB()` | Flash / RAM sizes; 0 = unknown (general platforms report 0). |
| 属性 | `get Int32 ramKB()` | 获取 ramKB 的值。 |
| 属性 | `get Int32 stackFreeKB()` | 获取 stackFreeKB 的值。 |
| 属性 | `get Int32 heapFreeKB()` | 获取 heapFreeKB 的值。 |
| 属性 | `get bool hasFpu()` | 获取 hasFpu 的值。 |
| 属性 | `get bool hasMmu()` | 获取 hasMmu 的值。 |
| 属性 | `get bool hasMpu()` | 获取 hasMpu 的值。 |
| 属性 | `get bool hasDsp()` | 获取 hasDsp 的值。 |
| 属性 | `get Int32 cpuFreqMHz()` | 获取 cpuFreqMHz 的值。 |
| 属性 | `get string toolchain()` | 获取 toolchain 的值。 |
| 方法 | `Array&lt;string&gt; peripherals()` | Names of all embedded peripherals, in probe table order (empty on general-purpose platforms). |
| 方法 | `bool has(string peripheral)` | Whether the peripheral (case-insensitive free text, e.g. "wifi") is present in the effective view. |
| 方法 | `bool isConstrained()` | Resource-constrained judgement (§12.17): flash &lt; 512KB or ram &lt; 256KB or no MMU or bare metal. On general-purpose platforms flash / ram report 0 = unknown, which counts as constrained (unknown resources are treated as limited, §12.21 P). |

## class `ProbeEmbedded`

- **说明**：── embedded (§12.17; probe channel — raw values) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 family()` | 获取 family 的值。 |
| 属性 | `get string chip()` | 获取 chip 的值。 |
| 属性 | `get string vendor()` | 获取 vendor 的值。 |
| 属性 | `get string coreName()` | 获取 coreName 的值。 |
| 属性 | `get bool bareMetal()` | 获取 bareMetal 的值。 |
| 属性 | `get Int32 rtos()` | 获取 rtos 的值。 |
| 属性 | `get string rtosVersion()` | 获取 rtosVersion 的值。 |
| 属性 | `get Int32 flashKB()` | 获取 flashKB 的值。 |
| 属性 | `get Int32 ramKB()` | 获取 ramKB 的值。 |
| 属性 | `get Int32 stackFreeKB()` | 获取 stackFreeKB 的值。 |
| 属性 | `get Int32 heapFreeKB()` | 获取 heapFreeKB 的值。 |
| 属性 | `get bool hasFpu()` | 获取 hasFpu 的值。 |
| 属性 | `get bool hasMmu()` | 获取 hasMmu 的值。 |
| 属性 | `get bool hasMpu()` | 获取 hasMpu 的值。 |
| 属性 | `get bool hasDsp()` | 获取 hasDsp 的值。 |
| 属性 | `get Int32 cpuFreqMHz()` | 获取 cpuFreqMHz 的值。 |
| 属性 | `get string toolchain()` | 获取 toolchain 的值。 |
| 方法 | `Array&lt;string&gt; peripherals()` | 执行 peripherals()。 |
| 方法 | `bool has(string peripheral)` | 判断 / 校验是否（has）。 |
| 方法 | `bool isConstrained()` | 判断状态是否（isConstrained）。 |

## class `DeviceInfo`

- **说明**：── device details (§12.6; P3) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int32 _dev = 0` | 字段 _dev（类型见签名）。 |
| 字段 | `Int32 _index = 0` | 字段 _index（类型见签名）。 |
| 构造 | `_init_(Int32 dev, Int32 index)` | 构造方法，初始化本类型实例。 |
| 属性 | `get string vendor()` | Vendor name ("nvidia"/"amd"/"intel"/"arm"/"qualcomm"/"imagination"; "unknown" when unidentified; "" when the device entry is absent). |
| 属性 | `get string name()` | Device model name ("" when the entry is absent). |
| 属性 | `get Int32 computeCapability()` | GPU shader-model-like capability (0 = unknown / not applicable). |
| 属性 | `get Int64 memoryMB()` | Dedicated memory in MB (0 = unknown). |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `Device`

- **说明**：── device kinds (§12.6; current channel) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 kind()` | Main device kind: the highest priority kind present (gpu &gt; npu &gt; dsp &gt; fpga &gt; cpu). Compare against Environment.Platform.device members. |
| 方法 | `bool has(Int32 dev)` | Whether the device kind is present (effective view: honours --disable / --enable device.&lt;name&gt; overrides). |
| 方法 | `Int32 count(Int32 dev)` | Count of devices of the kind (effective view). |
| 方法 | `DeviceInfo info(Int32 dev)` | Info of the first device of the kind: {vendor, name, computeCapability, memoryMB} (§12.6). |
| 方法 | `DeviceInfo info(Int32 dev, Int32 index)` | Info of the n-th device of the kind (multi-GPU; index from 0). |

## class `ProbeDeviceInfo`

- **说明**：── device details (§12.6; probe channel — raw values) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `Int32 _dev = 0` | 字段 _dev（类型见签名）。 |
| 字段 | `Int32 _index = 0` | 字段 _index（类型见签名）。 |
| 构造 | `_init_(Int32 dev, Int32 index)` | 构造方法，初始化本类型实例。 |
| 属性 | `get string vendor()` | 获取 vendor 的值。 |
| 属性 | `get string name()` | 获取 name 的值。 |
| 属性 | `get Int32 computeCapability()` | 获取 computeCapability 的值。 |
| 属性 | `get Int64 memoryMB()` | 获取 memoryMB 的值。 |
| 方法 | `string toString()` | 转换为 Stringundefined 类型（toString）。 |

## class `ProbeDevice`

- **说明**：── device kinds (§12.6; probe channel — raw values) ──

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 kind()` | 获取 kind 的值。 |
| 方法 | `bool has(Int32 dev)` | 判断 / 校验是否（has）。 |
| 方法 | `Int32 count(Int32 dev)` | 执行 count(dev)，行为详见源实现。 |
| 方法 | `ProbeDeviceInfo info(Int32 dev)` | 执行 info(dev)，行为详见源实现。 |
| 方法 | `ProbeDeviceInfo info(Int32 dev, Int32 index)` | 执行 info(dev, index)，行为详见源实现。 |

## class `current`

- **说明**：Static getters forward to SystemPlatformEnv* system methods; the CVM side probes + classifies once into a lazy singleton (sl_environment), so each access is an O(1) lookup. Old modules without a platform section work too. Enum-typed values return Int32 — compare against the Platform member: if Environment.current.os == Environment.Platform.os.window { ... } isa / device are bit sets — query with isaHas / deviceHas / deviceCount: if Environment.current.isaHas( Environment.Platform.isa.avx2 ) { ... }

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 os()` | ── os ── |
| 属性 | `get string osName()` | 获取 osName 的值。 |
| 属性 | `get Int32 osFamily()` | 0=unknown 1=window 2=unix (OS family shortcut, §12.2). |
| 属性 | `get OSVersionNumber osVersionNumber()` | 获取 osVersionNumber 的值。 |
| 属性 | `get Int32 form()` | ── form ── |
| 属性 | `get Int32 arch()` | ── arch ── |
| 属性 | `get Int32 archBits()` | 32 / 64 / 0=unknown. |
| 属性 | `get Int32 endian()` | 获取 endian 的值。 |
| 属性 | `get string triple()` | 获取 triple 的值。 |
| 属性 | `get Int32 cpuCount()` | ── cpu ── |
| 属性 | `get string cpuVendor()` | 获取 cpuVendor 的值。 |
| 属性 | `get string cpuModel()` | 获取 cpuModel 的值。 |
| 方法 | `bool isaHas(Int32 isa)` | ── isa (bit set; isa param takes an isa member value) ── |
| 方法 | `bool deviceHas(Int32 dev)` | ── device (bit set; dev param takes a device member value) ── |
| 方法 | `Int32 deviceCount(Int32 dev)` | 执行 deviceCount(dev)，行为详见源实现。 |
| 属性 | `get Int32 runtime()` | ── runtime / build ── |
| 属性 | `get string runtimeVersion()` | 获取 runtimeVersion 的值。 |
| 属性 | `get Int32 build()` | 获取 build 的值。 |
| 属性 | `get Int64 totalMemMB()` | ── memory ── |
| 属性 | `get Int64 availMemMB()` | 获取 availMemMB 的值。 |
| 方法 | `bool libExists(string name)` | ── lib (§9.2 dynamic library presence/version query; judgement forms honour --disable / --enable lib.&lt;name&gt; overrides) ── |
| 方法 | `string libVersion(string name)` | Version string of a known lib ("" when the lib is absent or not registered in the C version symbol table — §9.2 conservative policy: only registered libs report a version). |
| 方法 | `bool libHas(string name, string minVersion)` | Whether the lib is present AND version &gt;= minVersion. Empty minVersion = presence only; unknown version does not fail the check (§9.2 no false negative). |
| 方法 | `string libPath(string name)` | Full path of the probed lib ("" when absent or unknown). |
| 属性 | `get Cpu cpu()` | ── six new categories (§12.12-12.17, P2.7b) ── |
| 属性 | `get Ai ai()` | 获取 ai 的值。 |
| 属性 | `get Render render()` | 获取 render 的值。 |
| 属性 | `get Network network()` | 获取 network 的值。 |
| 属性 | `get Script script()` | 获取 script 的值。 |
| 属性 | `get Embedded embedded()` | 获取 embedded 的值。 |
| 属性 | `get Device device()` | ── device (§12.6, P3) ── |

## class `probe`

- **说明**：probe - raw probed values (§8.5.6: probe = raw, current = effective). Mirrors current, but every getter reads the Probe system methods, so the values are never affected by --disable / --enable / --set overrides. Use for diagnostics / reporting ("what is really there"); branch on current ("what the code sees").

| 类型 | 签名 | 说明 |
|------|------|------|
| 属性 | `get Int32 os()` | ── os ── |
| 属性 | `get string osName()` | 获取 osName 的值。 |
| 属性 | `get Int32 osFamily()` | 获取 osFamily 的值。 |
| 属性 | `get ProbeOSVersionNumber osVersionNumber()` | 获取 osVersionNumber 的值。 |
| 属性 | `get Int32 form()` | ── form ── |
| 属性 | `get Int32 arch()` | ── arch ── |
| 属性 | `get Int32 archBits()` | 获取 archBits 的值。 |
| 属性 | `get Int32 endian()` | 获取 endian 的值。 |
| 属性 | `get string triple()` | 获取 triple 的值。 |
| 属性 | `get Int32 cpuCount()` | ── cpu ── |
| 属性 | `get string cpuVendor()` | 获取 cpuVendor 的值。 |
| 属性 | `get string cpuModel()` | 获取 cpuModel 的值。 |
| 方法 | `bool isaHas(Int32 isa)` | ── isa ── |
| 方法 | `bool deviceHas(Int32 dev)` | ── device ── |
| 方法 | `Int32 deviceCount(Int32 dev)` | 执行 deviceCount(dev)，行为详见源实现。 |
| 属性 | `get Int32 runtime()` | ── runtime / build / memory ── |
| 属性 | `get string runtimeVersion()` | 获取 runtimeVersion 的值。 |
| 属性 | `get Int32 build()` | 获取 build 的值。 |
| 属性 | `get Int64 totalMemMB()` | 获取 totalMemMB 的值。 |
| 属性 | `get Int64 availMemMB()` | 获取 availMemMB 的值。 |
| 方法 | `bool libExists(string name)` | ── lib (§9.2; raw probe: never affected by overrides, use for diagnostics / "what is really there") ── |
| 方法 | `string libVersion(string name)` | 执行 libVersion(name)，行为详见源实现。 |
| 方法 | `bool libHas(string name, string minVersion)` | 执行 libHas(name, minVersion)，行为详见源实现。 |
| 方法 | `string libPath(string name)` | 执行 libPath(name)，行为详见源实现。 |
| 属性 | `get ProbeCpu cpu()` | ── six new categories (§12.12-12.17, P2.7b; raw probe view, never affected by --disable / --enable / --set) ── |
| 属性 | `get ProbeAi ai()` | 获取 ai 的值。 |
| 属性 | `get ProbeRender render()` | 获取 render 的值。 |
| 属性 | `get ProbeNetwork network()` | 获取 network 的值。 |
| 属性 | `get ProbeScript script()` | 获取 script 的值。 |
| 属性 | `get ProbeEmbedded embedded()` | 获取 embedded 的值。 |
| 属性 | `get ProbeDevice device()` | ── device (§12.6, P3; raw probe view) ── |

## class `Override`

- **说明**：Override - runtime override query (§8.5.6: three read forms). Class name uses capital Override: "override" is the SL method override keyword, and the lexer is case-sensitive (same naming rule as get/set — no bare keyword identifiers). bool  off = Environment.Override.isDisabled( "device.gpu" ) string src = Environment.Override.source( "cpu.avx2" )  # "" / "jsonc" / "env" / "cli" / "host" string val = Environment.Override.getValue( "memory" )  # SET value, "" when none

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `bool isDisabled(string key)` | Whether the override key is disabled (only DISABLE counts; the key is normalized on the C side, e.g. "Device.GPU" matches). |
| 方法 | `string source(string key)` | Which channel supplied the override for the key. Returns "" when the key has no override (SL has no string? syntax; same convention as custom.getValue). |
| 方法 | `string getValue(string key)` | The SET replacement value of the key ("" when not overridden or the entry is a DISABLE/ENABLE, which carry no value). |

## class `env`

- **说明**：env - process environment variables (§13.2 ③).

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `string getValue(string name)` | Get the value of an environment variable by name. Returns the value string, or an empty string if not found. |
| 方法 | `bool setValue(string name, string value)` | Set an environment variable to the given value. Returns true on success. |
| 方法 | `bool exists(string name)` | Whether an environment variable exists and is non-empty. (C side returns "" for missing entries, so length is the test.) |

## class `custom`

- **说明**：custom - custom condition values (jsonc require.custom, §13.2 ④).

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `string getValue(string key)` | Get a custom value declared in the module's jsonc require.custom section. Returns an empty string when the key is absent. |

## class `sys`

- **说明**：sys - directory / newline / timing (container for the old Environment static members; a namespace cannot hold bare functions).

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `string currentDirectory()` | Get the current working directory path. |
| 方法 | `bool setCurrentDirectory(string path)` | Set the current working directory. Returns true on success. |
| 属性 | `get string newLine()` | The platform newline string ("\n"). |
| 方法 | `Int32 tickCount()` | Monotonic tick count in milliseconds, as a 32-bit integer. Wraps around every ~24.8 days (same semantics as C# Environment.TickCount). Use tickCount64() if you need the full 64-bit value without overflow. |
| 方法 | `Int64 tickCount64()` | Monotonic tick count in milliseconds, as a 64-bit integer. No overflow (same semantics as C# Environment.TickCount64). |
| 方法 | `Int64 nowMillis()` | Unix timestamp in milliseconds since epoch (1970-01-01 UTC). |

## class `legacy`

- **说明**：legacy - P1.6 compatibility shell (§13.13). New code should use Environment.env.getValue / Environment.env.setValue.

| 类型 | 签名 | 说明 |
|------|------|------|
| 方法 | `string getVariable(string name)` | Deprecated: use Environment.env.getValue( name ). |
| 方法 | `bool setVariable(string name, string value)` | Deprecated: use Environment.env.setValue( name, value ). |
