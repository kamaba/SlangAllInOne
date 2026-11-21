/*
 * sl_mem.c —— Tensora cvm 原生实现跨平台内存辅助部分（合入 sl_tensora_lib.dll）
 * ==========================================================================
 * Mem.sl（Tensora 跨平台内存管理门面）的主机侧原语：C 侧 memcpy。
 * SL 侧数组↔数组 / 块↔块的快速拷贝出口（OQ-1 同思路：一次 C 调用
 * 替代 SL 逐元素循环）。设备侧（H2D/D2H/D2D）由 Mem.sl 分派到 CUDA
 * 部分 slc_*（未来 ROCm/NPU/TPU 同构分派）。
 * ==========================================================================
 */

#include "vm_sl_mem.h"
#include <string.h>

/* 主机内存块拷贝（memcpy 语义，区域重叠行为未定义——同 CUDA API）。
   返回 1 成功 / 0 失败（参数非法）。 */
SLM_API int32_t slm_memcpy(int64_t dst, int64_t src, int64_t bytes)
{
    if (dst == 0 || src == 0 || bytes < 0)
    {
        return 0;
    }
    if (bytes == 0)
    {
        return 1;
    }
    memcpy((void*)(intptr_t)dst, (const void*)(intptr_t)src, (size_t)bytes);
    return 1;
}
