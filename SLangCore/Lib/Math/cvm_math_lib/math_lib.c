/*
 * math_lib.c —— Math 模块 FFI 原生实现（产物 math_lib.dll）。
 *
 * 供 Mathf.sl / Mathd.sl / 矩阵类的 @DllImport 声明直接绑定
 * （FFI.StaticLibrary.bindFunction，普通 C ABI，无 VM 栈依赖，
 * 见 md/design/ffi-design.md）：
 *
 *     @DllImport( "math_lib", "mathf_sin", "Float32->Float32" )
 *     public static Float32 sin( Float32 value ) { ...SL fallback... }
 *
 * 导出命名约定：
 *   mathf_* —— Float32（单精度），C 形参/返回 float，sig 用 SL 名 "Float32"；
 *   mathd_* —— Float64（双精度），C 形参/返回 double，sig 用 SL 名 "Float64"；
 *   *dot3   —— 三元素内积（矩阵乘法/变换按行、列元素直接传参，
 *              6 实参恰为 FFI 调度上限，避开 SL 数组寻址开销）。
 *
 * 调用约定：x64 唯一（Microsoft x64），与 sl_ffi_call 的 INT/DBL
 * 分类调度对齐（float/double 实参与返回均走 XMM 寄存器）。
 */

#include <math.h>

/* wasm 载体：MAIN_MODULE=1 全量符号导出，无需 dllexport 标记；
 * sl_vm_ext_api.h 由 VM 头目录提供（math_vm_object_bridge 引用）。 */
#if defined(__EMSCRIPTEN__)
#define MATH_LIB_API
#else
#define MATH_LIB_API __declspec(dllexport)
#endif

/* ===================== Float32（mathf_*） ===================== */

MATH_LIB_API float mathf_sin(float x) { return sinf(x); }
MATH_LIB_API float mathf_cos(float x) { return cosf(x); }
MATH_LIB_API float mathf_tan(float x) { return tanf(x); }
MATH_LIB_API float mathf_asin(float x) { return asinf(x); }
MATH_LIB_API float mathf_acos(float x) { return acosf(x); }
MATH_LIB_API float mathf_atan(float x) { return atanf(x); }
MATH_LIB_API float mathf_atan2(float y, float x) { return atan2f(y, x); }
MATH_LIB_API float mathf_sinh(float x) { return sinhf(x); }
MATH_LIB_API float mathf_cosh(float x) { return coshf(x); }
MATH_LIB_API float mathf_tanh(float x) { return tanhf(x); }
MATH_LIB_API float mathf_pow(float x, float y) { return powf(x, y); }
MATH_LIB_API float mathf_sqrt(float x) { return sqrtf(x); }
MATH_LIB_API float mathf_exp(float x) { return expf(x); }
MATH_LIB_API float mathf_log(float x) { return logf(x); }
MATH_LIB_API float mathf_log10(float x) { return log10f(x); }
MATH_LIB_API float mathf_ceil(float x) { return ceilf(x); }
MATH_LIB_API float mathf_floor(float x) { return floorf(x); }
MATH_LIB_API float mathf_round(float x) { return roundf(x); }
MATH_LIB_API int   mathf_truncate(float x) { return (int)x; }

MATH_LIB_API float mathf_dot3(float a0, float a1, float a2,
                               float b0, float b1, float b2)
{
    return a0 * b0 + a1 * b1 + a2 * b2;
}

/* ===================== Float64（mathd_*） ===================== */

MATH_LIB_API double mathd_sin(double x) { return sin(x); }
MATH_LIB_API double mathd_cos(double x) { return cos(x); }
MATH_LIB_API double mathd_tan(double x) { return tan(x); }
MATH_LIB_API double mathd_asin(double x) { return asin(x); }
MATH_LIB_API double mathd_acos(double x) { return acos(x); }
MATH_LIB_API double mathd_atan(double x) { return atan(x); }
MATH_LIB_API double mathd_atan2(double y, double x) { return atan2(y, x); }
MATH_LIB_API double mathd_sinh(double x) { return sinh(x); }
MATH_LIB_API double mathd_cosh(double x) { return cosh(x); }
MATH_LIB_API double mathd_tanh(double x) { return tanh(x); }
MATH_LIB_API double mathd_pow(double x, double y) { return pow(x, y); }
MATH_LIB_API double mathd_sqrt(double x) { return sqrt(x); }
MATH_LIB_API double mathd_exp(double x) { return exp(x); }
MATH_LIB_API double mathd_log(double x) { return log(x); }
MATH_LIB_API double mathd_log10(double x) { return log10(x); }
MATH_LIB_API double mathd_ceil(double x) { return ceil(x); }
MATH_LIB_API double mathd_floor(double x) { return floor(x); }
MATH_LIB_API double mathd_round(double x) { return round(x); }
MATH_LIB_API int    mathd_truncate(double x) { return (int)x; }

