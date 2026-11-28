// SlGoExtraUtil.go —— golang 插件外部源码示例（jsonc plugins.golang.sources
// 声明，GoCode/ 目录对位 CsharpCode/JavaCode/COrCplusCode/JsCode/TsCode）。
//
// Go 域语义（2026-11-28）：导出期 Front 读本文件内容随 Build 请求下发，
// 构建器按原文件名写进临时组装目录（与块生成的 Entry_N.go 同目录）——
// Go 按目录整包收录 *.go，声明 package main 即与生成条目同包直调，无需
// import（对照 java 域 SLAtSign 同包合并编译口径；Go 无相对路径 import，
// 跨包依赖须走块首 import 外部模块路径，如 import "github.com/xxx/yyy"）。
//
// 约束：勿声明 main 函数（与 gohost 驱动冲突）；勿与驱动资产撞名
// （main.go/gohost.go/registry.go，构建器拒收）；本文件可自带 import 区
//（Go 逐文件解析 import，与块生成的预置 import 组互不冲突）。
package main

import "strings"

// GoExtraMul —— 简单乘法（块体直调示例）
func GoExtraMul(a int64, b int64) int64 {
	return a * b
}

// GoExtraRepeat —— 字符串重复（本文件自带 import 的使用示例）
func GoExtraRepeat(s string, n int64) string {
	return strings.Repeat(s, int(n))
}
