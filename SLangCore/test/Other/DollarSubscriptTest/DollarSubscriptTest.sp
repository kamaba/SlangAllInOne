# DollarSubscriptTest - positive case: compile.isSupportDollarSubscript = true
# (jsonc 缺省值同为 true) keeps the obj.$name member subscript form working.
#
# Covered forms (all equivalent to their [] counterparts):
#   1. arr.$i        variable index   (== arr[i])
#   2. arr.$0        const index      (== arr[0])
#   3. arr.$1 += 5   compound assign through $-index
#   4. jag.$0.$1     chained $-index  (== jag[0][1]); mixed jag[0].$1 also OK
#   5. items.$idx.i1 user pattern var1.$i.innerVal ($-index then member)
#
# Expected: compile + run OK, printed values verified:
#   A a1=20 a2=20 a3=10 a4=25
#   B j1=2 jag[0][1]=42 j2=42
#   C write99=99 read-back=99

class DsItem
{
    i1 = 0
}

Project
{
    _main_()
    {
        int[] arr = [10, 20, 30]
        var i = 1

        # 1/2/3: variable index, const index, compound assign
        var a1 = arr.$i
        var a2 = arr[i]
        var a3 = arr.$0
        arr.$1 += 5
        SystemPrintln("A a1=" + a1.toString() + " a2=" + a2.toString() + " a3=" + a3.toString() + " a4=" + arr.$1.toString())

        # 4: chained / mixed jagged subscript
        int[2][] jag = { [1,2],[3,4] }
        var j1 = jag.$0.$1
        jag.$0.$1 = 42
        var j2 = jag[0].$1
        SystemPrintln("B j1=" + j1.toString() + " jag[0][1]=" + jag[0][1].toString() + " j2=" + j2.toString())

        # 5: var1.$i.innerVal - $-index into object array, then member access
        DsItem[] items = new(3)
        for k = 0, k < items.length
        {
            items[k] = DsItem()
            items[k].i1 = k * 10
            k += 1
        }
        var idx = 2
        items.$idx.i1 = 99
        SystemPrintln("C write99=" + items[2].i1.toString() + " read-back=" + items.$idx.i1.toString())
        SystemPrintln("D DollarSubscriptTest end")
    }
    _before_()
    {
    }
}