MATH_LIB_API double mathd_dot3(double a0, double a1, double a2,
                               double b0, double b1, double b2)
{
    return a0 * b0 + a1 * b1 + a2 * b2;
}

/* ===================== Complex（mathc_*） =====================
 * 复数拆参 ABI：每个复数按 (real, imag) 两个标量参数传入；
 * 返回值同样拆成两个标量函数（_re / _im），规避 FFI 无结构体返回的
 * 限制，且实部/虚部计算天然独立，不产生临时对象。
 *   mathc_f_* —— Complex32（float）；mathc_d_* —— Complex64（double）。
 * 超越函数手写标准公式（不依赖 <complex.h>，规避 MSVC C 模式 _Fcomplex
 * 无法用运算符构造的问题，且与 SL 侧 fallback 公式一致，跨平台统一）。
 * FFI 实参数量：两复数运算 4 参，取模/共轭/标量 2 参，均在 6 参上限内。 */

/* ---- 基础四则：re/im 各自独立 ---- */
MATH_LIB_API float mathc_f_add_re(float ar, float ai, float br, float bi) { (void)ai; (void)bi; return ar + br; }
MATH_LIB_API float mathc_f_add_im(float ar, float ai, float br, float bi) { (void)ar; (void)br; return ai + bi; }
MATH_LIB_API float mathc_f_sub_re(float ar, float ai, float br, float bi) { (void)ai; (void)bi; return ar - br; }
MATH_LIB_API float mathc_f_sub_im(float ar, float ai, float br, float bi) { (void)ar; (void)br; return ai - bi; }
MATH_LIB_API float mathc_f_mul_re(float ar, float ai, float br, float bi) { return ar * br - ai * bi; }
MATH_LIB_API float mathc_f_mul_im(float ar, float ai, float br, float bi) { return ar * bi + ai * br; }
/* 除法：(a+bi)/(c+di) = ((ac+bd) + (bc-ad)i)/(c^2+d^2) */
MATH_LIB_API float mathc_f_div_re(float ar, float ai, float br, float bi)
{
    float d = br * br + bi * bi;
    return (ar * br + ai * bi) / d;
}
MATH_LIB_API float mathc_f_div_im(float ar, float ai, float br, float bi)
{
    float d = br * br + bi * bi;
    return (ai * br - ar * bi) / d;
}

MATH_LIB_API double mathc_d_add_re(double ar, double ai, double br, double bi) { (void)ai; (void)bi; return ar + br; }
MATH_LIB_API double mathc_d_add_im(double ar, double ai, double br, double bi) { (void)ar; (void)br; return ai + bi; }
MATH_LIB_API double mathc_d_sub_re(double ar, double ai, double br, double bi) { (void)ai; (void)bi; return ar - br; }
MATH_LIB_API double mathc_d_sub_im(double ar, double ai, double br, double bi) { (void)ar; (void)br; return ai - bi; }
MATH_LIB_API double mathc_d_mul_re(double ar, double ai, double br, double bi) { return ar * br - ai * bi; }
MATH_LIB_API double mathc_d_mul_im(double ar, double ai, double br, double bi) { return ar * bi + ai * br; }
MATH_LIB_API double mathc_d_div_re(double ar, double ai, double br, double bi)
{
    double d = br * br + bi * bi;
    return (ar * br + ai * bi) / d;
}
MATH_LIB_API double mathc_d_div_im(double ar, double ai, double br, double bi)
{
    double d = br * br + bi * bi;
    return (ai * br - ar * bi) / d;
}

