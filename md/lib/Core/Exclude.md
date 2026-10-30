# Exclude.sl

> 源文件：`Exclude.sl`

## class `Exclude`

- **说明**：SLang 标准库类型 Exclude（详见源文件）。

| 类型 | 签名 | 说明 |
|------|------|------|
| 构造 | `_init_()` | 编译前（PreCompile）生效: 识别到符号即跳过该段代码编译（成员整体不进 module.json） 收编旧 @IF/@ELSE/@ENDIF 宏与 CompileBeforeManager static if 条件参数（平台/DEBUG 等常量）由 Front 处理器求值, v1 先落无条件形态 用法: @Exclude() 标注在 class/data/enum/成员变量/成员函数上 |
