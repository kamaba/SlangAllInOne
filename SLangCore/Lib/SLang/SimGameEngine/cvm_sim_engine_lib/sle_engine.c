/* ============================================================================
 * sle_engine.c — SimGameEngine C99 原生库实现
 * ----------------------------------------------------------------------------
 * 导出符号由 FFI 静态绑定消费（EngineFfi.sl，dllImports "static" 非空时
 * cvm 加载模块即预载本 dll 并注册绑定表）。
 * 平台：Windows 用 QueryPerformanceCounter；其他平台 clock_gettime
 * (CLOCK_MONOTONIC)。引擎库与 csimple_lang 核心（R3 禁平台代码）不同，
 * 本 dll 是独立原生库（sl_render_lib / sl_audio_lib 同款先例），允许平台层。
 * C99：变量声明置块首、C 风格注释。
 * =========================================================================== */
#include "sle_engine.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ── 平台时钟 ─────────────────────────────────────────────── */
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

static int64_t sle_qpc_freq = 0;

static int64_t sle_time_counter(void)
{
    LARGE_INTEGER c;
    if (sle_qpc_freq == 0)
    {
        LARGE_INTEGER f;
        if (!QueryPerformanceFrequency(&f))
        {
            return 0;
        }
        sle_qpc_freq = (int64_t)f.QuadPart;
    }
    if (!QueryPerformanceCounter(&c))
    {
        return 0;
    }
    return (int64_t)c.QuadPart;
}

static int64_t sle_counter_to_us(int64_t counter)
{
    if (sle_qpc_freq <= 0)
    {
        return 0;
    }
    return counter * (int64_t)1000000 / sle_qpc_freq;
}
#else
#include <time.h>

static int64_t sle_time_counter(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    {
        return 0;
    }
    return (int64_t)ts.tv_sec * (int64_t)1000000000 + (int64_t)ts.tv_nsec;
}

static int64_t sle_counter_to_us(int64_t counter)
{
    return counter / (int64_t)1000; /* ns -> us */
}
#endif

int64_t sle_time_now_us(void)
{
    return sle_counter_to_us(sle_time_counter());
}

int64_t sle_time_now_ms(void)
{
    return sle_time_now_us() / (int64_t)1000;
}

int64_t sle_time_mark(void)
{
    static int64_t s_last_us = 0;
    int64_t now = sle_time_now_us();
    int64_t delta = now - s_last_us;
    if (delta < 0)
    {
        delta = 0;
    }
    s_last_us = now;
    return delta;
}

/* ── 定时器表 ─────────────────────────────────────────────── */
#define SLE_TIMER_MAX 64

typedef struct
{
    int32_t used;
    int32_t running;
    int64_t start_us;
} SleTimer;

static SleTimer s_timers[SLE_TIMER_MAX];

static SleTimer* sle_timer_at(int64_t h)
{
    if (h <= 0 || h > SLE_TIMER_MAX)
    {
        return NULL;
    }
    SleTimer* t = &s_timers[h - 1];
    if (!t->used)
    {
        return NULL;
    }
    return t;
}

int64_t sle_timer_create(void)
{
    int32_t i;
    for (i = 0; i < SLE_TIMER_MAX; ++i)
    {
        if (!s_timers[i].used)
        {
            s_timers[i].used = 1;
            s_timers[i].running = 0;
            s_timers[i].start_us = 0;
            return (int64_t)(i + 1);
        }
    }
    return 0;
}

int32_t sle_timer_start(int64_t h)
{
    SleTimer* t = sle_timer_at(h);
    if (t == NULL)
    {
        return 0;
    }
    t->running = 1;
    t->start_us = sle_time_now_us();
    return 1;
}

int64_t sle_timer_elapsed_us(int64_t h)
{
    SleTimer* t = sle_timer_at(h);
    if (t == NULL || !t->running)
    {
        return -1;
    }
    int64_t now = sle_time_now_us();
    int64_t d = now - t->start_us;
    if (d < 0)
    {
        d = 0;
    }
    return d;
}

int32_t sle_timer_reset(int64_t h)
{
    SleTimer* t = sle_timer_at(h);
    if (t == NULL)
    {
        return 0;
    }
    t->start_us = t->running ? sle_time_now_us() : 0;
    return 1;
}

int32_t sle_timer_destroy(int64_t h)
{
    SleTimer* t = sle_timer_at(h);
    if (t == NULL)
    {
        return 0;
    }
    t->used = 0;
    t->running = 0;
    t->start_us = 0;
    return 1;
}

/* ── 节点注册表（开放寻址哈希，name -> id）────────────────── */
#define SLE_NODE_MAX 4096

typedef struct
{
    int32_t used;
    int32_t active;
    int64_t id;
    int32_t layer;
    char* name;
    char* tag;
} SleNode;

static SleNode s_nodes[SLE_NODE_MAX];      /* id -> entry（id-1 下标） */

static int32_t s_node_count = 0;

/* 哈希表：槽存 id（0 空）；容量 = SLE_NODE_MAX（负载 < 1，规模小可线性探测） */
static int64_t s_name_slots[SLE_NODE_MAX];

static uint32_t sle_str_hash(const char* s)
{
    uint32_t h = 2166136261u; /* FNV-1a */
    while (*s != '\0')
    {
        h ^= (uint8_t)(*s++);
        h *= 16777619u;
    }
    return h;
}

static int32_t sle_registry_id_to_index(int64_t id)
{
    if (id <= 0 || id > SLE_NODE_MAX)
    {
        return -1;
    }
    int32_t idx = (int32_t)(id - 1);
    if (!s_nodes[idx].used)
    {
        return -1;
    }
    return idx;
}

static void sle_name_slot_insert(const char* name, int64_t id)
{
    uint32_t mask = (uint32_t)(SLE_NODE_MAX - 1);
    uint32_t idx = sle_str_hash(name) & mask;
    for (;;)
    {
        if (s_name_slots[idx] == 0)
        {
            s_name_slots[idx] = id;
            return;
        }
        idx = (idx + 1) & mask;
    }
}

static int64_t sle_name_slot_find(const char* name)
{
    uint32_t mask = (uint32_t)(SLE_NODE_MAX - 1);
    uint32_t idx = sle_str_hash(name) & mask;
    for (;;)
    {
        int64_t id = s_name_slots[idx];
        if (id == 0)
        {
            return 0;
        }
        SleNode* n = &s_nodes[id - 1];
        if (n->used && n->name != NULL && strcmp(n->name, name) == 0)
        {
            return id;
        }
        idx = (idx + 1) & mask;
    }
}

static void sle_name_slot_erase(const char* name)
{
    uint32_t mask = (uint32_t)(SLE_NODE_MAX - 1);
    uint32_t idx = sle_str_hash(name) & mask;
    for (;;)
    {
        int64_t id = s_name_slots[idx];
        if (id == 0)
        {
            return;
        }
        SleNode* n = &s_nodes[id - 1];
        if (n->used && n->name != NULL && strcmp(n->name, name) == 0)
        {
            s_name_slots[idx] = 0;
            return;
        }
        idx = (idx + 1) & mask;
    }
}

int32_t sle_node_count(void)
{
    return s_node_count;
}

int64_t sle_node_register(const char* name, const char* tag, int32_t layer)
{
    if (name == NULL || name[0] == '\0' || s_node_count >= SLE_NODE_MAX)
    {
        return 0;
    }
    /* 同名重复注册拒绝（SL 侧 Scene.find 语义保持唯一） */
    if (sle_name_slot_find(name) != 0)
    {
        return 0;
    }
    int32_t i;
    for (i = 0; i < SLE_NODE_MAX; ++i)
    {
        SleNode* n = &s_nodes[i];
        if (!n->used)
        {
            n->used = 1;
            n->active = 1;
            /* id 恒等于数组下标+1（句柄复用语义）：sle_registry_id_to_index、
             * 名字哈希槽（sle_name_slot_* 以 id-1 反查节点）全依赖此不变量。
             * 曾用全局递增 id——注销后槽位复用即错位，表现为按名查找 miss、
             * 重名注册不拒（2026-11-16 SimFfiTest F4c/F4d 实证）。 */
            n->id = (int64_t)(i + 1);
            n->layer = layer;
            n->name = (char*)malloc(strlen(name) + 1);
            if (n->name == NULL)
            {
                return 0;
            }
            strcpy(n->name, name);
            if (tag != NULL)
            {
                n->tag = (char*)malloc(strlen(tag) + 1);
                if (n->tag == NULL)
                {
                    free(n->name);
                    n->name = NULL;
                    return 0;
                }
                strcpy(n->tag, tag);
            }
            else
            {
                n->tag = NULL;
            }
            s_node_count++;
            sle_name_slot_insert(n->name, n->id);
            return n->id;
        }
    }
    return 0;
}

int32_t sle_node_unregister(int64_t id)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0)
    {
        return 0;
    }
    SleNode* n = &s_nodes[idx];
    sle_name_slot_erase(n->name);
    free(n->name);
    free(n->tag);
    n->name = NULL;
    n->tag = NULL;
    n->used = 0;
    n->active = 0;
    s_node_count--;
    return 1;
}

int64_t sle_node_find_by_name(const char* name)
{
    if (name == NULL || name[0] == '\0')
    {
        return 0;
    }
    return sle_name_slot_find(name);
}

int32_t sle_node_name(int64_t id, char* buf, int32_t cap)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0 || buf == NULL || cap <= 0)
    {
        return 0;
    }
    SleNode* n = &s_nodes[idx];
    int32_t len = (int32_t)strlen(n->name);
    if (len >= cap)
    {
        len = cap - 1;
    }
    memcpy(buf, n->name, (size_t)len);
    buf[len] = '\0';
    return len;
}

int32_t sle_node_tag(int64_t id, char* buf, int32_t cap)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0 || buf == NULL || cap <= 0)
    {
        return 0;
    }
    SleNode* n = &s_nodes[idx];
    if (n->tag == NULL)
    {
        if (cap > 0)
        {
            buf[0] = '\0';
        }
        return 0;
    }
    int32_t len = (int32_t)strlen(n->tag);
    if (len >= cap)
    {
        len = cap - 1;
    }
    memcpy(buf, n->tag, (size_t)len);
    buf[len] = '\0';
    return len;
}

const char* sle_node_name_ref(int64_t id)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0)
    {
        return "";
    }
    return s_nodes[idx].name;
}

const char* sle_node_tag_ref(int64_t id)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0 || s_nodes[idx].tag == NULL)
    {
        return "";
    }
    return s_nodes[idx].tag;
}

int32_t sle_node_set_layer(int64_t id, int32_t layer)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0)
    {
        return 0;
    }
    s_nodes[idx].layer = layer;
    return 1;
}

int32_t sle_node_get_layer(int64_t id)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0)
    {
        return -1;
    }
    return s_nodes[idx].layer;
}

int32_t sle_node_set_active(int64_t id, int32_t active)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0)
    {
        return 0;
    }
    s_nodes[idx].active = active ? 1 : 0;
    return 1;
}

