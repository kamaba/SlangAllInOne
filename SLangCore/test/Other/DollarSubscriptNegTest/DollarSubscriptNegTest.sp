# DollarSubscriptNegTest - negative case: compile.isSupportDollarSubscript = false
# rejects the obj.$name member subscript form at FrontEnd TokenParse,
# while the [] form stays allowed.
#
# Expected: compile FAILS.
#   4 errors LID 20121 (TokenParseDollarSubscriptDisabled):
#     neg1: var a1 = arr.$i     (variable index via $)
#     neg2: var a2 = arr.$0     (const index via $)
#     neg3: arr.$1 += 5         (compound-assign target via $)
#     neg4: var b1 = arr.$"key" (string-key form; previously crashed with
#                                confusing LID 11028 visitType=ConstValue)
#   1 error LID 20117 (TokenParseNodeIssue2), switch-independent pre-existing rule:
#     neg5: var c1 = $x         (standalone $ without preceding '.')
#   The [] forms (arr[i] / arr[0]) trigger nothing.
#   No DollarSubscriptNegTest.module.json is produced.
Project
{
    _main_()
    {
        int[] arr = [10, 20, 30]
        var i = 1
        var a1 = arr.$i                      # neg1: variable index via $
        var a2 = arr.$0                      # neg2: const index via $
        arr.$1 += 5                          # neg3: compound-assign target via $
        var a3 = arr[i]                      # [] allowed: no error
        var a4 = arr[0]                      # [] allowed: no error
        var b1 = arr.$"key"                 # neg4: string-key form
        var c1 = $x                          # neg5: standalone $ (20117)
        SystemPrintln("never runs")
    }
    _before_()
    {
    }
}
