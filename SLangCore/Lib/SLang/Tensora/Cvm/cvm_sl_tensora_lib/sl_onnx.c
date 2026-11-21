/*
 * sl_onnx.c —— Tensora cvm 原生实现 ONNX 读取部分（合入 sl_tensora_lib.dll）
 * ==========================================================================
 * 手写 ONNX（protobuf wire format）最小解析器，零外部依赖（无
 * protobuf / onnx 库 / SDK）：直接按 wire format 扫描
 *   ModelProto(field 7 = graph) -> GraphProto(field 5 = initializer, repeated)
 *   -> TensorProto(dims / data_type / name / float_data / raw_data)
 * 权重张量物化为连续 f32 缓冲，暴露裸指针 + 批量 memcpy 出口
 * （Onnx.sl 经 @DllStaticImport 直调，"上层拿指针读数据"通路）。
 *
 * wire format 速查（仅本文件涉及面）：
 *   varint  : LEB128，每字节低 7 位有效，bit7 = 继续
 *   tag     : (field_number << 3) | wire_type
 *   wire 0  : varint（标量 / repeated 非打包）
 *   wire 2  : length-delimited（varint 长度 + 载荷：string/bytes/
 *             packed repeated/嵌套 message）
 *   wire 1/5: 8/4 字节定长块（本面未出现，统一按尺寸跳过）
 *
 * v1 范围：dtype = 1（FLOAT）；float_data（packed）与 raw_data 两条
 * 数据路径都支持（raw_data 优先——与 ONNX 规范的序列化工具行为对齐）。
 * dims 同时兼容 packed（wire 2）与非 packed（wire 0）两种编码。
 * ==========================================================================
 */

#include "vm_sl_onnx.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* 数据结构                                                            */
/* ------------------------------------------------------------------ */

typedef struct {
    char     name[128];
    int64_t* dims;        /* 维度数组（元素个数为 dim_count） */
    int32_t  dim_count;
    int32_t  dtype;       /* ONNX TensorProto.DataType 原值 */
    float*   f32;         /* 物化连续 f32 数据（elem_count 个） */
    int64_t  elem_count;
} SloTensor;

typedef struct {
    SloTensor* items;
    int32_t    count;
    int32_t    cap;
} SloModel;

/* ------------------------------------------------------------------ */
/* 错误通道（粘性）                                                    */
/* ------------------------------------------------------------------ */

static int32_t s_err = 0;
static char     s_err_buf[256];

static int32_t slo_fail(int32_t code, const char* msg)
{
    s_err = code;
    strncpy(s_err_buf, msg, sizeof(s_err_buf) - 1);
    s_err_buf[sizeof(s_err_buf) - 1] = '\0';
    return code;
}

SLO_API int32_t slo_last_error(void)
{
    return s_err;
}

SLO_API const char* slo_error_string(int32_t err)
{
    if (err == 0)
    {
        err = s_err;
    }
    switch (err)
    {
    case 0:  return "success";
    case -1: return "invalid argument";
    case -2: return "file open/read failed";
    case -3: return "malformed protobuf";
    case -4: return "graph not found in model";
    case -5: return "unsupported data type (v1: FLOAT only)";
    case -6: return "element count mismatch with dims";
    case -7: return "out of memory";
    case -8: return "index out of range";
    default: return (err < 0 && s_err == err) ? s_err_buf : "unknown error";
    }
}

/* ------------------------------------------------------------------ */
/* wire format 读取原语（p/pend 区间；越界即错）                        */
/* ------------------------------------------------------------------ */

typedef struct {
    const uint8_t* p;
    const uint8_t* end;
} SloRange;

static int32_t slo_read_varint(SloRange* r, uint64_t* out)
{
    uint64_t v = 0;
    int32_t shift = 0;
    for (;;)
    {
        uint8_t b;
        if (r->p >= r->end)
        {
            return 0;
        }
        b = *r->p++;
        v |= (uint64_t)(b & 0x7F) << shift;
        if ((b & 0x80) == 0)
        {
            break;
        }
        shift += 7;
        if (shift > 63)
        {
            return 0;
        }
    }
    *out = v;
    return 1;
}

