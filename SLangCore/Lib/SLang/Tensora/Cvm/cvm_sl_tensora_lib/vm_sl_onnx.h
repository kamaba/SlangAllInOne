#ifndef VM_SL_ONNX_H
#define VM_SL_ONNX_H

/* ==========================================================================
 * vm_sl_onnx.h —— Tensora cvm 原生层 ONNX 读取导出声明（sl_onnx.c）
 * --------------------------------------------------------------------------
 * 手写 ONNX（protobuf wire format）最小解析器：读取 ModelProto.graph.
 * initializer 权重张量表，物化为连续 f32 缓冲，向 SL 层暴露裸指针与
 * 批量拷贝出口（Onnx.sl 经 @DllStaticImport 直调）。
 *
 * 句柄语义：slo_open 返回 SloModel*（Int64 位模式承载，0 = 失败）；
 * slo_close 整体释放（名字 / dims / f32 缓冲 / 模型本体）。数据指针
 * 在 close 后失效（SL 侧约定：读毕即关，或先拷出）。
 *
 * 错误约定：slo_* 返回 -1/0/false 时查 slo_last_error / slo_error_string
 * （粘性：每次入口先清零）。
 * ========================================================================== */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(_MSC_VER)
#  define SLO_API __declspec(dllexport)
#else
#  define SLO_API
#endif

/* 打开并解析 ONNX 模型文件（v1：graph.initializer，dtype=FLOAT）。
   返回模型句柄（0 = 失败）。 */
SLO_API int64_t slo_open(const char* path);

/* 关闭模型（释放全部解析产物）。返回 1 成功 / 0 失败。 */
SLO_API int32_t slo_close(int64_t model);

/* initializer（权重张量）数量。失败 -1。 */
SLO_API int32_t slo_count(int64_t model);

/* 第 idx 个 initializer 的名字（模型生命周期内共享，勿释放）。
   失败返回空串。 */
SLO_API const char* slo_name(int64_t model, int32_t idx);

/* 第 idx 个张量的维数（rank）。失败 -1。 */
SLO_API int32_t slo_rank(int64_t model, int32_t idx);

/* 第 idx 个张量第 axis 维的尺寸。失败 -1。 */
SLO_API int32_t slo_dim(int64_t model, int32_t idx, int32_t axis);

/* 第 idx 个张量的元素总数（dims 乘积）。失败 -1。 */
SLO_API int32_t slo_elem_count(int64_t model, int32_t idx);

/* 第 idx 个张量的 ONNX TensorProto.DataType 原值（v1 仅支持 1=FLOAT，
   其他类型 slo_open 即报错）。失败 -1。 */
SLO_API int32_t slo_data_type(int64_t model, int32_t idx);

/* 第 idx 个张量的连续 f32 数据裸指针（SL 侧经 SystemPtr/Memory 系
   原语按元素读取——"上层拿指针读数据"通路）。失败 0。 */
SLO_API int64_t slo_data_ptr(int64_t model, int32_t idx);

/* 把第 idx 个张量的全部元素 memcpy 到 dst（通常为 SL 数组的 pin 指针，
   OQ-1 零逐元素循环构造 Tensor 的快路径）。返回 1 成功 / 0 失败。 */
SLO_API int32_t slo_copy_f32(int64_t model, int32_t idx, float* dst);

/* 最近一次错误码（0 = 无错，粘性）。 */
SLO_API int32_t slo_last_error(void);

/* 错误码转文本；err == 0 时取粘性码。 */
SLO_API const char* slo_error_string(int32_t err);

/* 生成测试用最小 ONNX 模型文件（含 2 个 FLOAT initializer：w0[2,3]
   float_data 路径 + w1[5] raw_data 路径），供 OnnxTest 端到端验证
   （无现成模型文件的环境也能全链测试）。返回 1 成功 / 0 失败。 */
SLO_API int32_t slo_make_test_model(const char* path);

#ifdef __cplusplus
}
#endif

#endif /* VM_SL_ONNX_H */