int32_t sle_node_active(int64_t id)
{
    int32_t idx = sle_registry_id_to_index(id);
    if (idx < 0)
    {
        return -1;
    }
    return s_nodes[idx].active;
}

/* ── Volume 参数栈混合（计算核心，doc/14 §3；v1.1 扩参）────────
 * 输入块布局（每 Volume 24 个 float，SLE_VOLUME_STRIDE 紧凑排布）：
 *   [0] weight         有效权重 [0,1]（<=0 不贡献）
 *   [1] priority       升序（值大者排后 = 后应用 = 覆盖优先）
 *   [2] isGlobal       0/1（全局优先于局部）
 *   [3] camDist        到相机距离（同键子序近者先；全局填 0）
 *   [4] hasBrightness  [5] brightness
 *   [6] hasContrast    [7] contrast
 *   [8] hasSaturation  [9] saturation
 *   [10] hasVignette   [11] vignette
 *   [12] hasVigSmooth  [13] vigSmooth
 *   [14] hasHueShift   [15] hueShift（角度制）
 *   [16] hasGrain      [17] grain
 *   [18] hasTonemap    [19] tonemap（0/1；枚举不插值，直接覆盖）
 *   [20] hasFilter     [21] filterR [22] filterG [23] filterB
 * 输出块（11 float）：[0] brightness [1] contrast [2] saturation
 *   [3] vignette [4] vigSmooth [5] hueShift [6] grain [7] tonemap
 *   [8..10] filter RGB（enable 由 SL 侧 contributing 决定，不下发）
 * 语义：按（全局优先, priority 升序, camDist 升序, 输入序稳定）排序后，
 * 自中性默认起逐 Volume 对**已配置字段** lerp(cur, v, weight)——
 * 未配置字段保留当前值（掩码语义，doc/14 §3.1）；排序靠后者覆盖优先。
 * 中性值：brightness/contrast/saturation/filter = 1、hueShift/grain/
 * tonemap = 0、vigSmooth = 1、**vignette = 0**（无配置 = 无暗角，
 * v1.1 修正 v1 的 1.0 起点误语义）。
 * 返回：贡献 Volume 数（weight>0）；参数非法返回 0。SL 侧绑定失败走
 * 兜底体返回 -1（VolumeSystem 据此降级 SL 线性混合）。 */
#define SLE_VOLUME_STRIDE 24
#define SLE_VOLUME_MAX 256

static int sle_vol_before(const float* a, const float* b)
{
    int ga = (a[2] > 0.5f) ? 1 : 0;
    int gb = (b[2] > 0.5f) ? 1 : 0;
    if (ga != gb)
    {
        return ga > gb;
    }
    if (a[1] != b[1])
    {
        return a[1] < b[1];
    }
    return a[3] < b[3];
}

static float sle_vol_lerp(float a, float b, float t)
{
    return a + (b - a) * t;
}

SLE_API int32_t sle_volume_blend(const float* in, int32_t count, float* out)
{
    int32_t idx[SLE_VOLUME_MAX];
    int32_t n = count;
    int32_t i;
    int32_t used = 0;
    float br = 1.0f, ct = 1.0f, sa = 1.0f, vi = 0.0f, vs = 1.0f;
    float hu = 0.0f, gr = 0.0f, tm = 0.0f;
    float fr = 1.0f, fg = 1.0f, fb = 1.0f;
    if (in == NULL || out == NULL || count <= 0)
    {
        return 0;
    }
    if (n > SLE_VOLUME_MAX)
    {
        n = SLE_VOLUME_MAX;
    }
    /* 稳定插入排序（相等键保持输入序；比较方向 = new 是否应排在
     * 已排元素之前——写反会得到降序，2026-11-17 SimVolumeTest W4 实证） */
    for (i = 0; i < n; ++i)
    {
        int32_t pos = i;
        int32_t j = i - 1;
        while (j >= 0 && sle_vol_before(in + i * SLE_VOLUME_STRIDE, in + idx[j] * SLE_VOLUME_STRIDE))
        {
            idx[j + 1] = idx[j];
            --j;
        }
        pos = j + 1;
        idx[pos] = i;
    }
    for (i = 0; i < n; ++i)
    {
        const float* v = in + idx[i] * SLE_VOLUME_STRIDE;
        if (v[0] <= 0.0f)
        {
            continue;
        }
        if (v[4] > 0.5f)  { br = sle_vol_lerp(br, v[5], v[0]); }
        if (v[6] > 0.5f)  { ct = sle_vol_lerp(ct, v[7], v[0]); }
        if (v[8] > 0.5f)  { sa = sle_vol_lerp(sa, v[9], v[0]); }
        if (v[10] > 0.5f) { vi = sle_vol_lerp(vi, v[11], v[0]); }
        if (v[12] > 0.5f) { vs = sle_vol_lerp(vs, v[13], v[0]); }
        if (v[14] > 0.5f) { hu = sle_vol_lerp(hu, v[15], v[0]); }
        if (v[16] > 0.5f) { gr = sle_vol_lerp(gr, v[17], v[0]); }
        if (v[18] > 0.5f) { tm = v[19]; }  /* 枚举覆盖不插值 */
        if (v[20] > 0.5f)
        {
            fr = sle_vol_lerp(fr, v[21], v[0]);
            fg = sle_vol_lerp(fg, v[22], v[0]);
            fb = sle_vol_lerp(fb, v[23], v[0]);
        }
        ++used;
    }
    out[0] = br;  out[1] = ct;  out[2] = sa;
    out[3] = vi;  out[4] = vs;  out[5] = hu;
    out[6] = gr;  out[7] = tm;
    out[8] = fr;  out[9] = fg;  out[10] = fb;
    return used;
}

/* ── GJK 凸点集相交（计算核心，doc/11 远期项）────────────────
 * 顶点块布局：float3 紧凑排布（stride 12B）。sle_points_transform 用
 * 行主序 4x4（16 float，m00..m33）对点集做点变换（w=1，含平移）。
 * sle_gjk_intersect：标准 GJK 布尔测试——Minkowski 差支撑函数为点集
 * 扫描（argmax dot），单纯形线/三角/四面体最近点 + 包含判定，迭代上限
 * 32；支撑点重复判死（无进展 → 分离）。返回 1 相交 / 0 分离 / 参数
 * 非法 0。接触法线/穿透量需 EPA（远期），当前布尔形态供事件窄相精化。 */

static void sle_v_sub(const float* a, const float* b, float* o)
{
    o[0] = a[0] - b[0];
    o[1] = a[1] - b[1];
    o[2] = a[2] - b[2];
}

