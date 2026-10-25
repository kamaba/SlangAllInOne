# CycleNS.A <-> CycleNS.B：两节点循环引用

import CycleNS.B

namespace CycleNS.A
{
    ClassA
    {
        static int a = 1
    }
}
