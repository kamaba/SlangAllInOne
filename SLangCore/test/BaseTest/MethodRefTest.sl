# MethodRefTest.sl - 方法引用特性验证（NewMethodRef opcode = 125）
# 覆盖: 静态方法引用 / 实例方法引用(receiver 捕获与状态联动) / this 引用 /
#       继承覆写后按 receiver 运行时类重分派 / 作为参数传递 / forEach 回调 / 作为返回值

namespace NSMethodRefTest
{
    # 被引用方法宿主: 静态 + 实例 + 可覆写
    MethodRefDemo
    {
        static int staticAdd( int a, int b )
        {
            ret a + b;
        }

        int m_base = 0;

        _init_( int b )
        {
            this.m_base = b;
        }

        int instanceAdd( int a, int b )
        {
            ret a + b + this.m_base;
        }

        int bump( int step )
        {
            this.m_base = this.m_base + step;
            ret this.m_base;
        }

        string describe()
        {
            ret "MethodRefDemo base=" + this.m_base.toString();
        }

        static printer( int item )
        {
            global.println( "forEach item = " + item.toString() );
        }
    }

    # 覆写子类: 构造放大 base + describe 覆写
    LoudDemo extends MethodRefDemo
    {
        override _init_( int b )
        {
            base._init_( b * 10 );
        }

        override string describe()
        {
            ret "LoudDemo[Loud] " + base.describe();
        }
    }

    # 测试驱动
    MethodRefTest
    {
        # 案例1: 静态方法引用 ( Class.staticFn -> 函数值 )
        static staticRefCase()
        {
            var f = MethodRefDemo.staticAdd;
            global.println( "staticAdd(3,4) = " + f(3, 4).toString() );
            global.println( "staticAdd(10,20) = " + f(10, 20).toString() );
        }

        # 案例2: 实例方法引用 ( obj.instanceFn -> receiver 捕获, 多次调用状态联动 )
        static receiverCase()
        {
            var d = MethodRefDemo( 100 );
            var addFn = d.instanceAdd;
            global.println( "instanceAdd(2,3) = " + addFn(2, 3).toString() );

            var bumpFn = d.bump;
            global.println( "bump(5) = " + bumpFn(5).toString() );
            global.println( "bump(7) = " + bumpFn(7).toString() );
            global.println( "after bumps, d.describe() = " + d.describe() );
        }

        # 案例3: this 实例方法引用 ( this.instanceFn )
        int m_val = 0;

        int twicePlus( int x )
        {
            ret x * 2 + this.m_val;
        }

        thisRefCase()
        {
            this.m_val = 50;
            var f = this.twicePlus;
            global.println( "twicePlus(3) = " + f(3).toString() );
        }

        # 案例4: 继承覆写后按 receiver 运行时类重分派
        static virtualRefCase()
        {
            var loud = LoudDemo( 3 );
            var lf = loud.describe;
            global.println( "loud ref = " + lf().toString() );

            var plain = MethodRefDemo( 3 );
            var pf = plain.describe;
            global.println( "plain ref = " + pf().toString() );
        }

        # 案例5: 方法引用作为参数 ( 静态 / 实例 / 匿名闭包 三来源同参 )
        static callWith( Function f, int a, int b )
        {
            global.println( "callWith = " + f(a, b).toString() );
        }

        static paramCase()
        {
            callWith( MethodRefDemo.staticAdd, 2, 3 );

            var d = MethodRefDemo( 10 );
            callWith( d.instanceAdd, 2, 3 );

            var mul = function( int a, int b )
            {
                ret a * b;
            };
            callWith( mul, 4, 5 );
        }

        # 案例6: Array.forEach + 静态方法引用回调
        static forEachCase()
        {
            Array<int> arr = [1, 2, 3];
            arr.forEach( MethodRefDemo.printer );
        }

        # 案例7: 方法引用作为返回值
        static Function getAdder()
        {
            ret MethodRefDemo.staticAdd;
        }

        static returnRefCase()
        {
            var f = getAdder();
            global.println( "getAdder()(5,6) = " + f(5, 6).toString() );
        }

        static fun()
        {
            global.println( "========== MethodRefTest (start) ==========" );
            staticRefCase();
            receiverCase();
            var t = MethodRefTest();
            t.thisRefCase();
            virtualRefCase();
            paramCase();
            forEachCase();
            returnRefCase();
            global.println( "========== MethodRefTest (end) ==========" );
        }
    }
}
