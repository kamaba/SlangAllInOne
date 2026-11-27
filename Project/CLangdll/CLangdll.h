/* CLangdll.h — 外部第三方库 CLangdll 的引入头（cplus_clang 外部引入
 * 约定目录样例）：由 SlangAllInOne\Project\CLangdll\CLangdll.cpp 导出
 * 的 extern "C" 原型子集（标量/字符串族；结构体/回调族原型见源文件）。
 *
 * 就位约定：
 *   本头文件    <plugin>\package\windows\include\（编译命令追加 -I）
 *   导入库      <plugin>\package\windows\lib\CLangdll.lib（链接输入）
 *   运行期 DLL  <plugin>\package\windows\CLangdll.dll（与 SLCpp.dll 同
 *   目录，loader 按 import 表解析）
 * 块内 #include "CLangdll.h" 即可调用。 */
#ifndef CLANGDLL_H
#define CLANGDLL_H

#ifdef __cplusplus
extern "C" {
#endif

/* 0. 基础 */
int simplelanguage_addtest( int a, int b );

/* 1. 标量多宽度混合 */
double sl_mix_all( unsigned char a, short b, unsigned int c,
                   long long d, float e, double f );

/* 算术族 */
long long sl_add( long long a, long long b );
long long sl_mul2( long long x );
long long sl_mul10( long long x );

/* Utf8 字符串族 */
const char* sl_echo( const char* s );
const char* sl_concat( const char* a, const char* b );
long long sl_strlen_utf8( const char* s );

#ifdef __cplusplus
}
#endif

#endif /* CLANGDLL_H */
