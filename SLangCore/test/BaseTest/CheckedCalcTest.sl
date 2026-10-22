# ── 错误类型定义 ──
enum CheckedError extends Error
{
    Overflow = { code = 201, message = "checked-overflow" }
    NotOverflow = { code = 202, message = "should-not-happen" }
}

CheckedCalcTest
{
    # ── 1. Int32 加法溢出 ──
    static int32AddOverflowTest()
    {
        global.println("========== 1. Int32 add overflow ==========")
        string log = "before"
        label addOverflowBlock
        {
            Int32 max = 2147483647
            Int32 result = checked(max + 1)
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 2. Int32 加法不溢出 ──
    static int32AddNoOverflowTest()
    {
        global.println("========== 2. Int32 add no overflow ==========")
        string log = "before"
        label addNoOverflowBlock
        {
            Int32 a = 100
            Int32 b = 200
            Int32 result = checked(a + b)
            log = "result=" + result.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }
        global.println("log = " + log)
    }

    # ── 3. Int32 减法溢出 ──
    static int32SubOverflowTest()
    {
        global.println("========== 3. Int32 sub overflow ==========")
        string log = "before"
        label subOverflowBlock
        {
            Int32 min = -2147483648
            Int32 result = checked(min - 1)
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 4. Int32 乘法溢出 ──
    static int32MulOverflowTest()
    {
        global.println("========== 4. Int32 mul overflow ==========")
        string log = "before"
        label mulOverflowBlock
        {
            Int32 big = 2147483647
            Int32 result = checked(big * 2)
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 5. Int32 乘法不溢出 ──
    static int32MulNoOverflowTest()
    {
        global.println("========== 5. Int32 mul no overflow ==========")
        string log = "before"
        label mulNoOverflowBlock
        {
            Int32 a = 1000
            Int32 b = 1000
            Int32 result = checked(a * b)
            log = "result=" + result.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }
        global.println("log = " + log)
    }

    # ── 6. Int64 乘法溢出 ──
    static int64MulOverflowTest()
    {
        global.println("========== 6. Int64 mul overflow ==========")
        string log = "before"
        label i64MulOverflowBlock
        {
            Int64 big = 9223372036854775807
            Int64 result = checked(big * 2)
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 7. Int64 除法溢出 (MinValue / -1) ──
    static int64DivOverflowTest()
    {
        global.println("========== 7. Int64 div overflow ==========")
        string log = "before"
        Int64 minVal = -9223372036854775807 - 1
        label i64DivOverflowBlock
        {
            Int64 result = checked(minVal / -1)
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 8. Int64 取模溢出 (MinValue % -1) ──
    static int64ModOverflowTest()
    {
        global.println("========== 8. Int64 mod overflow ==========")
        string log = "before"
        Int64 minVal = -9223372036854775807 - 1
        label i64ModOverflowBlock
        {
            Int64 result = checked(minVal % -1)
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 9. Byte (UInt8) 加法溢出 (checked label 覆盖转换) ──
    static byteAddOverflowTest()
    {
        global.println("========== 9. Byte add overflow ==========")
        string log = "before"
        checked label byteOverflowBlock
        {
            Byte max = 255
            Byte result = max + 1
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 10. Int16 加法溢出 (checked label 覆盖转换) ──
    static int16AddOverflowTest()
    {
        global.println("========== 10. Int16 add overflow ==========")
        string log = "before"
        checked label i16OverflowBlock
        {
            Int16 max = 32767
            Int16 result = max + 1
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 11. 浮点运算不受 checked 影响 ──
    static floatNotAffectedTest()
    {
        global.println("========== 11. float not affected ==========")
        string log = "before"
        label floatBlock
        {
            Num a = 1.5
            Num b = 2.5
            Num result = checked(a * b)
            log = "result=" + result.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }
        global.println("log = " + log)
    }

    # ── 12. 位运算不受 checked 影响 ──
    static bitwiseNotAffectedTest()
    {
        global.println("========== 12. bitwise not affected ==========")
        string log = "before"
        label bitwiseBlock
        {
            Int32 a = 255
            Int32 b = 15
            Int32 andResult = checked(a & b)
            Int32 orResult = checked(a | b)
            Int32 xorResult = checked(a ^ b)
            log = "and=" + andResult.toString() + " or=" + orResult.toString() + " xor=" + xorResult.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }
        global.println("log = " + log)
    }

    # ── 13. 嵌套 checked 表达式 ──
    static nestedCheckedTest()
    {
        global.println("========== 13. nested checked ==========")
        string log = "before"
        label outerBlock
        {
            Int32 a = 100
            Int32 safe = checked(a + 200)
            log = "outer-safe=" + safe.toString()
            Int32 max = 2147483647
            Int32 result = checked(max + 1)
            log = log + "-inner-no-overflow"
        }
        catch
        {
            log = log + "-overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 14. 不使用 checked 时溢出不抛异常（环绕） ──
    static noCheckedNoOverflowTest()
    {
        global.println("========== 14. no checked, no throw ==========")
        string log = "before"
        label noCheckedBlock
        {
            Int32 max = 2147483647
            Int32 result = max + 1
            log = "wrapped-result=" + result.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }
        global.println("log = " + log)
    }

    # ── 15. checked 表达式中多个运算，仅一个溢出 ──
    static mixedOperationsTest()
    {
        global.println("========== 15. mixed operations ==========")
        string log = "before"
        label mixedBlock
        {
            Int32 a = 100
            Int32 b = 200
            Int32 safe1 = checked(a + b)
            log = "safe1=" + safe1.toString()
            Int32 big = 2147483647
            Int32 overflow = checked(big + 1)
            log = log + "-should-not-reach"
        }
        catch
        {
            log = log + "-overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 16. checked 块中除法正常 ──
    static checkedDivideNormalTest()
    {
        global.println("========== 16. checked divide normal ==========")
        string log = "before"
        label divNormalBlock
        {
            Int32 a = 100
            Int32 b = 7
            Int32 result = checked(a / b)
            log = "result=" + result.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }
        global.println("log = " + log)
    }

    # ── 17. checked 块中取模正常 ──
    static checkedModuloNormalTest()
    {
        global.println("========== 17. checked modulo normal ==========")
        string log = "before"
        label modNormalBlock
        {
            Int32 a = 100
            Int32 b = 7
            Int32 result = checked(a % b)
            log = "result=" + result.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }
        global.println("log = " + log)
    }

    # ── 18. UInt16 减法下溢 (checked label 覆盖转换) ──
    static uint16SubUnderflowTest()
    {
        global.println("========== 18. UInt16 sub underflow ==========")
        string log = "before"
        checked label u16UnderflowBlock
        {
            UInt16 a = 0
            UInt16 result = a - 1
            log = "no-underflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 19. checked 后恢复正常（unchecked 自动恢复） ──
    static checkedRecoveryTest()
    {
        global.println("========== 19. checked recovery ==========")
        string log = "before"
        label recoveryBlock
        {
            Int32 a = 100
            Int32 b = 200
            Int32 safe = checked(a + b)
            log = "checked-safe=" + safe.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }

        Int32 max = 2147483647
        Int32 wrapped = max + 1
        log = log + "-unchecked-wrapped=" + wrapped.toString()
        global.println("log = " + log)
    }

    # ── 20. Int32 减法溢出 (MaxValue - (-1)) ──
    static int32SubOverflowTest2()
    {
        global.println("========== 20. Int32 sub overflow (max - (-1)) ==========")
        string log = "before"
        label subOverflow2Block
        {
            Int32 max = 2147483647
            Int32 negOne = -1
            Int32 result = checked(max - negOne)
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 21. checked 表达式直接用于赋值 ──
    static checkedInAssignmentTest()
    {
        global.println("========== 21. checked in assignment ==========")
        string log = "before"
        label assignBlock
        {
            Int32 a = 2147483647
            Int32 b = checked(a + 1)
            log = "result=" + b.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 22. checked 嵌套 checked ──
    static nestedCheckedExpressTest()
    {
        global.println("========== 22. nested checked express ==========")
        string log = "before"
        label nestedBlock
        {
            Int32 a = 100
            Int32 b = 200
            Int32 result = checked(checked(a + b) + 100)
            log = "result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 23. checked label 块级 checked ──
    static checkedLabelOverflowTest()
    {
        global.println("========== 23. checked label overflow ==========")
        string log = "before"
        checked label chkOverflowBlock
        {
            Int32 max = 2147483647
            Int32 result = max + 1
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 24. checked label 无溢出 ──
    static checkedLabelNoOverflowTest()
    {
        global.println("========== 24. checked label no overflow ==========")
        string log = "before"
        checked label chkSafeBlock
        {
            Int32 a = 100
            Int32 b = 200
            Int32 result = a + b
            log = "result=" + result.toString()
        }
        catch
        {
            log = "unexpected-overflow"
        }
        global.println("log = " + log)
    }

    # ── 25. checked label + unchecked 排除 ──
    static checkedLabelWithUncheckedTest()
    {
        global.println("========== 25. checked label + unchecked ==========")
        string log = "before"
        checked label chkUncheckedBlock
        {
            Int32 max = 2147483647
            Int32 wrapped = 0
            unchecked
            {
                wrapped = max + 1
            }
            log = "unchecked-wrapped=" + wrapped.toString()
            Int32 result = max + 1
            log = log + "-checked-should-throw"
        }
        catch
        {
            log = log + "-overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 26. checked label + finally ──
    static checkedLabelWithFinallyTest()
    {
        global.println("========== 26. checked label + finally ==========")
        string log = "before"
        checked label chkFinallyBlock
        {
            Int32 max = 2147483647
            Int32 result = max * 2
            log = "no-overflow"
        }
        catch
        {
            log = log + "-catch"
        }
        finally
        {
            log = log + "-finally"
        }
        global.println("log = " + log)
    }

    # ── 27. checked label 多运算 ──
    static checkedLabelMixedTest()
    {
        global.println("========== 27. checked label mixed ==========")
        string log = "before"
        checked label chkMixedBlock
        {
            Int32 a = 100
            Int32 b = 200
            Int32 safe = a + b
            log = "safe=" + safe.toString()
            Int32 max = 2147483647
            Int32 overflow = max + 1
            log = log + "-should-not-reach"
        }
        catch
        {
            log = log + "-overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 28. checked label 内嵌套 unchecked 后恢复 checked ──
    static checkedLabelNestedUncheckedTest()
    {
        global.println("========== 28. checked label nested unchecked ==========")
        string log = "before"
        checked label chkNestedUncheckedBlock
        {
            Int32 max = 2147483647
            Int32 wrapped = 0
            unchecked
            {
                wrapped = max + 1
            }
            log = "unchecked-ok=" + wrapped.toString()
            Int32 result = max + 1
            log = log + "-should-throw"
        }
        catch
        {
            log = log + "-overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 29. 混合类型 UInt8 + Int16 溢出（checked，结果域=左操作数 UInt8） ──
    static mixUInt8Int16OverflowTest()
    {
        global.println("========== 29. UInt8 + Int16 checked overflow ==========")
        string log = "before"
        checked label mixU8I16ChkBlock
        {
            Byte a = 200
            Int16 b = 100
            Byte result = a + b
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 30. 混合类型 UInt8 + Int16 回绕（无 checked，300 -> 44） ──
    static mixUInt8Int16WrapTest()
    {
        global.println("========== 30. UInt8 + Int16 unchecked wrap ==========")
        Byte a = 200
        Int16 b = 100
        Byte result = a + b
        global.println("wrapped-result=" + result.toString())
    }

    # ── 31. SByte 加法溢出（checked）与回绕（无 checked，127+1 -> -128） ──
    static mixInt8OverflowAndWrapTest()
    {
        global.println("========== 31. SByte checked + unchecked ==========")
        string log = "before"
        checked label i8MixChkBlock
        {
            SByte max = 127
            SByte result = max + 1
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        SByte max2 = 127
        SByte wrapped = max2 + 1
        global.println("log = " + log + ", wrapped=" + wrapped.toString())
    }

    # ── 32. Int16 + UInt16 混合符号溢出（checked）与回绕 ──
    static mixInt16UInt16OverflowTest()
    {
        global.println("========== 32. Int16 + UInt16 checked overflow ==========")
        string log = "before"
        checked label i16u16MixChkBlock
        {
            Int16 a = 32767
            UInt16 b = 2
            Int16 result = a + b
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        Int16 a2 = 32767
        UInt16 b2 = 2
        Int16 wrapped = a2 + b2
        global.println("log = " + log + ", wrapped=" + wrapped.toString())
    }

    # ── 33. UInt32 + Int32 混合宽度溢出（checked）与回绕 ──
    static mixUInt32Int32OverflowTest()
    {
        global.println("========== 33. UInt32 + Int32 checked overflow ==========")
        string log = "before"
        checked label u32i32MixChkBlock
        {
            UInt32 a = 4000000000
            Int32 b = 2000000000
            UInt32 result = a + b
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        UInt32 a2 = 4000000000
        Int32 b2 = 2000000000
        UInt32 wrapped = a2 + b2
        global.println("log = " + log + ", wrapped=" + wrapped.toString())
    }

    # ── 34. UInt64 加法 64 位回绕溢出（checked）与回绕（max+1 -> 0） ──
    static mixUInt64OverflowTest()
    {
        global.println("========== 34. UInt64 checked overflow ==========")
        string log = "before"
        checked label u64MixChkBlock
        {
            UInt64 max = 18446744073709551615
            UInt64 result = max + 1
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        UInt64 max2 = 18446744073709551615
        UInt64 wrapped = max2 + 1
        global.println("log = " + log + ", wrapped=" + wrapped.toString())
    }

    # ── 35. SByte + Byte 混合符号不溢出（-1 + 2 = 1，不应误报） ──
    static mixSignedUnsignedNoOverflowTest()
    {
        global.println("========== 35. SByte + Byte no overflow ==========")
        string log = "before"
        checked label sgnu8MixChkBlock
        {
            SByte a = -1
            Byte b = 2
            SByte result = a + b
            log = "result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        global.println("log = " + log)
    }

    # ── 36. 混合类型赋宽目标（Int32 r = Byte + Int16，观察提升域） ──
    static mixPromotionToWideTest()
    {
        global.println("========== 36. Byte + Int16 promote to Int32 ==========")
        Byte a = 200
        Int16 b = 100
        Int32 result = a + b
        global.println("promoted-result=" + result.toString())
    }

    # ── 37. UInt16 + Int16 混合（无符号左操作数域，65535+1） ──
    static mixUInt16Int16OverflowTest()
    {
        global.println("========== 37. UInt16 + Int16 checked overflow ==========")
        string log = "before"
        checked label u16i16MixChkBlock
        {
            UInt16 a = 65535
            Int16 b = 1
            UInt16 result = a + b
            log = "no-overflow-result=" + result.toString()
        }
        catch
        {
            log = "overflow-caught"
        }
        UInt16 a2 = 65535
        Int16 b2 = 1
        UInt16 wrapped = a2 + b2
        global.println("log = " + log + ", wrapped=" + wrapped.toString())
    }

    # ── main entry ──
    static fun()
    {
        # 基本溢出检测
        int32AddOverflowTest()
        int32AddNoOverflowTest()
        int32SubOverflowTest()
        int32MulOverflowTest()
        int32MulNoOverflowTest()

        # Int64 溢出
        int64MulOverflowTest()
        int64DivOverflowTest()
        int64ModOverflowTest()

        # 窄类型溢出
        byteAddOverflowTest()
        int16AddOverflowTest()

        # 不受 checked 影响
        floatNotAffectedTest()
        bitwiseNotAffectedTest()

        # 嵌套和恢复
        nestedCheckedTest()
        noCheckedNoOverflowTest()
        mixedOperationsTest()
        checkedRecoveryTest()

        # 正常运算
        checkedDivideNormalTest()
        checkedModuloNormalTest()

        # 无符号下溢
        uint16SubUnderflowTest()

        # 减法溢出变体
        int32SubOverflowTest2()

        # 表达式用法
        checkedInAssignmentTest()
        nestedCheckedExpressTest()

        # checked label 块级 + unchecked
        checkedLabelOverflowTest()
        checkedLabelNoOverflowTest()
        checkedLabelWithUncheckedTest()
        checkedLabelWithFinallyTest()
        checkedLabelMixedTest()
        checkedLabelNestedUncheckedTest()

        # 混合类型提升（uint8+int16 等，无 checked 回绕 / 有 checked 报溢出）
        mixUInt8Int16OverflowTest()
        mixUInt8Int16WrapTest()
        mixInt8OverflowAndWrapTest()
        mixInt16UInt16OverflowTest()
        mixUInt32Int32OverflowTest()
        mixUInt64OverflowTest()
        mixSignedUnsignedNoOverflowTest()
        mixPromotionToWideTest()
        mixUInt16Int16OverflowTest()

        global.println("========== all checked calc tests done ==========")
    }
}
