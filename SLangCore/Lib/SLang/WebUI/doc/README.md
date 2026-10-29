# WebUI/doc 文档索引

`SLangWebUI` 模块的设计与实现文档集合。

## 设计文档（P0 调研与方案）

| 文档 | 主题 |
|---|---|
| `00-总览与路线图.md` | 目标 / 核心结论 / 范式 / 分阶段计划 / 未决问题 |
| `01-webui开源库调研.md` | webui 架构 / 完整 C API 清单 / MIT 许可 / 构建 |
| `02-集成架构设计.md` | 三层结构 / FFI 静态绑定 / 双层回调桥 / 线程模型 |
| `03-SL层API设计.md` | `SLang.WebUI` / `WebUIWindow` 类与用法 |
| `04-原生C包装层设计.md` | `cvm_webui_lib` 扁平化 / trampoline 池 / 事件转发 |
| `05-工程与构建.md` | `.sp`/`.jsonc`/`vmDlls`/vcxproj / 跨平台 / 版本 |
| `06-示例用例.md` | HelloWorld / 点击返回 / 多窗口 / Kiosk / JS 求值 |
| `07-风险待办与验收.md` | 并发安全 / 版本漂移 / 与 Server·QT·Render 关系 / 验收 |

## 实现文档（P1+ 落地）

| 文档 | 主题 |
|---|---|
| `WebUI.md` | 库说明（API / 快速开始 / 处理函数约定 / 许可），对标 `MysqlClient.md` |

## 代码落点（同模块目录）

- `../WebUI.sl` —— SL 层封装（门面 `SLang.WebUI` + 实例类 `SLang.WebUIWindow`，工厂 `newWindow()`）
- `../WebUI.sp` / `../WebUI.jsonc` —— 模块工程入口与配置
- `../cvm_webui_lib/` —— 原生 C 包装层（`cvm_webui.*` + `webui_wrap.h` + `webui_stub.c` + vendored `webui.*` + vcxproj + `get_webui.ps1` + `README.md`）

## 示例 / 测试落点

- `../../../test/Other/WebUITest/` —— 端到端冒烟示例（已跑通：native 预载 / 窗口句柄 / bindHandle 函数值注册（三形态）/ show / wait 阻塞），命令与输出见 `../cvm_webui_lib/README.md`
