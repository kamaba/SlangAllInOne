// SlCppExtraUtil.cpp —— SpecialTest 工程外部 C++ 源示例（COrCplusCode\ 目录）：
// 由工程 jsonc plugins.cplus_clang.sources 引入（Front 读文件内容随 Build
// 请求下发），与全部 @cplus_clang(){} 块体条目同批合并编译进 SLCpp.dll
//（同一 clang++ 命令多 TU 合并链接）。块内前置声明后即可调用其中函数；
// SLCPP_EXPORT 导出函数额外进 SLCpp.dll.slffi 契约（SL 侧 FFI 直调）。
// 链接注意（clang-cl 实测）：块体在生成 TU 的 lambda 内，lambda 体内的
// 块作用域函数声明按 C 链接（裸符号名）引用——外部文件的定义必须显式
// extern "C"（C++ 默认修饰名不会匹配，lld-link 报 undefined symbol）。
#include "slcpp.h"

// 普通外部链接函数（extern "C"——块内前置声明按 C 符号引用）：块体
// trampoline 内前置声明后调用（labelExec 通道）
extern "C" long long sl_cpp_extra_add( long long a, long long b )
{
    return a + b;
}

// 导出函数：进 slffi 契约，SL 侧 @DllImport("SLCpp", ...) 直接调用
SLCPP_EXPORT long long cpp_extra_ffi_mul( long long a, long long b )
{
    return a * b;
}