static float sle_v_dot(const float* a, const float* b)
{
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

static void sle_v_cross(const float* a, const float* b, float* o)
{
    o[0] = a[1] * b[2] - a[2] * b[1];
    o[1] = a[2] * b[0] - a[0] * b[2];
    o[2] = a[0] * b[1] - a[1] * b[0];
}

SLE_API int32_t sle_points_transform(const float* m, const float* src, int32_t count, float* dst)
{
    int32_t i;
    if (m == NULL || src == NULL || dst == NULL || count <= 0)
    {
        return 0;
    }
    for (i = 0; i < count; ++i)
    {
        const float* p = src + i * 3;
        float* o = dst + i * 3;
        o[0] = m[0] * p[0] + m[1] * p[1] + m[2] * p[2] + m[3];
        o[1] = m[4] * p[0] + m[5] * p[1] + m[6] * p[2] + m[7];
        o[2] = m[8] * p[0] + m[9] * p[1] + m[10] * p[2] + m[11];
    }
    return count;
}

/* ── 输入状态表（SnakeGame 专用；QT 键盘回调注入，游戏逻辑查询）──────
 * down[256]：当前按住；pressed[256]：本帧按下边沿（down 置位时置 1，
 * sle_input_end_frame 清零）。键码 = Qt::Key 枚举值：字母/数字区（<128，
 * 与 ASCII 同）直接下标；方向键族（0x01000000+）压缩映射到 128+ 槽。
 * 单线程（Qt 事件循环与 VM 重入同线程），无锁。 */
#define SLE_INPUT_SLOTS 256
static unsigned char s_input_down[SLE_INPUT_SLOTS];
static unsigned char s_input_pressed[SLE_INPUT_SLOTS];

static int sle_input_slot(int32_t key)
{
    if (key >= 0 && key < 128)
    {
        return key;
    }
    switch (key)
    {
    case 0x01000000: return 128; /* Escape */
    case 0x01000003: return 132; /* Backspace */
    case 0x01000004: return 133; /* Return/Enter */
    case 0x01000012: return 134; /* Left  (Qt::Key_Left  = 0x01000012) */
    case 0x01000013: return 135; /* Up    (Qt::Key_Up    = 0x01000013) */
    case 0x01000014: return 136; /* Right (Qt::Key_Right = 0x01000014) */
    case 0x01000015: return 137; /* Down  (Qt::Key_Down  = 0x01000015) */
    case 0x01000021: return 138; /* Ctrl  (Qt::Key_Control = 0x01000021) */
    case 0x01000076: return 139; /* F12   (Qt::Key_F12    = 0x01000076) */
    case 0x01000010: return 140; /* Home  (Qt::Key_Home   = 0x01000010) */
    default: return -1;
    }
}

SLE_API int32_t sle_input_set_key(int32_t key, int32_t down)
{
    int slot = sle_input_slot(key);
    int prev;
    if (slot < 0)
    {
        return 0;
    }
    prev = s_input_down[slot];
    s_input_down[slot] = down ? 1 : 0;
    if (down && !prev)
    {
        /* 仅真按下沿置位：QT 键盘自动重复（按住连发 down=1）不去重会把
         * wasPressed 边沿语义破坏成持续真 */
        s_input_pressed[slot] = 1;
    }
    return 1;
}

SLE_API int32_t sle_input_down(int32_t key)
{
    int slot = sle_input_slot(key);
    return slot >= 0 ? s_input_down[slot] : 0;
}

SLE_API int32_t sle_input_pressed(int32_t key)
{
    int slot = sle_input_slot(key);
    return slot >= 0 ? s_input_pressed[slot] : 0;
}

/* ── 鼠标状态表（与键盘同线程无锁；注入方 = QT 宿主桥每帧采样，查询方 =
 * 游戏逻辑）。按钮号直接作槽位（1=左键 2=右键，0..7）；坐标 = 窗口客户
 * 区像素（QT 全局事件过滤器口径）；滚轮累计，wheel_take 读后清零。 */
#define SLE_MOUSE_BUTTONS 8
static unsigned char s_mouse_down[SLE_MOUSE_BUTTONS];
static unsigned char s_mouse_pressed[SLE_MOUSE_BUTTONS];
static int32_t s_mouse_x = 0;
static int32_t s_mouse_y = 0;
static int32_t s_mouse_wheel = 0;

SLE_API int32_t sle_input_end_frame(void)
{
    memset(s_input_pressed, 0, sizeof(s_input_pressed));
    memset(s_mouse_pressed, 0, sizeof(s_mouse_pressed));
    return 1;
}

SLE_API int32_t sle_input_set_mouse_button(int32_t button, int32_t down)
{
    int prev;
    if (button < 0 || button >= SLE_MOUSE_BUTTONS)
    {
        return 0;
    }
    prev = s_mouse_down[button];
    s_mouse_down[button] = down ? 1 : 0;
    if (down && !prev)
    {
        s_mouse_pressed[button] = 1;
    }
    return 1;
}

SLE_API int32_t sle_input_set_mouse_pos(int32_t x, int32_t y)
{
    s_mouse_x = x;
    s_mouse_y = y;
    return 1;
}

SLE_API int32_t sle_input_set_mouse_wheel(int32_t delta)
{
    s_mouse_wheel += delta;
    return 1;
}

SLE_API int32_t sle_input_mouse_button(int32_t button)
{
    if (button < 0 || button >= SLE_MOUSE_BUTTONS)
    {
        return 0;
    }
    return s_mouse_down[button];
}

SLE_API int32_t sle_input_mouse_pressed(int32_t button)
{
    if (button < 0 || button >= SLE_MOUSE_BUTTONS)
    {
        return 0;
    }
    return s_mouse_pressed[button];
}

SLE_API int32_t sle_input_mouse_x(void)
{
    return s_mouse_x;
}

SLE_API int32_t sle_input_mouse_y(void)
{
    return s_mouse_y;
}

SLE_API int32_t sle_input_mouse_wheel_take(void)
{
    int32_t v = s_mouse_wheel;
    s_mouse_wheel = 0;
    return v;
}

static void sle_support_diff(const float* A, int32_t na, const float* B, int32_t nb, const float* d, float* w)
{
    /* Minkowski 差支撑：argmax_A dot(p,d) - argmax_B dot(p,-d)
     * （B 侧必须沿 -d 扫描取 max——漏取反得 min_B，w 全错且分离用例
     * 恰好碰对掩蔽，2026-11-17 独立 C 自测实证） */
    int32_t i;
    float best;
    float nd[3];
    const float* pa = A;
    const float* pb = B;
    nd[0] = -d[0];
    nd[1] = -d[1];
    nd[2] = -d[2];
    best = -1e30f;
    for (i = 0; i < na; ++i)
    {
        float v = sle_v_dot(A + i * 3, d);
        if (v > best)
        {
            best = v;
            pa = A + i * 3;
        }
    }
    best = -1e30f;
    for (i = 0; i < nb; ++i)
    {
        float v = sle_v_dot(B + i * 3, nd);
        if (v > best)
        {
            best = v;
            pb = B + i * 3;
        }
    }
    w[0] = pa[0] - pb[0];
    w[1] = pa[1] - pb[1];
    w[2] = pa[2] - pb[2];
}

static void sle_seg_closest(const float* a, const float* b, float* out)
{
    /* 线段 ab 上距原点最近点 */
    float ab[3];
    float denom;
    float t;
    sle_v_sub(b, a, ab);
    denom = sle_v_dot(ab, ab);
    if (denom < 1e-12f)
    {
        out[0] = a[0];
        out[1] = a[1];
        out[2] = a[2];
        return;
    }
    t = -sle_v_dot(a, ab) / denom;
    if (t < 0.0f)
    {
        t = 0.0f;
    }
    if (t > 1.0f)
    {
        t = 1.0f;
    }
    out[0] = a[0] + ab[0] * t;
    out[1] = a[1] + ab[1] * t;
    out[2] = a[2] + ab[2] * t;
}

/* Ericson 5.1.5：三角形 ABC 上距原点最近点 */
static void sle_tri_closest(const float* a, const float* b, const float* c, float* out)
{
    float ab[3];
    float ac[3];
    float d1;
    float d2;
    float d3;
    float d4;
    float d5;
    float d6;
    float vc;
    float vb;
    float va;
    float denom;
    float v;
    float w;
    sle_v_sub(b, a, ab);
    sle_v_sub(c, a, ac);
    /* p = 原点：ap = -a */
    d1 = ab[0] * (-a[0]) + ab[1] * (-a[1]) + ab[2] * (-a[2]);
    d2 = ac[0] * (-a[0]) + ac[1] * (-a[1]) + ac[2] * (-a[2]);
    if (d1 <= 0.0f && d2 <= 0.0f)
    {
        out[0] = a[0];
        out[1] = a[1];
        out[2] = a[2];
        return;
    }
    d3 = ab[0] * (-b[0]) + ab[1] * (-b[1]) + ab[2] * (-b[2]);
    d4 = ac[0] * (-b[0]) + ac[1] * (-b[1]) + ac[2] * (-b[2]);
    if (d3 >= 0.0f && d4 <= d3)
    {
        out[0] = b[0];
        out[1] = b[1];
        out[2] = b[2];
        return;
    }
    vc = d1 * d4 - d3 * d2;
    if (vc <= 0.0f && d1 >= 0.0f && d3 <= 0.0f)
    {
        v = d1 / (d1 - d3);
        out[0] = a[0] + ab[0] * v;
        out[1] = a[1] + ab[1] * v;
        out[2] = a[2] + ab[2] * v;
        return;
    }
    d5 = ab[0] * (-c[0]) + ab[1] * (-c[1]) + ab[2] * (-c[2]);
    d6 = ac[0] * (-c[0]) + ac[1] * (-c[1]) + ac[2] * (-c[2]);
    if (d6 >= 0.0f && d5 <= d6)
    {
        out[0] = c[0];
        out[1] = c[1];
        out[2] = c[2];
        return;
    }
    vb = d5 * d2 - d1 * d6;
    if (vb <= 0.0f && d2 >= 0.0f && d6 <= 0.0f)
    {
        w = d2 / (d2 - d6);
        out[0] = a[0] + ac[0] * w;
        out[1] = a[1] + ac[1] * w;
        out[2] = a[2] + ac[2] * w;
        return;
    }
    va = d3 * d6 - d5 * d4;
    if (va <= 0.0f && (d4 - d3) >= 0.0f && (d5 - d6) >= 0.0f)
    {
        float bc[3];
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
        sle_v_sub(c, b, bc);
        out[0] = b[0] + bc[0] * w;
        out[1] = b[1] + bc[1] * w;
        out[2] = b[2] + bc[2] * w;
        return;
    }
    denom = va + vb + vc;
    if (denom < 1e-12f && denom > -1e-12f)
    {
        denom = 1.0f;
    }
    v = vb / denom;
    w = vc / denom;
    out[0] = a[0] + ab[0] * v + ac[0] * w;
    out[1] = a[1] + ab[1] * v + ac[1] * w;
    out[2] = a[2] + ab[2] * v + ac[2] * w;
}

typedef struct
{
    float p[4][3];
    int n;
} SleSmp;

/* 原点是否在四面体内（点在面上算在内）；否则缩减到距原点最近面 */
static int sle_tetra_reduce(SleSmp* s)
{
    int bestFace = 0;
    float bestLen = 1e30f;
    float bestCp[3];
    int face;
    int f;
    for (face = 0; face < 4; ++face)
    {
        /* face = 除顶点 face 外的三顶点 */
        float a[3];
        float b[3];
        float c[3];
        float n[3];
        float ab[3];
        float ac[3];
        float cp[3];
        float dist;
        int k = 0;
        int inside = 1;
        for (f = 0; f < 4 && inside; ++f)
        {
            if (f == face)
            {
                continue;
            }
            if (k == 0) { a[0] = s->p[f][0]; a[1] = s->p[f][1]; a[2] = s->p[f][2]; ++k; }
            else if (k == 1) { b[0] = s->p[f][0]; b[1] = s->p[f][1]; b[2] = s->p[f][2]; ++k; }
            else { c[0] = s->p[f][0]; c[1] = s->p[f][1]; c[2] = s->p[f][2]; ++k; }
        }
        sle_v_sub(b, a, ab);
        sle_v_sub(c, a, ac);
        sle_v_cross(ab, ac, n);
        /* 原点与被剔除顶点同侧才算该面「外侧可达」——检查 origin 与
         * s->p[face] 相对面平面的符号一致性：不一致 = 原点在四面体外
         * 该面一侧，该面即候选缩减面 */
        {
            float vo[3];
            float vp[3];
            float so;
            float sv;
            vo[0] = -a[0];
            vo[1] = -a[1];
            vo[2] = -a[2];
            vp[0] = s->p[face][0] - a[0];
            vp[1] = s->p[face][1] - a[1];
            vp[2] = s->p[face][2] - a[2];
            so = sle_v_dot(n, vo);
            sv = sle_v_dot(n, vp);
            /* 原点与对面顶点在异侧 → 原点在该面之外 */
            if ((so > 0.0f && sv < 0.0f) || (so < 0.0f && sv > 0.0f))
            {
                inside = 0;
            }
        }
        if (inside)
        {
            /* 原点在所有面内侧 → 包含 */
            return 1;
        }
        sle_tri_closest(a, b, c, cp);
        dist = sle_v_dot(cp, cp);
        if (dist < bestLen)
        {
            bestLen = dist;
            bestFace = face;
            bestCp[0] = cp[0];
            bestCp[1] = cp[1];
            bestCp[2] = cp[2];
        }
    }
    /* 缩减到最近面三顶点；新方向 = -最近点 */
    {
        int k = 0;
        for (f = 0; f < 4; ++f)
        {
            if (f == bestFace)
            {
                continue;
            }
            s->p[k][0] = s->p[f][0];
            s->p[k][1] = s->p[f][1];
            s->p[k][2] = s->p[f][2];
            ++k;
        }
        s->n = 3;
    }
    return 0;
}

static int sle_smp_has(const SleSmp* s, const float* w)
{
    int i;
    for (i = 0; i < s->n; ++i)
    {
        float dx = s->p[i][0] - w[0];
        float dy = s->p[i][1] - w[1];
        float dz = s->p[i][2] - w[2];
        if (dx < 1e-9f && dx > -1e-9f && dy < 1e-9f && dy > -1e-9f && dz < 1e-9f && dz > -1e-9f)
        {
            return 1;
        }
    }
    return 0;
}

SLE_API int32_t sle_gjk_intersect(const float* A, int32_t na, const float* B, int32_t nb)
{
    SleSmp s;
    float d[3];
    float w[3];
    float cp[3];
    int32_t iter;
    s.n = 0;
    if (A == NULL || B == NULL || na <= 0 || nb <= 0)
    {
        return 0;
    }
    d[0] = 1.0f;
    d[1] = 0.0f;
    d[2] = 0.0f;
    for (iter = 0; iter < 32; ++iter)
    {
        float vw;
        float len2;
        sle_support_diff(A, na, B, nb, d, w);
        vw = sle_v_dot(d, w);
        if (vw < 0.0f)
        {
            /* 支撑点未越过原点 → Minkowski 差不含原点 → 分离 */
            return 0;
        }
        if (sle_smp_has(&s, w) && s.n >= 3)
        {
            /* 支撑点无进展 → 分离 */
            return 0;
        }
        s.p[s.n][0] = w[0];
        s.p[s.n][1] = w[1];
        s.p[s.n][2] = w[2];
        s.n = s.n + 1;
        if (s.n == 4)
        {
            int inside = sle_tetra_reduce(&s);
            if (inside)
            {
                return 1;
            }
        }
        /* 新搜索方向 = 原点到当前单纯形最近点的反向 */
        if (s.n == 1)
        {
            cp[0] = s.p[0][0];
            cp[1] = s.p[0][1];
            cp[2] = s.p[0][2];
        }
        else if (s.n == 2)
        {
            sle_seg_closest(s.p[1], s.p[0], cp);
        }
        else
        {
            sle_tri_closest(s.p[2], s.p[1], s.p[0], cp);
        }
        len2 = sle_v_dot(cp, cp);
        if (len2 < 1e-14f)
        {
            /* 最近点即原点 → 相交 */
            return 1;
        }
        d[0] = -cp[0];
        d[1] = -cp[1];
        d[2] = -cp[2];
    }
    /* 迭代上限：保守判分离（布尔测试误差可接受） */
    return 0;
}

/* ── 透视相机投影（doc/13 §2.1 透视相机专项；计算核心）────────
 * camPtr 9 float：[eyeX,eyeY,eyeZ, yawRad,pitchRad, tanHalfFovY, aspect,
 * zNear, zFar]。朝向约定（与 sky 正交公式同族）：fwd = (sinYaw*cosPitch,
 * sinPitch, -cosYaw*cosPitch)（yaw=0 → 朝 -Z），right = (cosYaw,0,sinYaw)，
 * up = cross(right, fwd)。
 * src 世界 float3 × count；dst 每点 8 float：
 *   [ndcX, ndcY, depth01, visible, viewZ, projX, projY, 0]
 *   ndc = (vx/(aspect*tanHalf), vy/tanHalf) / viewZ（透视除）；
 *   depth01 = (viewZ - near) / (far - near)（线性，painter 用）；
 *   visible = viewZ ∈ [near, far]；projX/Y = 1/(aspect*tanHalf), 1/tanHalf
 *   （SL 侧直通组 scale 换算用：ndcSize = worldSize * proj / viewZ）。
 * 返回可见点数（-1 = 参数非法）。 */
static void sle_cam_basis(const float* cam, float* eye, float* fwd, float* right, float* up)
{
    float cy = cosf(cam[3]);
    float sy = sinf(cam[3]);
    float cp = cosf(cam[4]);
    float sp = sinf(cam[4]);
    eye[0] = cam[0]; eye[1] = cam[1]; eye[2] = cam[2];
    fwd[0] = sy * cp; fwd[1] = sp; fwd[2] = -cy * cp;
    right[0] = cy; right[1] = 0.0f; right[2] = sy;
    /* up = cross(right, fwd) */
    up[0] = right[1] * fwd[2] - right[2] * fwd[1];
    up[1] = right[2] * fwd[0] - right[0] * fwd[2];
    up[2] = right[0] * fwd[1] - right[1] * fwd[0];
}

SLE_API int32_t sle_camera_project(const float* cam, const float* src, int32_t count, float* dst)
{
    float eye[3];
    float fwd[3];
    float right[3];
    float up[3];
    float tanHalf;
    float aspect;
    float projX;
    float projY;
    float zNear;
    float zFar;
    int32_t i;
    int32_t visCount = 0;
    if (cam == NULL || src == NULL || dst == NULL || count <= 0)
    {
        return -1;
    }
    tanHalf = cam[5];
    aspect = cam[6];
    zNear = cam[7];
    zFar = cam[8];
    projX = 1.0f / (aspect * tanHalf);
    projY = 1.0f / tanHalf;
    sle_cam_basis(cam, eye, fwd, right, up);
    for (i = 0; i < count; ++i)
    {
        const float* p = src + i * 3;
        float* o = dst + i * 8;
        float dx = p[0] - eye[0];
        float dy = p[1] - eye[1];
        float dz = p[2] - eye[2];
        float vx = dx * right[0] + dy * right[1] + dz * right[2];
        float vy = dx * up[0] + dy * up[1] + dz * up[2];
        float vz = dx * fwd[0] + dy * fwd[1] + dz * fwd[2];
        float inv;
        o[4] = vz;
        o[5] = projX;
        o[6] = projY;
        o[7] = 0.0f;
        if (vz < zNear || vz > zFar || vz <= 0.0f)
        {
            o[0] = 0.0f; o[1] = 0.0f; o[2] = 1.0f; o[3] = 0.0f;
            continue;
        }
        inv = 1.0f / vz;
        o[0] = vx * projX * inv;
        o[1] = vy * projY * inv;
        o[2] = (vz - zNear) / (zFar - zNear);
        o[3] = 1.0f;
        ++visCount;
    }
    return visCount;
}

/* ── 带镜头 yaw/pitch 的正交烘焙投影（Alt+拖拽旋转镜头）────────
 * cam 块 9 float：[eyeX,eyeY,eyeZ, yawRad,pitchRad, viewSize, aspect,
 *   pad0, pad1]。世界点先投到相机 right/up/fwd 基（复用 sle_cam_basis），
 * 再正交投影 ndc=(vx/(aspect*viewSize), vy/viewSize)，无透视除。
 * dst 每点 4 float [ndcX,ndcY,u,v]（u/v 恒 0），与 sle_ortho_bake 同布局
 * —— 直接喂 RenderPipeline.uploadMesh（pos2+uv2 stride 16B）。
 * 返回处理点数（参数非法 -1）。 */
SLE_API int32_t sle_ortho_bake_view(const float* cam, const float* src, int32_t count, float* dst)
{
    float eye[3];
    float fwd[3];
    float right[3];
    float up[3];
    float viewSize;
    float aspect;
    int32_t i;
    if (cam == NULL || src == NULL || dst == NULL || count <= 0)
    {
        return -1;
    }
    viewSize = cam[5];
    aspect = cam[6];
    if (viewSize <= 0.0f || aspect <= 0.0f)
    {
        return -1;
    }
    sle_cam_basis(cam, eye, fwd, right, up);
    for (i = 0; i < count; ++i)
    {
        const float* p = src + i * 3;
        float* o = dst + i * 4;
        float dx = p[0] - eye[0];
        float dy = p[1] - eye[1];
        float dz = p[2] - eye[2];
        float vx = dx * right[0] + dy * right[1] + dz * right[2];
        float vy = dx * up[0] + dy * up[1] + dz * up[2];
        o[0] = vx / (aspect * viewSize);
        o[1] = vy / viewSize;
        o[2] = 0.0f; /* u */
        o[3] = 0.0f; /* v */
    }
    return count;
}

/* ── GJK/MTV 接触法线与穿透深度（26 方向采样，doc/11）────────
 * 前置：调用方先 sle_gjk_intersect 确认相交（本函数不做布尔判定，
 * 返回 0 = 采样全负 → 实为未相交）。对 26 个单位方向 u（6 轴 + 12 棱
 * + 8 角）各求 Minkowski 差支撑投影 proj(u) = dot(w_sup(u), u)——
 * 沿 u 平移 A 该量即分离；取最小者 = MTV（轴对齐形状精确，旋转形状
 * 保守近似，误差随方向密度下降）。out = [nx,ny,nz,depth]：normal =
 * B→A（把 A 沿 normal 平移 depth 分离），与 ContactInfo.normal 的
 * 「other→self」约定一致。EPA 精确法线远期。 */
static const float SLE_MTV_DIRS[26][3] = {
    { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 },
    { 0.70710678f, 0.70710678f, 0 }, { -0.70710678f, 0.70710678f, 0 },
    { 0.70710678f, -0.70710678f, 0 }, { -0.70710678f, -0.70710678f, 0 },
    { 0.70710678f, 0, 0.70710678f }, { -0.70710678f, 0, 0.70710678f },
    { 0.70710678f, 0, -0.70710678f }, { -0.70710678f, 0, -0.70710678f },
    { 0, 0.70710678f, 0.70710678f }, { 0, -0.70710678f, 0.70710678f },
    { 0, 0.70710678f, -0.70710678f }, { 0, -0.70710678f, -0.70710678f },
    { 0.57735027f, 0.57735027f, 0.57735027f }, { -0.57735027f, 0.57735027f, 0.57735027f },
    { 0.57735027f, -0.57735027f, 0.57735027f }, { -0.57735027f, -0.57735027f, 0.57735027f },
    { 0.57735027f, 0.57735027f, -0.57735027f }, { -0.57735027f, 0.57735027f, -0.57735027f },
    { 0.57735027f, -0.57735027f, -0.57735027f }, { -0.57735027f, -0.57735027f, -0.57735027f }
};

#define SLE_MTV_DIR_COUNT 26

SLE_API int32_t sle_gjk_mtv(const float* A, int32_t na, const float* B, int32_t nb, float* out)
{
    int32_t i;
    float bestProj = 1e30f;
    int32_t bestDir = -1;
    if (A == NULL || B == NULL || na <= 0 || nb <= 0 || out == NULL)
    {
        return 0;
    }
    for (i = 0; i < SLE_MTV_DIR_COUNT; ++i)
    {
        float w[3];
        float proj;
        sle_support_diff(A, na, B, nb, SLE_MTV_DIRS[i], w);
        proj = sle_v_dot(w, SLE_MTV_DIRS[i]);
        if (proj < 0.0f)
        {
            /* 某方向支撑为负 → 原点在该方向之外 → 未相交 */
            return 0;
        }
        if (proj < bestProj)
        {
            bestProj = proj;
            bestDir = i;
        }
    }
    if (bestDir < 0)
    {
        return 0;
    }
    /* normal = -u（B→A），depth = min proj */
    out[0] = -SLE_MTV_DIRS[bestDir][0];
    out[1] = -SLE_MTV_DIRS[bestDir][1];
    out[2] = -SLE_MTV_DIRS[bestDir][2];
    out[3] = bestProj;
    return 1;
}

/* ── 正交烘焙投影（P7 烘焙组提交，doc/05 §3 全量路径）────────
 * src：世界空间 float3 三角形列表（顶点数 count）；dst：MESH_CUSTOM
 * 上传块（pos2+uv2 交错 stride 16B，**NDC 语义**，uv=0）。映射：
 * ndc = (world - center) / viewSize（与 RenderSystem 直通组同式）。
 * 返回投影顶点数；参数非法 0。透视投影（MVP + 透视除）随相机专项。 */
SLE_API int32_t sle_ortho_bake(const float* center, float viewSize, const float* src, int32_t count, float* dst)
{
    int32_t i;
    float inv;
    if (center == NULL || src == NULL || dst == NULL || count <= 0 || viewSize <= 0.0f)
    {
        return 0;
    }
    inv = 1.0f / viewSize;
    for (i = 0; i < count; ++i)
    {
        const float* p = src + i * 3;
        float* o = dst + i * 4;
        o[0] = (p[0] - center[0]) * inv;
        o[1] = (p[1] - center[1]) * inv;
        o[2] = 0.0f; /* u */
        o[3] = 0.0f; /* v */
    }
    return count;
}

/* ============================================================================
 * ── 形状生成（P9 shape 库，参考 Unity ProBuilder ShapeGenerator）────────
 * ----------------------------------------------------------------------------
 * 形状表（type / 参数 float 块布局 / 语义）——全部中心在原点、Y 轴向上、
 * 右手系、从外侧看逆时针（CCW）绕序；整型参数以 float 传入：
 *   0  Cube     sx,sy,sz                              盒（6 面 24 顶点）
 *   1  Plane    width,height,cols,rows                XZ 平面网格，法线 +Y
 *   2  Sprite   width,height                          XY 单面片，法线 +Z
 *   3  Sphere   radius,segU,segV                      经纬球（segU>=3,segV>=2）
 *   4  Cylinder radius,height,segments,heightSegments 圆柱（含双端盖）
 *   5  Cone     radius,height,segments                圆锥（含底盖）
 *   6  Torus    radius,tube,segU,segV                 圆环（主圈绕 +Y）
 *   7  Prism    sx,sy,sz                              三棱柱（XY 三角截面沿 Z 拉伸）
 *   8  Pipe     radius,height,thickness,segments      空心管（内外壁+双环端盖）
 *   9  Arch     angleDeg,radius,width,thickness,segments 拱带（XY 竖直弧带，宽 = Z 向）
 *  10  Stair    steps,width,stepHeight,depth          直梯（沿 +Z 上升，整梯居中）
 *  11  Door     sx,sy,sz,lintel,legWidth              门框（ProBuilder Door：左立柱
 *                                                + 右立柱 + 顶梁三盒组装，lintel
 *                                                顶梁高、legWidth 立柱宽、中间门洞）
 * 输出布局：dst = [pos 3V | nrm 3V | uv 2V]（float 连续块），tris = 3T int32。
 * 两段式调用：先 sle_shape_counts 拿 V/T 分配缓冲，再 sle_shape_build 填充。
 * =========================================================================== */

#define SLE_SHAPE_CUBE     0
#define SLE_SHAPE_PLANE    1
#define SLE_SHAPE_SPRITE   2
#define SLE_SHAPE_SPHERE   3
#define SLE_SHAPE_CYLINDER 4
#define SLE_SHAPE_CONE     5
#define SLE_SHAPE_TORUS    6
#define SLE_SHAPE_PRISM    7
#define SLE_SHAPE_PIPE     8
#define SLE_SHAPE_ARCH     9
#define SLE_SHAPE_STAIR    10
#define SLE_SHAPE_DOOR     11

#define SLE_SHAPE_TYPE_MAX 11

/* 顶点写入游标（build 一次性填充用） */
typedef struct
{
    float* pos;
    float* nrm;
    float* uv;
    int32_t* tri;
    int32_t v;
    int32_t t;
} SleW;

static void sle_w_vert(SleW* w, float x, float y, float z,
                       float nx, float ny, float nz, float u, float vv)
{
    float* p = w->pos + w->v * 3;
    float* n = w->nrm + w->v * 3;
    float* t = w->uv + w->v * 2;
    p[0] = x; p[1] = y; p[2] = z;
    n[0] = nx; n[1] = ny; n[2] = nz;
    t[0] = u; t[1] = vv;
    w->v = w->v + 1;
}

static void sle_w_tri(SleW* w, int32_t a, int32_t b, int32_t c)
{
    int32_t* t = w->tri + w->t * 3;
    t[0] = a; t[1] = b; t[2] = c;
    w->t = w->t + 1;
}

/* 四边形：4 顶点角序 a,b,c,d（从法线一侧看逆时针），UV (0,0)(1,0)(1,1)(0,1)，
 * 三角形 (a,b,c) + (a,c,d)。 */
static void sle_w_quad(SleW* w, const float* a, const float* b,
                       const float* c, const float* d, const float* n)
{
    int32_t base = w->v;
    sle_w_vert(w, a[0], a[1], a[2], n[0], n[1], n[2], 0.0f, 0.0f);
    sle_w_vert(w, b[0], b[1], b[2], n[0], n[1], n[2], 1.0f, 0.0f);
    sle_w_vert(w, c[0], c[1], c[2], n[0], n[1], n[2], 1.0f, 1.0f);
    sle_w_vert(w, d[0], d[1], d[2], n[0], n[1], n[2], 0.0f, 1.0f);
    sle_w_tri(w, base, base + 1, base + 2);
    sle_w_tri(w, base, base + 2, base + 3);
}

/* 闭合盒 [x0,x1]x[y0,y1]x[z0,z1]：6 面 24 顶点 12 三角形，逐面法线 */
static void sle_box(SleW* w, float x0, float x1, float y0, float y1, float z0, float z1)
{
    float a[3], b[3], c[3], d[3], n[3];

    /* +Z */
    n[0] = 0.0f; n[1] = 0.0f; n[2] = 1.0f;
    a[0] = x0; a[1] = y0; a[2] = z1;
    b[0] = x1; b[1] = y0; b[2] = z1;
    c[0] = x1; c[1] = y1; c[2] = z1;
    d[0] = x0; d[1] = y1; d[2] = z1;
    sle_w_quad(w, a, b, c, d, n);
    /* -Z */
    n[2] = -1.0f;
    a[0] = x1; a[1] = y0; a[2] = z0;
    b[0] = x0; b[1] = y0; b[2] = z0;
    c[0] = x0; c[1] = y1; c[2] = z0;
    d[0] = x1; d[1] = y1; d[2] = z0;
    sle_w_quad(w, a, b, c, d, n);
    /* +X */
    n[0] = 1.0f; n[2] = 0.0f;
    a[0] = x1; a[1] = y0; a[2] = z1;
    b[0] = x1; b[1] = y0; b[2] = z0;
    c[0] = x1; c[1] = y1; c[2] = z0;
    d[0] = x1; d[1] = y1; d[2] = z1;
    sle_w_quad(w, a, b, c, d, n);
    /* -X */
    n[0] = -1.0f;
    a[0] = x0; a[1] = y0; a[2] = z0;
    b[0] = x0; b[1] = y0; b[2] = z1;
    c[0] = x0; c[1] = y1; c[2] = z1;
    d[0] = x0; d[1] = y1; d[2] = z0;
    sle_w_quad(w, a, b, c, d, n);
    /* +Y */
    n[0] = 0.0f; n[1] = 1.0f; n[2] = 0.0f;
    a[0] = x0; a[1] = y1; a[2] = z1;
    b[0] = x1; b[1] = y1; b[2] = z1;
    c[0] = x1; c[1] = y1; c[2] = z0;
    d[0] = x0; d[1] = y1; d[2] = z0;
    sle_w_quad(w, a, b, c, d, n);
    /* -Y */
    n[1] = -1.0f;
    a[0] = x0; a[1] = y0; a[2] = z0;
    b[0] = x1; b[1] = y0; b[2] = z0;
    c[0] = x1; c[1] = y0; c[2] = z1;
    d[0] = x0; d[1] = y0; d[2] = z1;
    sle_w_quad(w, a, b, c, d, n);
}

/* 各形状的 V/T 规模（counts 与 build 共用单一真源） */
static int sle_shape_dims(int32_t type, const float* p, int32_t pc,
                          int32_t* vout, int32_t* tout)
{
    int32_t seg, hseg, segu, segv, cols, rows, steps;
    if (p == NULL || pc < 0)
    {
        return -2;
    }
    switch (type)
    {
    case SLE_SHAPE_CUBE:
        if (pc < 3 || p[0] <= 0.0f || p[1] <= 0.0f || p[2] <= 0.0f) { return -2; }
        *vout = 24; *tout = 12;
        return 0;
    case SLE_SHAPE_PLANE:
        if (pc < 4 || p[0] <= 0.0f || p[1] <= 0.0f) { return -2; }
        cols = (int32_t)p[2]; rows = (int32_t)p[3];
        if (cols < 1) { cols = 1; } if (rows < 1) { rows = 1; }
        *vout = (cols + 1) * (rows + 1); *tout = 2 * cols * rows;
        return 0;
    case SLE_SHAPE_SPRITE:
        if (pc < 2 || p[0] <= 0.0f || p[1] <= 0.0f) { return -2; }
        *vout = 4; *tout = 2;
        return 0;
    case SLE_SHAPE_SPHERE:
        if (pc < 3 || p[0] <= 0.0f) { return -2; }
        segu = (int32_t)p[1]; segv = (int32_t)p[2];
        if (segu < 3) { segu = 3; } if (segv < 2) { segv = 2; }
        *vout = 2 + (segv - 1) * (segu + 1);
        *tout = segu * (2 * segv - 2);
        return 0;
    case SLE_SHAPE_CYLINDER:
        if (pc < 4 || p[0] <= 0.0f || p[1] <= 0.0f) { return -2; }
        seg = (int32_t)p[2]; hseg = (int32_t)p[3];
        if (seg < 3) { seg = 3; } if (hseg < 1) { hseg = 1; }
        *vout = (seg + 1) * (hseg + 1) + 2 * (seg + 2);
        *tout = 2 * seg * hseg + 2 * seg;
        return 0;
    case SLE_SHAPE_CONE:
        if (pc < 3 || p[0] <= 0.0f || p[1] <= 0.0f) { return -2; }
        seg = (int32_t)p[2];
        if (seg < 3) { seg = 3; }
        *vout = seg + 3; *tout = 2 * seg;
        return 0;
    case SLE_SHAPE_TORUS:
        if (pc < 4 || p[0] <= 0.0f || p[1] <= 0.0f) { return -2; }
        segu = (int32_t)p[2]; segv = (int32_t)p[3];
        if (segu < 3) { segu = 3; } if (segv < 3) { segv = 3; }
        *vout = (segu + 1) * (segv + 1);
        *tout = 2 * segu * segv;
        return 0;
    case SLE_SHAPE_PRISM:
        if (pc < 3 || p[0] <= 0.0f || p[1] <= 0.0f || p[2] <= 0.0f) { return -2; }
        *vout = 18; *tout = 8;
        return 0;
    case SLE_SHAPE_PIPE:
        if (pc < 4 || p[0] <= 0.0f || p[1] <= 0.0f || p[2] <= 0.0f || p[2] >= p[0]) { return -2; }
        seg = (int32_t)p[3];
        if (seg < 3) { seg = 3; }
        *vout = 6 * (seg + 1); *tout = 8 * seg;
        return 0;
    case SLE_SHAPE_ARCH:
        if (pc < 5 || p[0] <= 0.0f || p[0] > 360.0f || p[1] <= 0.0f ||
            p[2] <= 0.0f || p[3] <= 0.0f) { return -2; }
        seg = (int32_t)p[4];
        if (seg < 3) { seg = 3; }
        *vout = 4 * (seg + 1);
        *tout = 8 * seg;
        if (p[0] < 359.9f)
        {
            *tout = *tout + 4; /* 两端封口各 2 三角形 */
        }
        return 0;
    case SLE_SHAPE_STAIR:
        if (pc < 4 || p[0] < 1.0f || p[1] <= 0.0f || p[2] <= 0.0f || p[3] <= 0.0f) { return -2; }
        steps = (int32_t)p[0];
        if (steps < 1) { steps = 1; }
        if (steps > 256) { return -2; }
        *vout = 24 * steps; *tout = 12 * steps;
        return 0;
    case SLE_SHAPE_DOOR:
        if (pc < 5 || p[0] <= 0.0f || p[1] <= 0.0f || p[2] <= 0.0f ||
            p[3] <= 0.0f || p[4] <= 0.0f ||
            p[3] >= p[1] || p[4] >= p[0] * 0.5f) { return -2; }
        *vout = 72; *tout = 36; /* 三盒组装：左立柱 + 右立柱 + 顶梁 */
        return 0;
    default:
        return -1;
    }
}

/* ── 各形状 build 实现（dims 校验后填充）──────────────────── */

static void sle_shape_cube(SleW* w, const float* p)
{
    float hx = p[0] * 0.5f, hy = p[1] * 0.5f, hz = p[2] * 0.5f;
    sle_box(w, -hx, hx, -hy, hy, -hz, hz);
}

static void sle_shape_plane(SleW* w, const float* p)
{
    float hw = p[0] * 0.5f, hh = p[1] * 0.5f;
    int32_t cols = (int32_t)p[2], rows = (int32_t)p[3];
    int32_t i, j;
    if (cols < 1) { cols = 1; } if (rows < 1) { rows = 1; }
    for (j = 0; j <= rows; ++j)
    {
        for (i = 0; i <= cols; ++i)
        {
            float x = -hw + (float)i * p[0] / (float)cols;
            float z = hh - (float)j * p[1] / (float)rows;
            sle_w_vert(w, x, 0.0f, z, 0.0f, 1.0f, 0.0f,
                       (float)i / (float)cols, 1.0f - (float)j / (float)rows);
        }
    }
    for (j = 0; j < rows; ++j)
    {
        for (i = 0; i < cols; ++i)
        {
            int32_t v00 = j * (cols + 1) + i;
            int32_t v10 = v00 + 1;
            int32_t v01 = v00 + cols + 1;
            int32_t v11 = v01 + 1;
            sle_w_tri(w, v00, v11, v01);
            sle_w_tri(w, v00, v10, v11);
        }
    }
}

static void sle_shape_sprite(SleW* w, const float* p)
{
    float hw = p[0] * 0.5f, hh = p[1] * 0.5f;
    float a[3], b[3], c[3], d[3], n[3];
    n[0] = 0.0f; n[1] = 0.0f; n[2] = 1.0f;
    a[0] = -hw; a[1] = -hh; a[2] = 0.0f;
    b[0] = hw;  b[1] = -hh; b[2] = 0.0f;
    c[0] = hw;  c[1] = hh;  c[2] = 0.0f;
    d[0] = -hw; d[1] = hh;  d[2] = 0.0f;
    sle_w_quad(w, a, b, c, d, n);
}

/* 经纬球：φ 0(顶)→π(底)，θ 0→2π；顶/底极点各 1 顶点 + 中间环 */
static void sle_shape_sphere(SleW* w, const float* p)
{
    float r = p[0];
    int32_t segu = (int32_t)p[1], segv = (int32_t)p[2];
    const float PI = 3.14159265f;
    int32_t i, j;
    if (segu < 3) { segu = 3; } if (segv < 2) { segv = 2; }
    /* 顶极点 */
    sle_w_vert(w, 0.0f, r, 0.0f, 0.0f, 1.0f, 0.0f, 0.5f, 1.0f);
    /* 环 j=1..segv-1（y 从上到下） */
    for (j = 1; j < segv; ++j)
    {
        float phi = PI * (float)j / (float)segv;
        float cy = (float)cos(phi), sy = (float)sin(phi);
        for (i = 0; i <= segu; ++i)
        {
            float th = 2.0f * PI * (float)i / (float)segu;
            float x = r * sy * (float)cos(th), z = r * sy * (float)sin(th);
            sle_w_vert(w, x, r * cy, z, x / r, cy, z / r,
                       (float)i / (float)segu, 1.0f - (float)j / (float)segv);
        }
    }
    /* 底极点 */
    sle_w_vert(w, 0.0f, -r, 0.0f, 0.0f, -1.0f, 0.0f, 0.5f, 0.0f);
    /* 顶帽（索引 0，逆序绕） */
    for (i = 0; i < segu; ++i)
    {
        sle_w_tri(w, 0, 2 + i, 1 + i);
    }
    /* 侧面：环 j（索引 1+(j-1)*(segu+1)+i 起）与环 j+1 之间 */
    for (j = 1; j < segv - 1; ++j)
    {
        int32_t rowA = 1 + (j - 1) * (segu + 1);
        int32_t rowB = rowA + segu + 1;
        for (i = 0; i < segu; ++i)
        {
            int32_t a00 = rowA + i, a10 = a00 + 1;
            int32_t a01 = rowB + i, a11 = a01 + 1;
            sle_w_tri(w, a00, a10, a11);
            sle_w_tri(w, a00, a11, a01);
        }
    }
    /* 底帽（索引 1 + (segv-2)*(segu+1) 起为最末环，末索引 = 底极点） */
    {
        int32_t last = 1 + (segv - 2) * (segu + 1);
        int32_t pole = last + segu + 1;
        for (i = 0; i < segu; ++i)
        {
            sle_w_tri(w, pole, last + i, last + i + 1);
        }
    }
}

/* 圆柱：侧面环（j=0 顶）+ 顶/底盖环（法线 ±Y） */
static void sle_shape_cylinder(SleW* w, const float* p)
{
    float r = p[0], h = p[1] * 0.5f;
    int32_t seg = (int32_t)p[2], hseg = (int32_t)p[3];
    const float PI = 3.14159265f;
    int32_t i, j;
    if (seg < 3) { seg = 3; } if (hseg < 1) { hseg = 1; }
    /* 侧面环：row j（0=顶 y=+h）基址 = j*(seg+1) */
    for (j = 0; j <= hseg; ++j)
    {
        float y = h - (float)j * p[1] / (float)hseg;
        for (i = 0; i <= seg; ++i)
        {
            float th = 2.0f * PI * (float)i / (float)seg;
            float cx = (float)cos(th), sz = (float)sin(th);
            sle_w_vert(w, r * cx, y, r * sz, cx, 0.0f, sz,
                       (float)i / (float)seg, 1.0f - (float)j / (float)hseg);
        }
    }
    /* 端盖：独立顶盖/底盖环（法线 ±Y）+ 中心顶点（扇形三角化） */
    {
        int32_t sideVerts = (hseg + 1) * (seg + 1);
        int32_t topBase = sideVerts;
        int32_t topCenter = topBase + seg + 1;
        int32_t botBase = topCenter + 1;
        int32_t botCenter = botBase + seg + 1;
        for (i = 0; i <= seg; ++i)
        {
            float th = 2.0f * PI * (float)i / (float)seg;
            float cx = (float)cos(th), sz = (float)sin(th);
            sle_w_vert(w, r * cx, h, r * sz, 0.0f, 1.0f, 0.0f,
                       cx * 0.5f + 0.5f, sz * 0.5f + 0.5f);              /* 顶盖环 */
        }
        sle_w_vert(w, 0.0f, h, 0.0f, 0.0f, 1.0f, 0.0f, 0.5f, 0.5f);     /* 顶盖心 */
        for (i = 0; i <= seg; ++i)
        {
            float th = 2.0f * PI * (float)i / (float)seg;
            float cx = (float)cos(th), sz = (float)sin(th);
            sle_w_vert(w, r * cx, 0.0f - h, r * sz, 0.0f, -1.0f, 0.0f,
                       cx * 0.5f + 0.5f, sz * 0.5f + 0.5f);              /* 底盖环 */
        }
        sle_w_vert(w, 0.0f, 0.0f - h, 0.0f, 0.0f, -1.0f, 0.0f, 0.5f, 0.5f); /* 底盖心 */
        /* 侧面四边形（外向：y 向下行 → (a00,a10,a11)+(a00,a11,a01)） */
        for (j = 0; j < hseg; ++j)
        {
            int32_t rowA = j * (seg + 1);
            int32_t rowB = rowA + seg + 1;
            for (i = 0; i < seg; ++i)
            {
                int32_t a00 = rowA + i, a10 = a00 + 1;
                int32_t a01 = rowB + i, a11 = a01 + 1;
                sle_w_tri(w, a00, a10, a11);
                sle_w_tri(w, a00, a11, a01);
            }
        }
        /* 顶帽（+Y：逆序扇形） */
        for (i = 0; i < seg; ++i)
        {
            sle_w_tri(w, topCenter, topBase + i + 1, topBase + i);
        }
        /* 底帽（-Y：顺序扇形） */
        for (i = 0; i < seg; ++i)
        {
            sle_w_tri(w, botCenter, botBase + i, botBase + i + 1);
        }
    }
}

/* 圆锥：底环 + 顶点 + 底中心；侧斜法线 (h·cosθ, r, h·sinθ)/slant */
static void sle_shape_cone(SleW* w, const float* p)
{
    float r = p[0], h = p[1];
    int32_t seg = (int32_t)p[2];
    const float PI = 3.14159265f;
    float slant;
    int32_t i;
    int32_t apex, center;
    if (seg < 3) { seg = 3; }
    slant = (float)sqrt(r * r + h * h);
    for (i = 0; i <= seg; ++i)
    {
        float th = 2.0f * PI * (float)i / (float)seg;
        float cx = (float)cos(th), sz = (float)sin(th);
        sle_w_vert(w, r * cx, 0.0f - h * 0.5f, r * sz,
                   h * cx / slant, r / slant, h * sz / slant,
                   (float)i / (float)seg, 0.0f);
    }
    apex = w->v;
    sle_w_vert(w, 0.0f, h * 0.5f, 0.0f, 0.0f, 1.0f, 0.0f, 0.5f, 1.0f);
    center = w->v;
    sle_w_vert(w, 0.0f, 0.0f - h * 0.5f, 0.0f, 0.0f, -1.0f, 0.0f, 0.5f, 0.0f);
    /* 侧面（外向：(apex, r[i+1], r[i])） */
    for (i = 0; i < seg; ++i)
    {
        sle_w_tri(w, apex, i + 1, i);
    }
    /* 底帽（-Y：顺序扇形，i=0..seg-1 覆盖全部楔形） */
    for (i = 0; i < seg; ++i)
    {
        sle_w_tri(w, center, i, i + 1);
    }
}

/* 圆环：主圈 θ 绕 +Y（半径 R），管圈 φ；法线 = 管心指向外 */
static void sle_shape_torus(SleW* w, const float* p)
{
    float R = p[0], tube = p[1];
    int32_t segu = (int32_t)p[2], segv = (int32_t)p[3];
    const float PI = 3.14159265f;
    int32_t i, j;
    if (segu < 3) { segu = 3; } if (segv < 3) { segv = 3; }
    for (j = 0; j <= segv; ++j)
    {
        float phi = 2.0f * PI * (float)j / (float)segv;
        float cp = (float)cos(phi), sp = (float)sin(phi);
        for (i = 0; i <= segu; ++i)
        {
            float th = 2.0f * PI * (float)i / (float)segu;
            float ct = (float)cos(th), st = (float)sin(th);
            float rr = R + tube * cp;
            sle_w_vert(w, rr * ct, tube * sp, rr * st,
                       cp * ct, sp, cp * st,
                       (float)i / (float)segu, (float)j / (float)segv);
        }
    }
    for (j = 0; j < segv; ++j)
    {
        for (i = 0; i < segu; ++i)
        {
            int32_t a00 = j * (segu + 1) + i, a10 = a00 + 1;
            int32_t a01 = a00 + segu + 1, a11 = a01 + 1;
            sle_w_tri(w, a00, a11, a10);
            sle_w_tri(w, a00, a01, a11);
        }
    }
}

/* 三棱柱：XY 三角截面（顶点朝上）沿 Z 拉伸；两三角端盖 + 三侧面 */
static void sle_shape_prism(SleW* w, const float* p)
{
    float hx = p[0] * 0.5f, hy = p[1] * 0.5f, hz = p[2] * 0.5f;
    /* 截面三顶点（XY）：T 顶(0,+hy)、BL(-hx,-hy)、BR(+hx,-hy) */
    float T[3], BL[3], BR[3];
    float e[3], n[3];
    T[0] = 0.0f;  T[1] = hy;  T[2] = 0.0f;
    BL[0] = 0.0f - hx; BL[1] = 0.0f - hy; BL[2] = 0.0f;
    BR[0] = hx;  BR[1] = 0.0f - hy; BR[2] = 0.0f;
    e[0] = hx; e[1] = p[1]; e[2] = 0.0f;
    /* 前端盖（+Z）：(BL,BR,T) */
    {
        float nF[3];
        float BLf[3], BRf[3], Tf[3];
        nF[0] = 0.0f; nF[1] = 0.0f; nF[2] = 1.0f;
        BLf[0] = BL[0]; BLf[1] = BL[1]; BLf[2] = hz;
        BRf[0] = BR[0]; BRf[1] = BR[1]; BRf[2] = hz;
        Tf[0] = T[0]; Tf[1] = T[1]; Tf[2] = hz;
        sle_w_tri(w, w->v, w->v + 1, w->v + 2);
        sle_w_vert(w, BLf[0], BLf[1], BLf[2], nF[0], nF[1], nF[2], 0.0f, 0.0f);
        sle_w_vert(w, BRf[0], BRf[1], BRf[2], nF[0], nF[1], nF[2], 1.0f, 0.0f);
        sle_w_vert(w, Tf[0], Tf[1], Tf[2], nF[0], nF[1], nF[2], 0.5f, 1.0f);
    }
    /* 后端盖（-Z）：(BR,BL,T) */
    {
        float nB[3];
        float BLb[3], BRb[3], Tb[3];
        nB[0] = 0.0f; nB[1] = 0.0f; nB[2] = -1.0f;
        BLb[0] = BL[0]; BLb[1] = BL[1]; BLb[2] = 0.0f - hz;
        BRb[0] = BR[0]; BRb[1] = BR[1]; BRb[2] = 0.0f - hz;
        Tb[0] = T[0]; Tb[1] = T[1]; Tb[2] = 0.0f - hz;
        sle_w_tri(w, w->v, w->v + 1, w->v + 2);
        sle_w_vert(w, BRb[0], BRb[1], BRb[2], nB[0], nB[1], nB[2], 1.0f, 0.0f);
        sle_w_vert(w, BLb[0], BLb[1], BLb[2], nB[0], nB[1], nB[2], 0.0f, 0.0f);
        sle_w_vert(w, Tb[0], Tb[1], Tb[2], nB[0], nB[1], nB[2], 0.5f, 1.0f);
    }
    /* 左侧面（BL→T 棱，法线外倾 (-ey,+ex,0)/len） */
    {
        float a[3], b[3], c[3], d[3];
        float len = (float)sqrt(e[0] * e[0] + e[1] * e[1]);
        n[0] = 0.0f - e[1] / len; n[1] = e[0] / len; n[2] = 0.0f;
        a[0] = BL[0]; a[1] = BL[1]; a[2] = hz;
        b[0] = T[0]; b[1] = T[1]; b[2] = hz;
        c[0] = T[0]; c[1] = T[1]; c[2] = 0.0f - hz;
        d[0] = BL[0]; d[1] = BL[1]; d[2] = 0.0f - hz;
        sle_w_quad(w, a, b, c, d, n);
    }
    /* 右侧面（T→BR 棱，外向法线 = (-eR.y, eR.x)/len = (sy,hx)/len） */
    {
        float a[3], b[3], c[3], d[3];
        float len = (float)sqrt(e[0] * e[0] + e[1] * e[1]);
        n[0] = e[1] / len; n[1] = e[0] / len; n[2] = 0.0f;
        a[0] = T[0]; a[1] = T[1]; a[2] = hz;
        b[0] = BR[0]; b[1] = BR[1]; b[2] = hz;
        c[0] = BR[0]; c[1] = BR[1]; c[2] = 0.0f - hz;
        d[0] = T[0]; d[1] = T[1]; d[2] = 0.0f - hz;
        sle_w_quad(w, a, b, c, d, n);
    }
    /* 底面（-Y）：(BL,BL,b/BR,BR) */
    {
        float a[3], b[3], c[3], d[3];
        n[0] = 0.0f; n[1] = -1.0f; n[2] = 0.0f;
        a[0] = BL[0]; a[1] = BL[1]; a[2] = hz;
        b[0] = BL[0]; b[1] = BL[1]; b[2] = 0.0f - hz;
        c[0] = BR[0]; c[1] = BR[1]; c[2] = 0.0f - hz;
        d[0] = BR[0]; d[1] = BR[1]; d[2] = hz;
        sle_w_quad(w, a, b, c, d, n);
    }
}

/* 空心管：外壁/内壁 + 顶/底端盖；布局 OT/OB/IT/IB 四段壁环 + 独立端盖环
 * （每环独立循环推入，保证块状基址与三角形引用一致） */
static void sle_shape_pipe(SleW* w, const float* p)
{
    float ro = p[0], h = p[1] * 0.5f, ri = p[0] - p[2];
    int32_t seg = (int32_t)p[3];
    const float PI = 3.14159265f;
    int32_t i;
    int32_t ot, ob, it, ib, ct, cb;
    if (seg < 3) { seg = 3; }
    if (ri < 0.001f) { ri = 0.001f; }
    ot = 0;
    ob = seg + 1;
    it = 2 * (seg + 1);
    ib = 3 * (seg + 1);
    ct = 4 * (seg + 1);
    cb = 5 * (seg + 1);
    for (i = 0; i <= seg; ++i)
    {
        float th = 2.0f * PI * (float)i / (float)seg;
        float cx = (float)cos(th), sz = (float)sin(th);
        float u = (float)i / (float)seg;
        sle_w_vert(w, ro * cx, h, ro * sz, cx, 0.0f, sz, u, 1.0f);          /* OT */
    }
    for (i = 0; i <= seg; ++i)
    {
        float th = 2.0f * PI * (float)i / (float)seg;
        float cx = (float)cos(th), sz = (float)sin(th);
        sle_w_vert(w, ro * cx, 0.0f - h, ro * sz, cx, 0.0f, sz, (float)i / (float)seg, 0.0f);   /* OB */
    }
    for (i = 0; i <= seg; ++i)
    {
        float th = 2.0f * PI * (float)i / (float)seg;
        float cx = (float)cos(th), sz = (float)sin(th);
        sle_w_vert(w, ri * cx, h, ri * sz, 0.0f - cx, 0.0f, 0.0f - sz, (float)i / (float)seg, 1.0f); /* IT */
    }
    for (i = 0; i <= seg; ++i)
    {
        float th = 2.0f * PI * (float)i / (float)seg;
        float cx = (float)cos(th), sz = (float)sin(th);
        sle_w_vert(w, ri * cx, 0.0f - h, ri * sz, 0.0f - cx, 0.0f, 0.0f - sz, (float)i / (float)seg, 0.0f); /* IB */
    }
    for (i = 0; i <= seg; ++i)
    {
        float th = 2.0f * PI * (float)i / (float)seg;
        float cx = (float)cos(th), sz = (float)sin(th);
        sle_w_vert(w, ro * cx, h, ro * sz, 0.0f, 1.0f, 0.0f, cx * 0.5f + 0.5f, sz * 0.5f + 0.5f);  /* CT */
    }
    for (i = 0; i <= seg; ++i)
    {
        float th = 2.0f * PI * (float)i / (float)seg;
        float cx = (float)cos(th), sz = (float)sin(th);
        sle_w_vert(w, ro * cx, 0.0f - h, ro * sz, 0.0f, -1.0f, 0.0f, cx * 0.5f + 0.5f, sz * 0.5f + 0.5f); /* CB */
    }
    /* 外壁（外向，y 向下行 → (a00,a10,a11)+(a00,a11,a01)）与内壁（反向） */
    for (i = 0; i < seg; ++i)
    {
        sle_w_tri(w, ot + i, ot + i + 1, ob + i + 1);
        sle_w_tri(w, ot + i, ob + i + 1, ob + i);
        sle_w_tri(w, it + i, ib + i + 1, it + i + 1);
        sle_w_tri(w, it + i, ib + i, ib + i + 1);
    }
    /* 顶环端盖（+Y）：环形块 IT↔CT（CT 环带 ±Y 法线；旋转三角形使首索
     * 引锚在 CT 上，绕序与法线检查一致） */
    for (i = 0; i < seg; ++i)
    {
        sle_w_tri(w, ct + i + 1, it + i, it + i + 1);
        sle_w_tri(w, ct + i, it + i, ct + i + 1);
    }
    /* 底环端盖（-Y）：环形块 IB↔CB（CB 环带 -Y 法线，逆序） */
    for (i = 0; i < seg; ++i)
    {
        sle_w_tri(w, cb + i, ib + i + 1, ib + i);
        sle_w_tri(w, cb + i, cb + i + 1, ib + i + 1);
    }
}

/* 拱带（竖直，XY 平面内弧、Z 向宽 width）：四段弧面 + 两端封口 */
static void sle_shape_arch(SleW* w, const float* p)
{
    float ang = p[0], ri = p[1], wdt = p[2] * 0.5f, th = p[3];
    int32_t seg = (int32_t)p[4];
    const float PI = 3.14159265f;
    float ro = ri + th;
    float a0, a1;
    int32_t i;
    int32_t of, ob, inf, inb; /* outer-front/outer-back/inner-front/inner-back 基址 */
    if (seg < 3) { seg = 3; }
    a0 = PI * 0.5f - ang * PI / 360.0f;
    a1 = PI * 0.5f + ang * PI / 360.0f;
    of = 0;
    ob = seg + 1;
    inf = 2 * (seg + 1);
    inb = 3 * (seg + 1);
    /* 每环独立循环推入，保证块状基址与三角形引用一致 */
    for (i = 0; i <= seg; ++i)
    {
        float a = a0 + (a1 - a0) * (float)i / (float)seg;
        float ca = (float)cos(a), sa = (float)sin(a);
        sle_w_vert(w, ro * ca, ro * sa, wdt, ca, sa, 0.0f, (float)i / (float)seg, 1.0f);            /* OF */
    }
    for (i = 0; i <= seg; ++i)
    {
        float a = a0 + (a1 - a0) * (float)i / (float)seg;
        float ca = (float)cos(a), sa = (float)sin(a);
        sle_w_vert(w, ro * ca, ro * sa, 0.0f - wdt, ca, sa, 0.0f, (float)i / (float)seg, 0.0f);     /* OB */
    }
    for (i = 0; i <= seg; ++i)
    {
        float a = a0 + (a1 - a0) * (float)i / (float)seg;
        float ca = (float)cos(a), sa = (float)sin(a);
        sle_w_vert(w, ri * ca, ri * sa, wdt, 0.0f - ca, 0.0f - sa, 0.0f, (float)i / (float)seg, 1.0f); /* IF */
    }
    for (i = 0; i <= seg; ++i)
    {
        float a = a0 + (a1 - a0) * (float)i / (float)seg;
        float ca = (float)cos(a), sa = (float)sin(a);
        sle_w_vert(w, ri * ca, ri * sa, 0.0f - wdt, 0.0f - ca, 0.0f - sa, 0.0f, (float)i / (float)seg, 0.0f); /* IB */
    }
    for (i = 0; i < seg; ++i)
    {
        /* 外壁（外向） */
        sle_w_tri(w, of + i + 1, of + i, ob + i);
        sle_w_tri(w, of + i + 1, ob + i, ob + i + 1);
        /* 内壁（内向） */
        sle_w_tri(w, inf + i, inf + i + 1, inb + i + 1);
        sle_w_tri(w, inf + i, inb + i + 1, inb + i);
        /* 前盖（+Z，从 +Z 看逆序）：(OF[i], IF[i], IF[i+1]) + (OF[i], IF[i+1], OF[i+1])
         * 后盖（-Z，绕序反向） */
        sle_w_tri(w, of + i, inf + i, inf + i + 1);
        sle_w_tri(w, of + i, inf + i + 1, of + i + 1);
        sle_w_tri(w, inf + i, of + i, of + i + 1);
        sle_w_tri(w, inf + i, of + i + 1, inf + i + 1);
    }
    /* 两端封口（角度 < 360）：θ0 面朝 -t 方向 (sinθ0,-cosθ0)，θ1 面朝 -t 反向 */
    if (ang < 359.9f)
    {
        int32_t f0 = of, f1 = of + seg;
        int32_t i0 = inf, i1 = inf + seg;
        int32_t b0 = ob, b1 = ob + seg;
        int32_t nb0 = inb, nb1 = inb + seg;
        /* θ0 端面：(OF0, IF0, IB0, OB0) 绕序 → cross ≈ (sinθ0,-cosθ0,0) */
        sle_w_tri(w, f0, i0, nb0);
        sle_w_tri(w, f0, nb0, b0);
        /* θ1 端面：绕序反转 → cross ≈ (-sinθ1, cosθ1, 0) */
        sle_w_tri(w, f1, nb1, i1);
        sle_w_tri(w, f1, b1, nb1);
    }
}

/* 直梯：steps 级闭合盒沿 +Z 上升（每级高 (i+1)*stepHeight），整体居中 */
static void sle_shape_stair(SleW* w, const float* p)
{
    int32_t steps = (int32_t)p[0];
    float width = p[1], sh = p[2], depth = p[3];
    float totalH = (float)steps * sh;
    float totalD = (float)steps * depth;
    float z0 = 0.0f - totalD * 0.5f;
    float y0 = 0.0f - totalH * 0.5f;
    int32_t i;
    if (steps < 1) { steps = 1; }
    if (steps > 256) { steps = 256; }
    for (i = 0; i < steps; ++i)
    {
        float x0 = 0.0f - width * 0.5f;
        float x1 = width * 0.5f;
        float ty = y0 + (float)(i + 1) * sh;
        float dz0 = z0 + (float)i * depth;
        float dz1 = dz0 + depth;
        sle_box(w, x0, x1, y0, ty, dz0, dz1);
    }
}

/* Door（type 11）：ProBuilder Door 同款门框——左立柱 + 右立柱 + 顶梁三盒
 * 组装，中间为门洞。p = [sx, sy, sz, lintel, legWidth]（全尺寸，中心原点）：
 * lintel = 顶梁高度（0 < lintel < sy），legWidth = 立柱宽（0 < leg < sx/2），
 * 门洞宽 = sx - 2*leg、门洞高 = sy - lintel。 */
static void sle_shape_door(SleW* w, const float* p)
{
    float sx = p[0], sy = p[1], sz = p[2];
    float lintel = p[3], leg = p[4];
    float hx = sx * 0.5f, hy = sy * 0.5f, hz = sz * 0.5f;
    /* 左立柱 */
    sle_box(w, 0.0f - hx, leg - hx, 0.0f - hy, hy, 0.0f - hz, hz);
    /* 右立柱 */
    sle_box(w, hx - leg, hx, 0.0f - hy, hy, 0.0f - hz, hz);
    /* 顶梁（横跨两立柱之间） */
    sle_box(w, leg - hx, hx - leg, hy - lintel, hy, 0.0f - hz, hz);
}

SLE_API int32_t sle_shape_counts(int32_t type, const float* params, int32_t paramCount, int32_t* out)
{
    int32_t v, t, err;
    if (out == NULL)
    {
        return -2;
    }
    v = 0;
    t = 0;
    err = sle_shape_dims(type, params, paramCount, &v, &t);
    if (err != 0)
    {
        return err;
    }
    out[0] = v;
    out[1] = t;
    return 0;
}

SLE_API int32_t sle_shape_build(int32_t type, const float* params, int32_t paramCount, float* dst, int32_t* tris)
{
    SleW w;
    int32_t v, t, err;
    if (dst == NULL || tris == NULL)
    {
        return -3;
    }
    v = 0;
    t = 0;
    err = sle_shape_dims(type, params, paramCount, &v, &t);
    if (err != 0)
    {
        return err;
    }
    w.pos = dst;
    w.nrm = dst + v * 3;
    w.uv = dst + v * 6;
    w.tri = tris;
    w.v = 0;
    w.t = 0;
    switch (type)
    {
    case SLE_SHAPE_CUBE:     sle_shape_cube(&w, params); break;
    case SLE_SHAPE_PLANE:    sle_shape_plane(&w, params); break;
    case SLE_SHAPE_SPRITE:   sle_shape_sprite(&w, params); break;
    case SLE_SHAPE_SPHERE:   sle_shape_sphere(&w, params); break;
    case SLE_SHAPE_CYLINDER: sle_shape_cylinder(&w, params); break;
    case SLE_SHAPE_CONE:     sle_shape_cone(&w, params); break;
    case SLE_SHAPE_TORUS:    sle_shape_torus(&w, params); break;
    case SLE_SHAPE_PRISM:    sle_shape_prism(&w, params); break;
    case SLE_SHAPE_PIPE:     sle_shape_pipe(&w, params); break;
    case SLE_SHAPE_ARCH:     sle_shape_arch(&w, params); break;
    case SLE_SHAPE_STAIR:    sle_shape_stair(&w, params); break;
    case SLE_SHAPE_DOOR:     sle_shape_door(&w, params); break;
    default:
        return -1;
    }
    if (w.v != v || w.t != t)
    {
        return -4; /* 内部计数漂移守卫 */
    }
    return w.v;
}

/* ============================================================================
 * UI 图层叠加（doc/08 §8）—— 引擎层「相机输出 → 图层合成」计算核心。
 * dst/layer 均为 top-down RGBA8（w*h*4），逐像素按 mode 混合：
 *   mode 0 ALPHA     : out = layer*sa + dst*(1-sa), sa = layer.a * alpha
 *   mode 1 ADD       : out.rgb = min(255, dst.rgb + layer.rgb*alpha)
 *   mode 2 MULTIPLY  : out.rgb = dst.rgb * (1 - alpha + alpha*layer.rgb/255)
 * alpha 钳制到 [0,1]。返回处理像素数（参数非法返回 0/-1）。
 * ========================================================================= */
SLE_API int32_t sle_layer_composite(uint8_t* dst, const uint8_t* layer,
    int32_t count, float alpha, int32_t mode)
{
    int32_t i;
    int32_t a;
    if (!dst || !layer || count <= 0) return -1;
    if (alpha < 0.0f) alpha = 0.0f;
    if (alpha > 1.0f) alpha = 1.0f;
    a = (int32_t)(alpha * 255.0f + 0.5f);
    for (i = 0; i < count; ++i)
    {
        int32_t o = i * 4;
        int32_t dr = dst[o], dg = dst[o+1], db = dst[o+2], da = dst[o+3];
        int32_t lr = layer[o], lg = layer[o+1], lb = layer[o+2], la = layer[o+3];
        int32_t sa = la * a / 255;
        int32_t nr, ng, nb, na;
        if (mode == 1)
        {
            nr = dr + lr * a / 255; ng = dg + lg * a / 255; nb = db + lb * a / 255;
            if (nr > 255) nr = 255; if (ng > 255) ng = 255; if (nb > 255) nb = 255;
        }
        else if (mode == 2)
        {
            int32_t ia = 255 - a;
            nr = dr * (ia + a * lr / 255) / 255;
            ng = dg * (ia + a * lg / 255) / 255;
            nb = db * (ia + a * lb / 255) / 255;
        }
        else
        {
            int32_t isa = 255 - sa;
            nr = (lr * sa + dr * isa) / 255;
            ng = (lg * sa + dg * isa) / 255;
            nb = (lb * sa + db * isa) / 255;
        }
        na = sa + da * (255 - sa) / 255;
        if (nr < 0) nr = 0; if (nr > 255) nr = 255;
        if (ng < 0) ng = 0; if (ng > 255) ng = 255;
        if (nb < 0) nb = 0; if (nb > 255) nb = 255;
        if (na < 0) na = 0; if (na > 255) na = 255;
        dst[o] = (uint8_t)nr; dst[o+1] = (uint8_t)ng;
        dst[o+2] = (uint8_t)nb; dst[o+3] = (uint8_t)na;
    }
    return count;
}
