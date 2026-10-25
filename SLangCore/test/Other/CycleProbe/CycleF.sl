# 对照组：Solo 与 Helper 同文件声明，Solo -> CycleNS.A 单向引用，不构成环

import CycleNS.A

namespace Solo
{
    ClassSolo
    {
        static int s = 4
    }
}

namespace Helper
{
    ClassHelper
    {
        static int h = 5
    }
}
