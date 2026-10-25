# ── 数值类型提升（计算升级）矩阵验证探针 ──
# BaseTest 套件副本：源文件 test\Other\PromotionProbe\PromotionProbe.sl（独立可跑工程）。
# 验证 MetaTypeFactory.CalcETypeByLeftAndRight 的提升规则（每条用例同时校验结果类型与结果值）：
#   - 小整型混算向大侧靠：UInt8+Int8→Int16、UInt8+Int16→Int16、UInt8+UInt16→UInt16
#   - 同宽度有/无符号混合升为更大有符号：Int8+UInt16→Int32、Int16+UInt16→Int32、Int32+UInt32→Int64
#   - 任一侧浮点则升浮点：Float32 吃掉全部整型（Int64/UInt64 除外→Float64），Float64 吃掉一切
#   - Int64+UInt64 → 编译期报错（error=2），不出现在用例中
#   - 低精度浮点：同型保持；跨格式（fe4/fe5、h/hb）升 Float32；遇小整型保持低精度；
#     遇 Int64/UInt64/Float32 升 Float32；遇 Float64 升 Float64
#   - Num 抽象数值：结果仍为 Num
PromotionProbe
{
    # 断言辅助：结果类型与值都符合预期才 OK
    static verify( string name, string actualType, string actualVal, string expectType, string expectVal )
    {
        bool ok = actualType == expectType && actualVal == expectVal
        if ok
        {
            global.println( "[Promo] " + name + " : OK   (" + actualType + " " + actualVal + ")" )
        }
        else
        {
            global.println( "[Promo] " + name + " : FAIL (got " + actualType + " " + actualVal + ", expect " + expectType + " " + expectVal + ")" )
            PromoStat.bump()
        }
    }

    # 只校验值（用于 bool 结果，类型固定 Boolean 不参与断言）
    static verifyVal( string name, string actualVal, string expectVal )
    {
        bool ok = actualVal == expectVal
        if ok
        {
            global.println( "[Promo] " + name + " : OK   (" + actualVal + ")" )
        }
        else
        {
            global.println( "[Promo] " + name + " : FAIL (got " + actualVal + ", expect " + expectVal + ")" )
            PromoStat.bump()
        }
    }

    # ── 1. 标准十类型两两相加矩阵（UInt8..Float64）──
    static matrixTest()
    {
        global.println( "========== 1. promotion matrix (+) ==========" )

        # 各类型基础变量（大值：验证结果宽度足够、不丢高位）
        Byte    u8   = 200
        SByte   s8   = -100
        Int16   i16  = 30000
        UInt16  u16  = 60000
        Int32   i32  = 2000000000
        UInt32  u32  = 4000000000
        Int64   i64  = 5000000000
        UInt64  u64  = 10000000000
        Float32 f32  = 1.5
        Float64 f64  = 2.25
        # 小值变量（保证浮点期望值可精确表示）
        Int32   i32s = 1500
        Int64   i64s = 2500
        UInt32  u32s = 3500
        UInt64  u64s = 4500

        # A. UInt8 左侧
        rA1 = u8 + s8
        verify( "A1  u8+s8 ", rA1.type.toString(), rA1.toString(), "Int16", "100" )
        rA2 = u8 + i16
        verify( "A2  u8+i16", rA2.type.toString(), rA2.toString(), "Int16", "30200" )
        rA3 = u8 + u16
        verify( "A3  u8+u16", rA3.type.toString(), rA3.toString(), "UInt16", "60200" )
        rA4 = u8 + i32
        verify( "A4  u8+i32", rA4.type.toString(), rA4.toString(), "Int32", "2000000200" )
        rA5 = u8 + u32
        verify( "A5  u8+u32", rA5.type.toString(), rA5.toString(), "UInt32", "4000000200" )
        rA6 = u8 + i64
        verify( "A6  u8+i64", rA6.type.toString(), rA6.toString(), "Int64", "5000000200" )
        rA7 = u8 + u64
        verify( "A7  u8+u64", rA7.type.toString(), rA7.toString(), "UInt64", "10000000200" )
        rA8 = u8 + f32
        verify( "A8  u8+f32", rA8.type.toString(), rA8.toString(), "Float32", "201.5" )
        rA9 = u8 + f64
        verify( "A9  u8+f64", rA9.type.toString(), rA9.toString(), "Float64", "202.25" )

        # B. SByte 左侧（含负数跨无符号：重点验证符号扩展是否正确）
        rB1 = s8 + i16
        verify( "B1  s8+i16", rB1.type.toString(), rB1.toString(), "Int16", "29900" )
        rB2 = s8 + u16
        verify( "B2  s8+u16", rB2.type.toString(), rB2.toString(), "Int32", "59900" )
        rB3 = s8 + i32
        verify( "B3  s8+i32", rB3.type.toString(), rB3.toString(), "Int32", "1999999900" )
        rB4 = s8 + u32
        verify( "B4  s8+u32", rB4.type.toString(), rB4.toString(), "UInt32", "3999999900" )
        rB5 = s8 + i64
        verify( "B5  s8+i64", rB5.type.toString(), rB5.toString(), "Int64", "4999999900" )
        rB6 = s8 + u64
        verify( "B6  s8+u64", rB6.type.toString(), rB6.toString(), "UInt64", "9999999900" )
        rB7 = s8 + f32
        verify( "B7  s8+f32", rB7.type.toString(), rB7.toString(), "Float32", "-98.5" )
        rB8 = s8 + f64
        verify( "B8  s8+f64", rB8.type.toString(), rB8.toString(), "Float64", "-97.75" )

        # C. Int16 左侧
        rC1 = i16 + u16
        verify( "C1  i16+u16", rC1.type.toString(), rC1.toString(), "Int32", "90000" )
        rC2 = i16 + i32
        verify( "C2  i16+i32", rC2.type.toString(), rC2.toString(), "Int32", "2000030000" )
        rC3 = i16 + u32
        verify( "C3  i16+u32", rC3.type.toString(), rC3.toString(), "UInt32", "4000030000" )
        rC4 = i16 + i64
        verify( "C4  i16+i64", rC4.type.toString(), rC4.toString(), "Int64", "5000030000" )
        rC5 = i16 + u64
        verify( "C5  i16+u64", rC5.type.toString(), rC5.toString(), "UInt64", "10000030000" )
        rC6 = i16 + f32
        verify( "C6  i16+f32", rC6.type.toString(), rC6.toString(), "Float32", "30001.5" )
        rC7 = i16 + f64
        verify( "C7  i16+f64", rC7.type.toString(), rC7.toString(), "Float64", "30002.25" )

        # D. UInt16 左侧
        rD1 = u16 + i32
        verify( "D1  u16+i32", rD1.type.toString(), rD1.toString(), "Int32", "2000060000" )
        rD2 = u16 + u32
        verify( "D2  u16+u32", rD2.type.toString(), rD2.toString(), "UInt32", "4000060000" )
        rD3 = u16 + i64
        verify( "D3  u16+i64", rD3.type.toString(), rD3.toString(), "Int64", "5000060000" )
        rD4 = u16 + u64
        verify( "D4  u16+u64", rD4.type.toString(), rD4.toString(), "UInt64", "10000060000" )
        rD5 = u16 + f32
        verify( "D5  u16+f32", rD5.type.toString(), rD5.toString(), "Float32", "60001.5" )
        rD6 = u16 + f64
        verify( "D6  u16+f64", rD6.type.toString(), rD6.toString(), "Float64", "60002.25" )

        # E. Int32 左侧
        rE1 = i32 + u32
        verify( "E1  i32+u32", rE1.type.toString(), rE1.toString(), "Int64", "6000000000" )
        rE2 = i32 + i64
        verify( "E2  i32+i64", rE2.type.toString(), rE2.toString(), "Int64", "7000000000" )
        rE3 = i32 + u64
        verify( "E3  i32+u64", rE3.type.toString(), rE3.toString(), "UInt64", "12000000000" )
        rE4 = i32s + f32
        verify( "E4  i32+f32", rE4.type.toString(), rE4.toString(), "Float32", "1501.5" )
        rE5 = i32s + f64
        verify( "E5  i32+f64", rE5.type.toString(), rE5.toString(), "Float64", "1502.25" )

        # F. UInt32 左侧
        rF1 = u32 + i64
        verify( "F1  u32+i64", rF1.type.toString(), rF1.toString(), "Int64", "9000000000" )
        rF2 = u32 + u64
        verify( "F2  u32+u64", rF2.type.toString(), rF2.toString(), "UInt64", "14000000000" )
        rF3 = u32s + f32
        verify( "F3  u32+f32", rF3.type.toString(), rF3.toString(), "Float32", "3501.5" )
        rF4 = u32s + f64
        verify( "F4  u32+f64", rF4.type.toString(), rF4.toString(), "Float64", "3502.25" )

        # G. Int64 左侧（i64+u64 编译期报错 error=2，不进用例）
        rG1 = i64s + f32
        verify( "G1  i64+f32", rG1.type.toString(), rG1.toString(), "Float64", "2501.5" )
        rG2 = i64s + f64
        verify( "G2  i64+f64", rG2.type.toString(), rG2.toString(), "Float64", "2502.25" )

        # H. UInt64 左侧
        rH1 = u64s + f32
        verify( "H1  u64+f32", rH1.type.toString(), rH1.toString(), "Float64", "4501.5" )
        rH2 = u64s + f64
        verify( "H2  u64+f64", rH2.type.toString(), rH2.toString(), "Float64", "4502.25" )

        # I. Float32 左侧
        rI1 = f32 + f64
        verify( "I1  f32+f64", rI1.type.toString(), rI1.toString(), "Float64", "3.75" )
    }

    # ── 2. 低精度浮点（Float8/Float8_E5M2/Float16/Float16_Brain）提升 ──
    static lowFloatTest()
    {
        global.println( "========== 2. low-float promotion ==========" )

        Float8        lf8  = 2.5fe4
        Float8_E5M2   lf85 = 1.5fe5
        Float16       lf16 = 2.5h
        Float16_Brain lfb  = 3.5hb
        Int32 i32t = 3
        Byte  u8t  = 5
        Int64 i64t = 2500

        # 同型保持
        rJ1 = lf8 + lf8
        verify( "J1  fe4+fe4", rJ1.type.toString(), rJ1.toString(), "Float8", "5" )
        # 跨格式升 Float32
        rJ2 = lf8 + lf85
        verify( "J2  fe4+fe5", rJ2.type.toString(), rJ2.toString(), "Float32", "4" )
        rJ3 = lf16 + lfb
        verify( "J3  h+hb   ", rJ3.type.toString(), rJ3.toString(), "Float32", "6" )
        # 低精度 + 小整型保持低精度
        rJ4 = lf8 + i32t
        verify( "J4  fe4+i32", rJ4.type.toString(), rJ4.toString(), "Float8", "5.5" )
        rJ5 = lf8 + u8t
        verify( "J5  fe4+u8 ", rJ5.type.toString(), rJ5.toString(), "Float8", "7.5" )
        # 低精度 + Int64 升 Float32
        rJ6 = lf16 + i64t
        verify( "J6  h+i64 ", rJ6.type.toString(), rJ6.toString(), "Float32", "2502.5" )
        # 低精度 + Float32 升 Float32
        rJ7 = lf16 + 1.5f
        verify( "J7  h+f32 ", rJ7.type.toString(), rJ7.toString(), "Float32", "4" )
        # 低精度 + Float64 升 Float64
        rJ8 = lf16 + 2.25d
        verify( "J8  h+f64 ", rJ8.type.toString(), rJ8.toString(), "Float64", "4.75" )
    }

    # ── 3. 混合类型下的 - * / % 与位运算 ──
    static operatorTest()
    {
        global.println( "========== 3. mixed operators (- * / % & | ^ << >>) ==========" )

        Byte    u8   = 200
        SByte   s8   = -100
        Int16   i16  = 30000
        UInt16  u16  = 60000
        Int32   i32  = 2000000000
        UInt32  u32  = 4000000000
        Int64   i64  = 5000000000
        Float32 f32  = 1.5
        Float64 f64  = 2.25
        Int64   i64s = 2500
        # 运算专用小值变量（避免中间溢出/精度损失）
        Byte    u8m   = 100
        Int16   i16m  = 300
        Int32   i32m  = 2000000
        UInt32  u32m  = 2000000
        Float64 f64k  = 900.0d
        UInt16  u16k  = 600
        Byte    u8k   = 225
        Int64   i64mo = 5000000008
        Byte    u8mo  = 250
        UInt16  u16mo = 60005
        Int16   i16mo = 30000
        Byte    u8b   = 240
        Int16   i16b  = 15
        UInt16  u16b  = 65280
        Int32   i32b  = 4080
        Int32   i32x  = 255
        Byte    u8x   = 240
        Int32   i32s  = 1
        Byte    u8s   = 8
        UInt16  u16s  = 1
        SByte   s8s   = 4

        # 减法
        rK1 = u8 - s8
        verify( "K1  u8-s8  ", rK1.type.toString(), rK1.toString(), "Int16", "300" )
        rK2 = i32 - u32
        verify( "K2  i32-u32", rK2.type.toString(), rK2.toString(), "Int64", "-2000000000" )
        rK3 = u16 - i16
        verify( "K3  u16-i16", rK3.type.toString(), rK3.toString(), "Int32", "30000" )
        rK4 = f64 - u8
        verify( "K4  f64-u8 ", rK4.type.toString(), rK4.toString(), "Float64", "-197.75" )
        rK5 = i64s - f32
        verify( "K5  i64-f32", rK5.type.toString(), rK5.toString(), "Float64", "2498.5" )
        # 乘法
        rK6 = u8m * i16m
        verify( "K6  u8*i16 ", rK6.type.toString(), rK6.toString(), "Int16", "30000" )
        rK7 = i16 * u16
        verify( "K7  i16*u16", rK7.type.toString(), rK7.toString(), "Int32", "1800000000" )
        rK8 = i32m * u32m
        verify( "K8  i32*u32", rK8.type.toString(), rK8.toString(), "Int64", "4000000000000" )
        rK9 = u8m * f32
        verify( "K9  u8*f32 ", rK9.type.toString(), rK9.toString(), "Float32", "150" )
        rK10 = i64s * f64
        verify( "K10 i64*f64", rK10.type.toString(), rK10.toString(), "Float64", "5625" )
        # 除法
        rK11 = i64 / u8
        verify( "K11 i64/u8 ", rK11.type.toString(), rK11.toString(), "Int64", "25000000" )
        rK12 = u16 / i16
        verify( "K12 u16/i16", rK12.type.toString(), rK12.toString(), "Int32", "2" )
        rK13 = f64k / u16k
        verify( "K13 f64/u16", rK13.type.toString(), rK13.toString(), "Float64", "1.5" )
        rK14 = u8k / f32
        verify( "K14 u8/f32 ", rK14.type.toString(), rK14.toString(), "Float32", "150" )
        # 取模
        rK15 = i64mo % u8mo
        verify( "K15 i64%u8 ", rK15.type.toString(), rK15.toString(), "Int64", "8" )
        rK16 = u16mo % i16mo
        verify( "K16 u16%i16", rK16.type.toString(), rK16.toString(), "Int32", "5" )
        # 位运算
        rK17 = u8b | i16b
        verify( "K17 u8|i16 ", rK17.type.toString(), rK17.toString(), "Int16", "255" )
        rK18 = u16b & i32b
        verify( "K18 u16&i32", rK18.type.toString(), rK18.toString(), "Int32", "3840" )
        rK19 = i32x ^ u8x
        verify( "K19 i32^u8 ", rK19.type.toString(), rK19.toString(), "Int32", "15" )
        rK20 = u16b | u8b
        verify( "K20 u16|u8 ", rK20.type.toString(), rK20.toString(), "Int32", "65520" )
        # 移位
        rK21 = i32s << u8s
        verify( "K21 i32<<u8", rK21.type.toString(), rK21.toString(), "Int32", "256" )
        rK22 = u16s << s8s
        verify( "K22 u16<<s8", rK22.type.toString(), rK22.toString(), "Int32", "16" )
    }

    # ── 4. 链式提升与赋值目标类型 ──
    static chainTest()
    {
        global.println( "========== 4. chained promotion & typed assignment ==========" )

        Byte    u8  = 200
        SByte   s8  = -100
        Int16   i16 = 30000
        UInt16  u16 = 60000
        Int32   i32 = 2000000000
        UInt32  u32 = 4000000000
        Int64   i64 = 5000000000
        Float32 f32 = 1.5
        Float64 f64 = 2.25
        Int32   i32s = 1500
        Int64   i64s = 2500

        # 逐级链式提升：Int16 -> UInt32
        rL1 = u8 + i16 + u32
        verify( "L1  u8+i16+u32      ", rL1.type.toString(), rL1.toString(), "UInt32", "4000030200" )
        # Int32 -> Int64
        rL2 = s8 + u16 + i64
        verify( "L2  s8+u16+i64      ", rL2.type.toString(), rL2.toString(), "Int64", "5000059900" )
        # Int64 -> Float64
        rL3 = i32 + u32 + f64
        verify( "L3  i32+u32+f64     ", rL3.type.toString(), rL3.toString(), "Float64", "6000000002.25" )
        # 先乘后加：u16*i16 -> Int32，再 + u8 -> Int32
        rL4 = u8 + u16 * i16
        verify( "L4  u8+u16*i16      ", rL4.type.toString(), rL4.toString(), "Int32", "1800000200" )

        # 显式类型变量承接提升结果
        Int16 t1 = u8 + i16
        verify( "L5  Int16 t = u8+i16", t1.type.toString(), t1.toString(), "Int16", "30200" )
        Int64 t2 = i32 + u32
        verify( "L6  Int64 t = i32+u32", t2.type.toString(), t2.toString(), "Int64", "6000000000" )
        Float64 t3 = i64s + f32
        verify( "L7  F64 t = i64+f32 ", t3.type.toString(), t3.toString(), "Float64", "2501.5" )
        # Float32 结果隐式加宽进 Float64 变量（赋值侧转换）
        Float64 t4 = i32s + f32
        verify( "L8  F64 t = i32+f32 ", t4.type.toString(), t4.toString(), "Float64", "1501.5" )
    }

    # ── 5. Num 抽象类型与跨类型比较 ──
    static numAndCompareTest()
    {
        global.println( "========== 5. Num & cross-type compare ==========" )

        Byte    u8  = 200
        Int16   i16 = 30000
        Int32   i32 = 2000000000
        UInt32  u32 = 4000000000
        UInt16  u16 = 60000
        SByte   s8  = -100
        Int64   i64s = 2500
        Float32 f32 = 1.5
        Float64 f64 = 2.25
        Float8  lf8 = 2.5fe4
        Num nm = 2.5

        # Num 参与运算：编译期结果类型为 Num；运行时 Num 无独立栈槽（栈层降格为
        # FLOAT64 槽），.type 读取经栈往返后报 Float64 —— 既有架构行为
        rM1 = nm + u8
        verify( "M1  Num+u8 ", rM1.type.toString(), rM1.toString(), "Float64", "202.5" )
        rM2 = i64s + nm
        verify( "M2  i64+Num", rM2.type.toString(), rM2.toString(), "Float64", "2502.5" )

        # 跨类型比较（结果 bool）
        rN1 = u8 > s8
        verifyVal( "N1  u8>s8    ", rN1.toString(), "True" )
        rN2 = i32 == u32
        verifyVal( "N2  i32==u32 ", rN2.toString(), "False" )
        rN3 = f64 >= i64s
        verifyVal( "N3  f64>=i64 ", rN3.toString(), "False" )
        rN4 = u16 < i32
        verifyVal( "N4  u16<i32  ", rN4.toString(), "True" )
        rN5 = lf8 < f32
        verifyVal( "N5  fe4<f32  ", rN5.toString(), "False" )
    }

    static run()
    {
        global.println( "========== PromotionProbe (start) ==========" )
        matrixTest()
        lowFloatTest()
        operatorTest()
        chainTest()
        numAndCompareTest()
        if PromoStat.fails == 0
        {
            global.println( "========== PromotionProbe : ALL CHECKS PASSED ==========" )
        }
        else
        {
            global.println( "========== PromotionProbe : " + PromoStat.fails.toString() + " CHECK(S) FAILED ==========" )
        }
    }
}

# 失败计数（供 summary 汇总）
class PromoStat
{
    public static Int32 fails = 0

    public static bump()
    {
        fails = fails + 1
    }
}