/* 读 tag（field_number + wire_type）。失败返回 0。 */
static int32_t slo_read_tag(SloRange* r, int32_t* field, int32_t* wire)
{
    uint64_t tag = 0;
    if (!slo_read_varint(r, &tag))
    {
        return 0;
    }
    *field = (int32_t)(tag >> 3);
    *wire = (int32_t)(tag & 7u);
    return 1;
}

/* 跳过一个未知字段的载荷（按 wire type）。失败返回 0。 */
static int32_t slo_skip_field(SloRange* r, int32_t wire)
{
    uint64_t len = 0;
    switch (wire)
    {
    case 0:
        {
            uint64_t dummy = 0;
            return slo_read_varint(r, &dummy);
        }
    case 1:
        if (r->end - r->p < 8) { return 0; }
        r->p += 8;
        return 1;
    case 2:
        if (!slo_read_varint(r, &len)) { return 0; }
        if (len > (uint64_t)(r->end - r->p)) { return 0; }
        r->p += len;
        return 1;
    case 5:
        if (r->end - r->p < 4) { return 0; }
        r->p += 4;
        return 1;
    default:
        return 0;    /* wire 3/4（group，proto2 遗留）本面不支持 */
    }
}

/* 读 length-delimited 载荷子区间。失败返回 0。 */
static int32_t slo_read_ld(SloRange* r, SloRange* out)
{
    uint64_t len = 0;
    if (!slo_read_varint(r, &len))
    {
        return 0;
    }
    if (len > (uint64_t)(r->end - r->p))
    {
        return 0;
    }
    out->p = r->p;
    out->end = r->p + len;
    r->p += len;
    return 1;
}

/* ------------------------------------------------------------------ */
/* TensorProto 解析                                                    */
/* ------------------------------------------------------------------ */

/* 解析一个 TensorProto 区间为 SloTensor（*out 需已被零初始化）。
   返回值：1 = 成功；2 = 跳过（非 FLOAT dtype 或无数据载荷——真实模型
   常带 INT64/shape 常量等辅助 initializer，v1 只物化 FLOAT）；0 = 结构
   性错误（整体失败）。 */
