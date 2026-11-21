import Math;
# TensorMath —— Tensora 专用标量数学（Mathf 之上的 AI 补充函数）
#
# 说明：
#   三角/指数/开方等基础能力直接复用 Math 库的 Mathf（Float32）
#   本类补齐 AI 常用但 Mathf 没有的函数：sigmoid / gelu / erf / softplus 等
#   所有函数均为 static，逐元素运算由 Tensor 调用

@Nickname("TMath")
public class TensorMath
{
    public const static Float32 Pi = 3.141592653589793f
    public const static Float32 E = 2.718281828459045f

    # 数值稳定用的极小值，避免 log(0) / 除 0
    public const static Float32 Eps = 0.0000001f

    # ── 基础 ─────────────────────────────────────────────
    public static Float32 exp( Float32 x )
    {
        ret Mathf.exp( x )
    }

    public static Float32 log( Float32 x )
    {
        ret Mathf.log( x )
    }

    # log 的防零版本（分类/熵相关必用）
    public static Float32 safeLog( Float32 x )
    {
        if x < Eps
        {
            ret Mathf.log( Eps )
        }
        ret Mathf.log( x )
    }

    public static Float32 sqrt( Float32 x )
    {
        ret Mathf.sqrt( x )
    }

    public static Float32 rsqrt( Float32 x )
    {
        ret 1.0f / Mathf.sqrt( x + Eps )
    }

    public static Float32 pow( Float32 x, Float32 p )
    {
        ret Mathf.pow( x, p )
    }

    public static Float32 abs( Float32 x )
    {
        if x < 0.0f
        {
            ret 0.0f - x
        }
        ret x
    }

    public static Float32 sign( Float32 x )
    {
        if x > 0.0f
        {
            ret 1.0f
        }
        if x < 0.0f
        {
            ret -1.0f
        }
        ret 0.0f
    }

    public static Float32 clamp( Float32 v, Float32 lo, Float32 hi )
    {
        if v < lo
        {
            ret lo
        }
        if v > hi
        {
            ret hi
        }
        ret v
    }

    public static Float32 lerp( Float32 a, Float32 b, Float32 t )
    {
        ret a + ( b - a ) * t
    }

    public static Float32 safeDiv( Float32 a, Float32 b )
    {
        ret a / ( b + Eps )
    }

    public static bool isClose( Float32 a, Float32 b, Float32 eps )
    {
        ret TensorMath.abs( a - b ) <= eps
    }

    # ── 激活函数 ─────────────────────────────────────────
    public static Float32 sigmoid( Float32 x )
    {
        ret 1.0f / ( 1.0f + Mathf.exp( 0.0f - x ) )
    }

    # 输入为 sigmoid 的输出值
    public static Float32 sigmoidDeriv( Float32 s )
    {
        ret s * ( 1.0f - s )
    }

    public static Float32 tanh( Float32 x )
    {
        ret Mathf.tanh( x )
    }

    public static Float32 tanhDeriv( Float32 t )
    {
        ret 1.0f - t * t
    }

    public static Float32 relu( Float32 x )
    {
        if x > 0.0f
        {
            ret x
        }
        ret 0.0f
    }

    public static Float32 reluDeriv( Float32 x )
    {
        if x > 0.0f
        {
            ret 1.0f
        }
        ret 0.0f
    }

    public static Float32 leakyRelu( Float32 x, Float32 alpha )
    {
        if x > 0.0f
        {
            ret x
        }
        ret alpha * x
    }

    public static Float32 elu( Float32 x, Float32 alpha )
    {
        if x > 0.0f
        {
            ret x
        }
        ret alpha * ( Mathf.exp( x ) - 1.0f )
    }

    public static Float32 softplus( Float32 x )
    {
        # 稳定写法：x 很大时直接返回 x
        if x > 20.0f
        {
            ret x
        }
        ret Mathf.log( 1.0f + Mathf.exp( x ) )
    }

    # GELU 的 tanh 近似（Transformer 默认）
    public static Float32 gelu( Float32 x )
    {
        Float32 inner = 0.7978845608f * ( x + 0.044715f * x * x * x )
        ret 0.5f * x * ( 1.0f + Mathf.tanh( inner ) )
    }

    # SiLU / Swish
    public static Float32 silu( Float32 x )
    {
        ret x * TensorMath.sigmoid( x )
    }

