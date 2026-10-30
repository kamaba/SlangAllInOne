# BlankLineProbe - behavior probe for jsonc "compile"."isForceBlankLineBetweenIfs"
# Pair A: two adjacent ifs with NO blank line between them.
#   Default config (key absent/false): no 20288 (check disabled).
#   Key = true: one Info 20288 (NodeStructParseIfNextNoBlankLine).
# Pair B (control): blank line before the if, must never trigger 20288.
class BlankLineProbe
{
    public static void runTest()
    {
        var a = 1
        if (a > 0)
        {
            a = 2
        }
        if (a > 1)
        {
            a = 3
        }

        if (a > 2)
        {
            a = 4
        }
    }
}