static int32_t slo_parse_tensor(SloRange* r, SloTensor* out)
{
    SloRange fr = *r;
    int64_t dims_tmp[16];
    int32_t dims_n = 0;
    int32_t dtype = 0;
    SloRange float_data = { NULL, NULL };
    SloRange raw_data = { NULL, NULL };
    int32_t i;
    int64_t prod;

    memset(out, 0, sizeof(*out));

    while (fr.p < fr.end)
    {
        int32_t field = 0;
        int32_t wire = 0;
        if (!slo_read_tag(&fr, &field, &wire))
        {
            return 0;
        }
        if (field == 1 && wire == 0)
        {
            /* dims：非 packed 单值 */
            uint64_t v = 0;
            if (!slo_read_varint(&fr, &v)) { return 0; }
            if (dims_n < 16) { dims_tmp[dims_n] = (int64_t)v; }
            dims_n++;
        }
        else if (field == 1 && wire == 2)
        {
            /* dims：packed varint */
            SloRange pr;
            if (!slo_read_ld(&fr, &pr)) { return 0; }
            while (pr.p < pr.end)
            {
                uint64_t v = 0;
                if (!slo_read_varint(&pr, &v)) { return 0; }
                if (dims_n < 16) { dims_tmp[dims_n] = (int64_t)v; }
                dims_n++;
            }
        }
        else if (field == 2 && wire == 0)
        {
            uint64_t v = 0;
            if (!slo_read_varint(&fr, &v)) { return 0; }
            dtype = (int32_t)v;
        }
        else if (field == 4 && wire == 2)
        {
            if (!slo_read_ld(&fr, &float_data)) { return 0; }
        }
        else if (field == 8 && wire == 2)
        {
            SloRange sr;
            if (!slo_read_ld(&fr, &sr)) { return 0; }
            {
                size_t n = (size_t)(sr.end - sr.p);
                if (n >= sizeof(out->name)) { n = sizeof(out->name) - 1; }
                memcpy(out->name, sr.p, n);
                out->name[n] = '\0';
            }
        }
        else if (field == 9 && wire == 2)
        {
            if (!slo_read_ld(&fr, &raw_data)) { return 0; }
        }
        else
        {
            if (!slo_skip_field(&fr, wire)) { return 0; }
        }
    }

    /* 校验与物化：非 FLOAT / 无载荷 → 跳过（返回 2，不物化不计数） */
    if (dtype != 1)
    {
        return 2;
    }
    if (dims_n <= 0 || dims_n > 16)
    {
        slo_fail(-3, "bad dims count");
        return 0;
    }
    prod = 1;
    for (i = 0; i < dims_n; ++i)
    {
        if (dims_tmp[i] <= 0)
        {
            slo_fail(-3, "bad dim value");
            return 0;
        }
        prod *= dims_tmp[i];
    }
    if (prod > (int64_t)0x7FFFFFFF)
    {
        slo_fail(-3, "tensor too large");
        return 0;
    }
    out->elem_count = prod;
    out->dim_count = dims_n;
    out->dtype = dtype;

    out->dims = (int64_t*)malloc(sizeof(int64_t) * (size_t)dims_n);
    out->f32 = (float*)malloc(sizeof(float) * (size_t)prod);
    if (out->dims == NULL || out->f32 == NULL)
    {
        free(out->dims);
        free(out->f32);
        out->dims = NULL;
        out->f32 = NULL;
        slo_fail(-7, "out of memory");
        return 0;
    }
    memcpy(out->dims, dims_tmp, sizeof(int64_t) * (size_t)dims_n);

    /* raw_data 优先；否则 float_data（packed f32 LE）。x64 小端直接 memcpy */
    if (raw_data.p != NULL)
    {
        if ((int64_t)(raw_data.end - raw_data.p) != prod * 4)
        {
            slo_fail(-6, "raw_data size mismatch with dims");
            return 0;
        }
        memcpy(out->f32, raw_data.p, (size_t)(prod * 4));
    }
    else if (float_data.p != NULL)
    {
        if ((int64_t)(float_data.end - float_data.p) != prod * 4)
        {
            slo_fail(-6, "float_data size mismatch with dims");
            return 0;
        }
        memcpy(out->f32, float_data.p, (size_t)(prod * 4));
    }
    else
    {
        return 2;    /* 无 float_data/raw_data 载荷：跳过 */
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* 打开 / 关闭 / 查询                                                  */
/* ------------------------------------------------------------------ */

SLO_API int64_t slo_open(const char* path)
{
    FILE* f = NULL;
    long fsize = 0;
    uint8_t* buf = NULL;
    SloModel* m = NULL;
    SloRange top;
    SloRange graph;
    int32_t graph_found = 0;

    s_err = 0;
    if (path == NULL || path[0] == '\0')
    {
        slo_fail(-1, "invalid path");
        return 0;
    }
    f = fopen(path, "rb");
    if (f == NULL)
    {
        slo_fail(-2, "file open failed");
        return 0;
    }
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); slo_fail(-2, "seek failed"); return 0; }
    fsize = ftell(f);
    if (fsize <= 0) { fclose(f); slo_fail(-2, "empty file"); return 0; }
    if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); slo_fail(-2, "seek failed"); return 0; }

    buf = (uint8_t*)malloc((size_t)fsize);
    if (buf == NULL) { fclose(f); slo_fail(-7, "out of memory"); return 0; }
    if (fread(buf, 1, (size_t)fsize, f) != (size_t)fsize)
    {
        free(buf);
        fclose(f);
        slo_fail(-2, "read failed");
        return 0;
    }
    fclose(f);

    m = (SloModel*)calloc(1, sizeof(SloModel));
    if (m == NULL) { free(buf); slo_fail(-7, "out of memory"); return 0; }
    m->cap = 8;
    m->items = (SloTensor*)calloc((size_t)m->cap, sizeof(SloTensor));
    if (m->items == NULL) { free(buf); free(m); slo_fail(-7, "out of memory"); return 0; }

    /* ModelProto 顶层：找 field 7（graph） */
    top.p = buf;
    top.end = buf + fsize;
    while (top.p < top.end)
    {
        int32_t field = 0;
        int32_t wire = 0;
        if (!slo_read_tag(&top, &field, &wire))
        {
            free(buf);
            slo_fail(-3, "malformed model proto");
            /* 已收集条目在 close 语义外——此处直接回收模型 */
            {
                int32_t i;
                for (i = 0; i < m->count; ++i)
                {
                    free(m->items[i].dims);
                    free(m->items[i].f32);
                }
                free(m->items);
                free(m);
            }
            return 0;
        }
        if (field == 7 && wire == 2)
        {
            if (!slo_read_ld(&top, &graph))
            {
                free(buf);
                slo_fail(-3, "malformed graph length");
                {
                    int32_t i;
                    for (i = 0; i < m->count; ++i)
                    {
                        free(m->items[i].dims);
                        free(m->items[i].f32);
                    }
                    free(m->items);
                    free(m);
                }
                return 0;
            }
            graph_found = 1;
            break;
        }
        if (!slo_skip_field(&top, wire))
        {
            free(buf);
            slo_fail(-3, "malformed model proto (skip)");
            {
                int32_t i;
                for (i = 0; i < m->count; ++i)
                {
                    free(m->items[i].dims);
                    free(m->items[i].f32);
                }
                free(m->items);
                free(m);
            }
            return 0;
        }
    }
    if (!graph_found)
    {
        free(buf);
        slo_fail(-4, "graph not found in model");
        free(m->items);
        free(m);
        return 0;
    }

    /* GraphProto：收集 field 5（initializer，repeated TensorProto） */
    while (graph.p < graph.end)
    {
        int32_t field = 0;
        int32_t wire = 0;
        if (!slo_read_tag(&graph, &field, &wire))
        {
            free(buf);
            slo_fail(-3, "malformed graph proto");
            {
                int32_t i;
                for (i = 0; i < m->count; ++i)
                {
                    free(m->items[i].dims);
                    free(m->items[i].f32);
                }
                free(m->items);
                free(m);
            }
            return 0;
        }
        if (field == 5 && wire == 2)
        {
            SloRange tr;
            if (!slo_read_ld(&graph, &tr))
            {
                free(buf);
                slo_fail(-3, "malformed tensor length");
                {
                    int32_t i;
                    for (i = 0; i < m->count; ++i)
                    {
                        free(m->items[i].dims);
                        free(m->items[i].f32);
                    }
                    free(m->items);
                    free(m);
                }
                return 0;
            }
            if (m->count >= m->cap)
            {
                int32_t ncap = m->cap * 2;
                SloTensor* ni = (SloTensor*)realloc(m->items,
                                    sizeof(SloTensor) * (size_t)ncap);
                if (ni == NULL)
                {
                    free(buf);
                    slo_fail(-7, "out of memory");
                    {
                        int32_t i;
                        for (i = 0; i < m->count; ++i)
                        {
                            free(m->items[i].dims);
                            free(m->items[i].f32);
                        }
                        free(m->items);
                        free(m);
                    }
                    return 0;
                }
                m->items = ni;
                m->cap = ncap;
            }
            {
                int32_t rc = slo_parse_tensor(&tr, &m->items[m->count]);
                if (rc == 0)
                {
                    free(buf);
                    /* 解析失败：回收模型（含半成品条目） */
                    {
                        int32_t i;
                        for (i = 0; i <= m->count; ++i)
                        {
                            if (m->items[i].dims != NULL) { free(m->items[i].dims); }
                            if (m->items[i].f32 != NULL) { free(m->items[i].f32); }
                        }
                        free(m->items);
                        free(m);
                    }
                    return 0;    /* slo_fail 已在 parse 内置码 */
                }
                if (rc == 1)
                {
                    m->count++;
                }
                /* rc == 2：跳过（非 FLOAT / 无载荷），不计数 */
            }
        }
        else
        {
            if (!slo_skip_field(&graph, wire))
            {
                free(buf);
                slo_fail(-3, "malformed graph proto (skip)");
                {
                    int32_t i;
                    for (i = 0; i < m->count; ++i)
                    {
                        free(m->items[i].dims);
                        free(m->items[i].f32);
                    }
                    free(m->items);
                    free(m);
                }
                return 0;
            }
        }
    }

    free(buf);
    if (m->count == 0)
    {
        slo_fail(-4, "no initializer found in graph");
        free(m->items);
        free(m);
        return 0;
    }
    return (int64_t)(intptr_t)m;
}

