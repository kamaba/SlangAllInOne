# CoreAutoProbe - Core 自动导入探针（2026-10-18 用户规则）
# 验证点：
#   1. Core 自动导入：全程不写 import Core，Core 基础类型/容器
#      （List/Map/string）零 import 直接可用；
#   2. import Core:Environment 命名空间直达：current.osName 等
#      Environment 命名空间成员无前缀直接搜索；
#   3. 全程不 import Std（本工程 references 只声明 Core）。

import Core:Environment

CoreAutoProbeTests
{
    static run()
    {
        global.println( "===== CoreAutoProbe start =====" )
        coreAutoImportTest()
        coreNamespaceDirectTest()
        global.println( "===== CoreAutoProbe end =====" )
    }

    # Core 自动导入：基础类型/容器零 import 直接可用
    static coreAutoImportTest()
    {
        global.println( "----- core auto import (no import Core) -----" )

        List<int> l = List<int>()
        l.add( 1 )
        l.add( 2 )
        l.add( 3 )
        global.println( "List length = " + l.length.toString() )
        global.println( "List[2] = " + l[2].toString() )

        Map<string, int> m = Map<string, int>()
        m.add( "a", 1 )
        m.add( "b", 2 )
        global.println( "Map[b] = " + m._getItem_( "b" ).toString() )

        string s = "hello core"
        global.println( "string length = " + s.length.toString() )
        global.println( "string + int = " + s + " " + 42 )

        int n = 7
        global.println( "int.toString = " + n.toString() )
        global.println( "int compute = " + ( n * 6 ).toString() )
    }

    # import Core:Environment 命名空间直达：成员无前缀直接搜索
    static coreNamespaceDirectTest()
    {
        global.println( "----- import Core:Environment direct -----" )
        global.println( "current.osName = " + current.osName )
        global.println( "current.os = " + current.os.toString() )
        global.println( "current.archBits = " + current.archBits.toString() )
        global.println( "current.form = " + current.form.toString() )
    }
}
