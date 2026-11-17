/* ============================================================================
 * sle_engine.h — SimGameEngine C99 原生库（sl_sim_engine_lib.dll）公共 API
 * ----------------------------------------------------------------------------
 * 消费方：EngineFfi.sl（@DllStaticImport("sl_sim_engine_lib", ...) 单点声明）。
 * 命名前缀 sle_（Sim Engine）；句柄 1 起始，0 = 无效。
 * 分层：
 *   1) 时间周期（单调时钟，贯穿逻辑/渲染/音频/物理的统一时间源）
 *   2) 节点管理（节点注册表：id 分配 / 哈希按名查找 / 活跃标志 / 计数）
 * =========================================================================== */
#ifndef SL_SIM_ENGINE_H
#define SL_SIM_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 符号导出宏（镜像 cvm_audio_lib/vm_sl_audio.h 的 SLA_API）：MSVC 下必须
 * dllexport——VM 预载后按 GetProcAddress("sle_*") 解析符号，无导出表时
 * 绑定全部落 NULL、FFI 走 SL 函数体兜底（2026-11-16 SimFfiTest 实证）。 */
#if defined(_WIN32) && defined(_MSC_VER)
#  define SLE_API __declspec(dllexport)
#else
#  define SLE_API
#endif

/* ── 时间周期 ─────────────────────────────────────────────── */

/* 单调时钟（微秒 / 毫秒）；基准任意（进程内一致） */
SLE_API int64_t sle_time_now_us(void);
SLE_API int64_t sle_time_now_ms(void);

/* 距上次调用 sle_time_mark 的微秒数（首次调用返回 0）；同时推进采样点 */
SLE_API int64_t sle_time_mark(void);

/* ── 定时器（查询式句柄表，容量 SLE_TIMER_MAX）────────────── */

SLE_API int64_t sle_timer_create(void);            /* 返回句柄；0 = 满   */
SLE_API int32_t sle_timer_start(int64_t h);        /* 清零并开始计时     */
SLE_API int64_t sle_timer_elapsed_us(int64_t h);   /* 未启动返回 -1      */
SLE_API int32_t sle_timer_reset(int64_t h);        /* 清零累计           */
SLE_API int32_t sle_timer_destroy(int64_t h);

/* ── 节点管理（注册表；id 1 起始；容量 SLE_NODE_MAX）──────── */

SLE_API int32_t sle_node_count(void);
/* 注册节点：返回分配 id；name 为空 / 表满返回 0。name/tag 内部拷贝。 */
SLE_API int64_t sle_node_register(const char* name, const char* tag, int32_t layer);
SLE_API int32_t sle_node_unregister(int64_t id);
/* O(1) 哈希按名查 id；未找到 0 */
SLE_API int64_t sle_node_find_by_name(const char* name);
/* 按 id 访问（name/tag 拷入调用方缓冲，返回字节数；0 = 无效 id） */
SLE_API int32_t sle_node_name(int64_t id, char* buf, int32_t cap);
SLE_API int32_t sle_node_tag(int64_t id, char* buf, int32_t cap);
/* 直接返回内部字符串指针（->utf8 绑定形态，VM 即时拷贝为 SL string；
 * 无效 id 返回 ""——VM utf8 返回值不收 NULL）。指针在注销前有效。 */
SLE_API const char* sle_node_name_ref(int64_t id);
SLE_API const char* sle_node_tag_ref(int64_t id);
SLE_API int32_t sle_node_set_layer(int64_t id, int32_t layer);
SLE_API int32_t sle_node_get_layer(int64_t id);
SLE_API int32_t sle_node_set_active(int64_t id, int32_t active);
SLE_API int32_t sle_node_active(int64_t id);

/* ── Volume 参数栈混合（计算核心；块布局与语义见 sle_engine.c 实现）── */
SLE_API int32_t sle_volume_blend(const float* in, int32_t count, float* out);

/* ── GJK 凸点集相交（计算核心；float3 紧凑块，语义见 sle_engine.c）── */
SLE_API int32_t sle_points_transform(const float* m, const float* src, int32_t count, float* dst);
SLE_API int32_t sle_gjk_intersect(const float* a, int32_t na, const float* b, int32_t nb);
SLE_API int32_t sle_gjk_mtv(const float* a, int32_t na, const float* b, int32_t nb, float* out);

/* ── 正交烘焙投影（P7 烘焙组提交；世界 float3 → NDC pos2+uv2）── */
SLE_API int32_t sle_ortho_bake(const float* center, float viewSize, const float* src, int32_t count, float* dst);

/* ── 形状生成（P9 shape 库；计算核心；形状表与参数布局见 sle_engine.c）──
 * type：0 Cube / 1 Plane / 2 Sprite / 3 Sphere / 4 Cylinder / 5 Cone /
 *       6 Torus / 7 Prism / 8 Pipe / 9 Arch / 10 Stair（与 SL ShapeTypes 常量一致）。
 * params：float 参数块（各形状参数个数见 sle_shape_dims）；整型参数以 float 传入。
 * sle_shape_counts：out 填 [vertCount, triCount]；返回 0 成功 / -1 形状号 / -2 参数。
 * sle_shape_build：dst 布局 [pos 3V | nrm 3V | uv 2V]（float），tris 3T 个
 *   int32；缓冲由调用方按 counts 分配。返回顶点数（>0）/ 同上负错误码。
 * 全部形状中心在原点、Y 轴向上、右手系、从外侧看逆时针（CCW）绕序。 */
SLE_API int32_t sle_shape_counts(int32_t type, const float* params, int32_t paramCount, int32_t* out);
SLE_API int32_t sle_shape_build(int32_t type, const float* params, int32_t paramCount, float* dst, int32_t* tris);

#ifdef __cplusplus
}
#endif
#endif /* SL_SIM_ENGINE_H */