SLO_API int32_t slo_close(int64_t model)
{
    SloModel* m = (SloModel*)(intptr_t)model;
    int32_t i;
    s_err = 0;
    if (m == NULL)
    {
        slo_fail(-1, "invalid model handle");
        return 0;
    }
    for (i = 0; i < m->count; ++i)
    {
        free(m->items[i].dims);
        free(m->items[i].f32);
    }
    free(m->items);
    free(m);
    return 1;
}

/* 内部：取第 idx 个张量（越界置错返回 NULL） */
static SloTensor* slo_get(SloModel* m, int32_t idx)
{
    if (m == NULL || idx < 0 || idx >= m->count)
    {
        slo_fail(-8, "index out of range");
        return NULL;
    }
    return &m->items[idx];
}

SLO_API int32_t slo_count(int64_t model)
{
    SloModel* m = (SloModel*)(intptr_t)model;
    s_err = 0;
    if (m == NULL)
    {
        slo_fail(-1, "invalid model handle");
        return -1;
    }
    return m->count;
}

SLO_API const char* slo_name(int64_t model, int32_t idx)
{
    SloTensor* t = NULL;
    s_err = 0;
    t = slo_get((SloModel*)(intptr_t)model, idx);
    if (t == NULL)
    {
        return "";
    }
    return t->name;
}

