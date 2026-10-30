# AOT.sl

> 源文件：`AOT.sl`

## class `AOT`

- **说明**：SLang 标准库类型 AOT（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 字段 | `private Int32 _optimizeLevel = 1` | AOT（Ahead-Of-Time）预编译属性 用法: @AOT() 或 @AOT( 2, "x64", "static", true, false, false ) 标注在类/成员上 编译中（Compiling）生效: Front flags\|=256 + VM AOT 注册表装配期加载 参数参考其它语言的 AOT 实现： .NET NativeAOT: PublishAot / TrimMode / RID(windows-x64, linux-arm64) GraalVM Native Image: -O / --target / --static / --shared / -g / --initialize-at-build-time / --no-fallback GCC/Clang: -O0..-O3 / -g / -static / -shared / target triple 优化级别: 0=无优化 1=基础优化(默认) 2=激进优化 参考 GraalVM -O、GCC -O0~-O3 |
| 字段 | `private string _target = ""` | 目标平台: 如 "x64" / "arm64" / "win-x64" / "linux-amd64"，空为当前平台 参考 .NET RID、GraalVM --target、GCC target triple |
| 字段 | `private string _linkMode = ""` | 链接模式: ""=可执行文件(默认) / "static"=静态链接 / "shared"=共享库 参考 GraalVM --static / --shared、GCC -static / -shared |
| 字段 | `private bool _isDebugInfo = false` | 是否生成调试信息 参考 GraalVM -g、GCC -g |
| 字段 | `private bool _isTrimming = false` | 是否启用裁剪（移除未使用的代码/元数据） 参考 .NET PublishTrimmed / TrimMode、Mono linker |
| 字段 | `private bool _isInitializeAtBuildTime = false` | 是否在构建期完成初始化（静态数据提前到编译期） 参考 GraalVM --initialize-at-build-time |
| 方法 | `override _init_()` | 无参构造: @AOT() 使用全部默认值 |
| 构造 | `_init_(Int32 optimizeLevel, string target, string linkMode, bool isDebugInfo, bool isTrimming, bool isInitializeAtBuildTime)` | 全参构造: @AOT( optimizeLevel, target, linkMode, isDebugInfo, isTrimming, isInitializeAtBuildTime ) |
| 属性 | `get Int32 optimizeLevel()` | 获取 optimizeLevel 的值。 |
| 属性 | `get string target()` | 获取 target 的值。 |
| 属性 | `get string linkMode()` | 获取 linkMode 的值。 |
| 属性 | `get bool isDebugInfo()` | 获取 isDebugInfo 的值。 |
| 属性 | `get bool isTrimming()` | 获取 isTrimming 的值。 |
| 属性 | `get bool isInitializeAtBuildTime()` | 获取 isInitializeAtBuildTime 的值。 |