    public static Float32 mish( Float32 x )
    {
        ret x * Mathf.tanh( TensorMath.softplus( x ) )
    }

    # ── 概率 / 误差函数 ──────────────────────────────────
    # erf 的 Abramowitz-Stegun 7.1.26 近似（用于 gelu 精确版、正态 CDF）
    public static Float32 erf( Float32 x )
    {
        Float32 s = TensorMath.sign( x )
        Float32 a = TensorMath.abs( x )
        Float32 t = 1.0f / ( 1.0f + 0.3275911f * a )
        Float32 y = 1.0f - ( ( ( ( 1.061405429f * t - 1.453152027f ) * t + 1.421413741f ) * t - 0.284496736f ) * t + 0.254829592f ) * t * Mathf.exp( 0.0f - a * a )
        ret s * y
    }

    public static Float32 normPdf( Float32 x, Float32 mean, Float32 std )
    {
        Float32 z = ( x - mean ) / ( std + Eps )
        ret 0.3989422804f * Mathf.exp( 0.0f - 0.5f * z * z )
    }

    public static Float32 normCdf( Float32 x, Float32 mean, Float32 std )
    {
        Float32 z = ( x - mean ) / ( std + Eps )
        ret 0.5f * ( 1.0f + TensorMath.erf( z * 0.7071067811f ) )
    }

    # log(sum(exp(v)))，带最大值平移防溢出
    public static Float32 logSumExp( Array<Float32> v )
    {
        Float32 mx = v[0]
        for i = 1, i < v.length, i++
        {
            if v[i] > mx
            {
                mx = v[i]
            }
        }
        Float32 acc = 0.0f
        for i = 0, i < v.length, i++
        {
            acc = acc + Mathf.exp( v[i] - mx )
        }
        ret mx + Mathf.log( acc )
    }

    # ── 基础算子标量补全（PyTorch 基础逐元素方法，Tensor 层配套）──

    # 1/x（0 返回 0，防炸）
    public static Float32 reciprocal( Float32 x )
    {
        if x == 0.0f
        {
            ret 0.0f
        }
        ret 1.0f / x
    }

    # x²
    public static Float32 square( Float32 x )
    {
        ret x * x
    }

    # 2^x
    public static Float32 exp2( Float32 x )
    {
        ret Mathf.exp( x * 0.6931471805599453f )
    }

    # log2(x)
    public static Float32 log2( Float32 x )
    {
        ret Mathf.log( x ) * 1.4426950408889634f
    }

    # e^x - 1（小 x 数值稳定版）
    public static Float32 expm1( Float32 x )
    {
        if x > -0.0001f && x < 0.0001f
        {
            ret x + 0.5f * x * x
        }
        ret Mathf.exp( x ) - 1.0f
    }

    # ln(1+x)（小 x 数值稳定版）
    public static Float32 log1p( Float32 x )
    {
        if x > -0.0001f && x < 0.0001f
        {
            ret x - 0.5f * x * x
        }
        ret Mathf.log( 1.0f + x )
    }

    # 浮点取余（同 C fmod / torch.fmod：结果符号随被除数。
    # 商按截断（向零取整）而非向下取整——负被除数时与
    # floor-mod（torch.remainder 语义）不同：fmod(-5,2)=-1）
    public static Float32 fmod( Float32 a, Float32 b )
    {
        if b == 0.0f
        {
            ret 0.0f
        }
        Float32 q = a / b
        Float32 t = Mathf.floor( q )
        if q < 0.0f && q != t
        {
            t = t + 1.0f
        }
        ret a - b * t
    }

    # 小数部分 x - floor(x)
    public static Float32 fract( Float32 x )
    {
        ret x - Mathf.floor( x )
    }

    # 双曲反函数（log 表达式；|x| 边界裁剪防 log(0)）
    public static Float32 asinh( Float32 x )
    {
        ret Mathf.log( x + Mathf.sqrt( x * x + 1.0f ) )
    }

    public static Float32 acosh( Float32 x )
    {
        if x < 1.0f
        {
            ret 0.0f
        }
        ret Mathf.log( x + Mathf.sqrt( x * x - 1.0f ) )
    }

    public static Float32 atanh( Float32 x )
    {
        if x <= -0.9999f || x >= 0.9999f
        {
            ret 0.0f
        }
        ret 0.5f * Mathf.log( ( 1.0f + x ) / ( 1.0f - x ) )
    }
}