SLO_API int32_t slo_rank(int64_t model, int32_t idx)
{
    SloTensor* t = NULL;
    s_err = 0;
    t = slo_get((SloModel*)(intptr_t)model, idx);
    if (t == NULL)
    {
        return -1;
    }
    return t->dim_count;
}

SLO_API int32_t slo_dim(int64_t model, int32_t idx, int32_t axis)
{
    SloTensor* t = NULL;
    s_err = 0;
    t = slo_get((SloModel*)(intptr_t)model, idx);
    if (t == NULL)
    {
        return -1;
    }
    if (axis < 0 || axis >= t->dim_count)
    {
        slo_fail(-8, "axis out of range");
        return -1;
    }
    return (int32_t)t->dims[axis];
}

SLO_API int32_t slo_elem_count(int64_t model, int32_t idx)
{
    SloTensor* t = NULL;
    s_err = 0;
    t = slo_get((SloModel*)(intptr_t)model, idx);
    if (t == NULL)
    {
        return -1;
    }
    return (int32_t)t->elem_count;
}

SLO_API int32_t slo_data_type(int64_t model, int32_t idx)
{
    SloTensor* t = NULL;
    s_err = 0;
    t = slo_get((SloModel*)(intptr_t)model, idx);
    if (t == NULL)
    {
        return -1;
    }
    return t->dtype;
}

SLO_API int64_t slo_data_ptr(int64_t model, int32_t idx)
{
    SloTensor* t = NULL;
    s_err = 0;
    t = slo_get((SloModel*)(intptr_t)model, idx);
    if (t == NULL)
    {
        return 0;
    }
    return (int64_t)(intptr_t)t->f32;
}

SLO_API int32_t slo_copy_f32(int64_t model, int32_t idx, float* dst)
{
    SloTensor* t = NULL;
    s_err = 0;
    if (dst == NULL)
    {
        slo_fail(-1, "invalid dst pointer");
        return 0;
    }
    t = slo_get((SloModel*)(intptr_t)model, idx);
    if (t == NULL)
    {
        return 0;
    }
    memcpy(dst, t->f32, sizeof(float) * (size_t)t->elem_count);
    return 1;
}


/* ------------------------------------------------------------------ */
/* 测试模型生成器（手写 protobuf 编码，纯内存组装）                    */
/* ------------------------------------------------------------------ */

/* 内存缓冲写入器（cap 冗余预留，本函数用量远小于分配量） */
typedef struct {
    uint8_t* buf;
    size_t   len;
    size_t   cap;
    int32_t  ok;
} SloMemW;

static void slo_mw_init(SloMemW* w, uint8_t* buf, size_t cap)
{
    w->buf = buf; w->len = 0; w->cap = cap; w->ok = 1;
}

static void slo_mw_byte(SloMemW* w, uint8_t b)
{
    if (w->ok && w->len < w->cap) { w->buf[w->len++] = b; } else { w->ok = 0; }
}