/* ---- 模/共轭/幅角 ---- */
MATH_LIB_API float  mathc_f_abs(float ar, float ai) { return hypotf(ar, ai); }
MATH_LIB_API double mathc_d_abs(double ar, double ai) { return hypot(ar, ai); }
MATH_LIB_API float  mathc_f_arg(float ar, float ai) { return atan2f(ai, ar); }
MATH_LIB_API double mathc_d_arg(double ar, double ai) { return atan2(ai, ar); }
MATH_LIB_API float  mathc_f_conj_im(float ar, float ai) { (void)ar; return -ai; }
MATH_LIB_API double mathc_d_conj_im(double ar, double ai) { (void)ar; return -ai; }

/* ---- 超越函数：手写标准公式，返回 re/im 两标量 ---- */
/* exp(a+bi) = e^a(cos b + i sin b) */
MATH_LIB_API float mathc_f_exp_re(float ar, float ai) { return expf(ar) * cosf(ai); }
MATH_LIB_API float mathc_f_exp_im(float ar, float ai) { return expf(ar) * sinf(ai); }
/* sqrt(a+bi): r=|z|, re=sqrt((r+a)/2), im=b/(2*re) */
MATH_LIB_API float mathc_f_sqrt_re(float ar, float ai)
{
    float r = hypotf(ar, ai);
    return sqrtf((r + ar) / 2.0f);
}
MATH_LIB_API float mathc_f_sqrt_im(float ar, float ai)
{
    float r = hypotf(ar, ai);
    float re = sqrtf((r + ar) / 2.0f);
    return (re == 0.0f) ? 0.0f : (ai / (2.0f * re));
}
/* log(a+bi) = ln|z| + i*atan2(b,a) */
MATH_LIB_API float mathc_f_log_re(float ar, float ai) { return logf(hypotf(ar, ai)); }
MATH_LIB_API float mathc_f_log_im(float ar, float ai) { return atan2f(ai, ar); }
/* sin(a+bi) = sin a cosh b + i cos a sinh b */
MATH_LIB_API float mathc_f_sin_re(float ar, float ai) { return sinf(ar) * coshf(ai); }
MATH_LIB_API float mathc_f_sin_im(float ar, float ai) { return cosf(ar) * sinhf(ai); }
/* cos(a+bi) = cos a cosh b - i sin a sinh b */
MATH_LIB_API float mathc_f_cos_re(float ar, float ai) { return cosf(ar) * coshf(ai); }
MATH_LIB_API float mathc_f_cos_im(float ar, float ai) { return -sinf(ar) * sinhf(ai); }

MATH_LIB_API double mathc_d_exp_re(double ar, double ai) { return exp(ar) * cos(ai); }
MATH_LIB_API double mathc_d_exp_im(double ar, double ai) { return exp(ar) * sin(ai); }
MATH_LIB_API double mathc_d_sqrt_re(double ar, double ai)
{
    double r = hypot(ar, ai);
    return sqrt((r + ar) / 2.0);
}
MATH_LIB_API double mathc_d_sqrt_im(double ar, double ai)
{
    double r = hypot(ar, ai);
    double re = sqrt((r + ar) / 2.0);
    return (re == 0.0) ? 0.0 : (ai / (2.0 * re));
}
MATH_LIB_API double mathc_d_log_re(double ar, double ai) { return log(hypot(ar, ai)); }
MATH_LIB_API double mathc_d_log_im(double ar, double ai) { return atan2(ai, ar); }
MATH_LIB_API double mathc_d_sin_re(double ar, double ai) { return sin(ar) * cosh(ai); }
MATH_LIB_API double mathc_d_sin_im(double ar, double ai) { return cos(ar) * sinh(ai); }
MATH_LIB_API double mathc_d_cos_re(double ar, double ai) { return cos(ar) * cosh(ai); }
MATH_LIB_API double mathc_d_cos_im(double ar, double ai) { return -sin(ar) * sinh(ai); }

/* 由极坐标构造：a + bi = r(cos(theta) + i sin(theta)) */
MATH_LIB_API float  mathc_f_from_polar_re(float r, float theta) { return r * cosf(theta); }
MATH_LIB_API float  mathc_f_from_polar_im(float r, float theta) { return r * sinf(theta); }
MATH_LIB_API double mathc_d_from_polar_re(double r, double theta) { return r * cos(theta); }
MATH_LIB_API double mathc_d_from_polar_im(double r, double theta) { return r * sin(theta); }
