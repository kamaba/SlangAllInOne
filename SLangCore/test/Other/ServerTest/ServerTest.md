# ServerTest Project Guide

- Project Entry File: `ServerTest.sp`
- Project Config File: `ServerTest.jsonc`

SLangServer（HTTP/WS 服务框架）验收用例集：P0 前置探针 + P0 引擎 + P1/P1.5/P2/P3/P4/P4.5
（2026-10-25 自 NetTest / ExpendTest 迁出独立；设计契约见
`Lib/SLang/Server/SERVER_DESIGN.md` §8）。

前置：先导出 SLangServer 模块（非系统库，compile-stdlib 三件套不覆盖）：

```powershell
dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -e ir -p SlangAllInOne\SLangCore\Lib\SLang\Server\Server.sp --format binary+json --no-banner
```

运行（联合测试宿主选择器）：`dotnet run --project SlangAllInOne\Project\CSimpleVMTest\CSimpleVMTest.csproj -- ServerTest`

## Project Entry Conventions

### `_main_`

Primary runtime entry. Normal execution starts here.

### `_test_`

Test entry. Used when test mode is enabled.

### `_before_`

Compile pre-hook entry (Project class). Executed before compilation.

### `_after_`

Compile post-hook entry (Project class). Executed after compilation, before IR export.