static void slo_mw_varint(SloMemW* w, uint64_t v)
{
    while (w->ok)
    {
        uint8_t b = (uint8_t)(v & 0x7F);
        v >>= 7;
        if (v != 0) { b |= 0x80u; }
        slo_mw_byte(w, b);
        if (v == 0) { break; }
    }
}

static void slo_mw_tag(SloMemW* w, int32_t field, int32_t wire)
{
    slo_mw_varint(w, ((uint64_t)field << 3) | (uint64_t)wire);
}

static void slo_mw_ld(SloMemW* w, int32_t field, const void* data, size_t len)
{
    slo_mw_tag(w, field, 2);
    slo_mw_varint(w, (uint64_t)len);
    if (w->ok && len > 0 && w->len + len <= w->cap)
    {
        memcpy(w->buf + w->len, data, len);
        w->len += len;
    }
    else if (len > 0)
    {
        w->ok = 0;
    }
}

/* 序列化一个 TensorProto 到 graph 缓冲（作为 GraphProto field 5） */
static void slo_mw_tensor(SloMemW* g, const char* name,
                          const int64_t* dims, int32_t dims_n,
                          const float* vals, int32_t use_raw)
{
    SloMemW t;
    uint8_t tbuf[512];
    int32_t i;
    int64_t n = 1;
    size_t name_len;

    for (i = 0; i < dims_n; ++i) { n *= dims[i]; }
    name_len = strlen(name);

    slo_mw_init(&t, tbuf, sizeof(tbuf));
    /* TensorProto field 1: dims（非 packed varint，逐字段） */
    for (i = 0; i < dims_n; ++i)
    {
        slo_mw_tag(&t, 1, 0);
        slo_mw_varint(&t, (uint64_t)dims[i]);
    }
    /* TensorProto field 2: data_type = 1（FLOAT） */
    slo_mw_tag(&t, 2, 0);
    slo_mw_varint(&t, 1);
    /* TensorProto field 8: name */
    slo_mw_ld(&t, 8, name, name_len);
    /* TensorProto field 4/9: float_data / raw_data（x64 小端直写位模式） */
    slo_mw_tag(&t, use_raw ? 9 : 4, 2);
    slo_mw_varint(&t, (uint64_t)((size_t)n * 4));
    if (t.ok && t.len + (size_t)n * 4 <= t.cap)
    {
        memcpy(t.buf + t.len, vals, (size_t)n * 4);
        t.len += (size_t)n * 4;
    }
    else
    {
        t.ok = 0;
    }
    /* 包成 GraphProto field 5（initializer，length-delimited） */
    slo_mw_ld(g, 5, tbuf, t.len);
}

SLO_API int32_t slo_make_test_model(const char* path)
{
    int64_t d0[2] = { 2, 3 };
    int64_t d1[1] = { 5 };
    float v0[6] = { 1.5f, -2.25f, 3.0f, 0.5f, 100.0f, 2.0f };
    float v1[5] = { 10.0f, 20.0f, 30.0f, 40.0f, 50.0f };
    uint8_t graph[2048];
    uint8_t model[2200];
    SloMemW g;
    SloMemW m;
    FILE* f;

    s_err = 0;
    if (path == NULL || path[0] == '\0')
    {
        slo_fail(-1, "invalid path");
        return 0;
    }

    /* graph = 两个 initializer（w0 走 float_data，w1 走 raw_data） */
    slo_mw_init(&g, graph, sizeof(graph));
    slo_mw_tensor(&g, "w0", d0, 2, v0, 0);
    slo_mw_tensor(&g, "w1", d1, 1, v1, 1);
    if (!g.ok)
    {
        slo_fail(-7, "graph buffer overflow (impossible)");
        return 0;
    }

    /* model = ModelProto{ graph(field 7) = graph 内容 } */
    slo_mw_init(&m, model, sizeof(model));
    slo_mw_ld(&m, 7, graph, g.len);
    if (!m.ok)
    {
        slo_fail(-7, "model buffer overflow (impossible)");
        return 0;
    }

    f = fopen(path, "wb");
    if (f == NULL)
    {
        slo_fail(-2, "file open failed");
        return 0;
    }
    if (fwrite(model, 1, m.len, f) != m.len)
    {
        fclose(f);
        slo_fail(-2, "write failed");
        return 0;
    }
    fclose(f);
    return 1;
}