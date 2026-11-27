// SlJsExtraUtil.js —— SpecialTest 工程外部 JS 库示例（JsCode\ 目录）：
// 由工程 jsonc plugins.javascript_quickjs.sources 引入（Front 读文件内容随
// Build 请求下发），构建器部署为 scripts\CsSrc_SlJsExtraUtil.js 并写清单
// _slqjs_libs.txt；运行期 C VM 首次执行该 lib 的块前按清单序求值进对应
// JSContext（每库仅一次），块内代码直接调用其中全局函数。
function slJsExtraBase() { return 20; }

const SL_JS_EXTRA = slJsExtraBase() + 2;

function slJsExtraTotal( x ) { return x + SL_JS_EXTRA; }

function slJsExtraBanner( name ) { return "[" + name + "]"; }
