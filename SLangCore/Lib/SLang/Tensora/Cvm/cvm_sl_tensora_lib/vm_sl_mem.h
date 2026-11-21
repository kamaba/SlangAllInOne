#ifndef VM_SL_MEM_H
#define VM_SL_MEM_H

/* ==========================================================================
 * vm_sl_mem.h —— Tensora cvm 原生层跨平台内存辅助导出声明（sl_mem.c）
 * --------------------------------------------------------------------------
 * Mem.sl（Tensora 跨平台内存管理门面）的主机侧原语：C 侧 memcpy——
 * SL 侧数组↔数组 / 块↔块快速拷贝的零循环出口（OQ-1 同思路）。
 * 设备侧（H2D/D2H/D2D）走 CUDA 部分 slc_*（Mem.sl 分派）。
 * ========================================================================== */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define SLM_API __declspec(dllexport)
#else
#  define SLM_API
#endif

/* 主机内存块拷贝（memcpy 语义，区域重叠行为未定义——同 CUDA API）。
   返回 1 成功 / 0 失败（参数非法）。 */
SLM_API int32_t slm_memcpy(int64_t dst, int64_t src, int64_t bytes);

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_MEM_H */
