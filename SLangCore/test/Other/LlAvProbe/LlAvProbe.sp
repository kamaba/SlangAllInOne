# LlAvProbe - AccessViolation crash probe: isolate the exact crashing call of
# LinkedListTest.testAddFirstLast (ExpendTest) in a minimal context.
# Breadcrumb after each step; the crash point = between last visible print and the next.
import Core;

Project
{
    _main_()
    {
        SystemPrintln("P0: before new")
        Core.LinkedList<int> list = new()
        SystemPrintln("P1: new() ok")
        list.addLast(2)
        SystemPrintln("P2: addLast(2) ok")
        list.addLast(3)
        SystemPrintln("P3: addLast(3) ok")
        list.addFirst(1)
        SystemPrintln("P4: addFirst(1) ok")
        list.addFirst(0)
        SystemPrintln("P5: addFirst(0) ok")
        SystemPrintln("P6: length = " + list.length)
        SystemPrintln("P7: toString = " + list.toString())
        SystemPrintln("P8: first = " + list.first)
        SystemPrintln("P9: last = " + list.last)
        SystemPrintln("P10: probe done")
    }
    _before_()
    {
    }
}
