import Core;
import Std;

# 探针：0 参方法引用修复验证 + 三形态函数值（多行语句风格）
class Probe
{
    static void a0() { Console.println( "  a0() called" ) }
    static void a1( Int64 e ) { Console.println( "  a1(e=" + e + ") called" ) }
    static Int64 z0() { Console.println( "  z0() called" )  ret 5 }

    class CA
    {
        Int64 tag = 9
        void ttt() { Console.println( "  ca.ttt() called tag=" + this.tag ) }
        void ttt1( Int64 e ) { Console.println( "  ca.ttt1(e=" + e + ") tag=" + this.tag ) }
    }

    static Int64 callF( Function f )
    {
        f( 7 )
        ret 0
    }

    static void callV( Function f, Int64 e )
    {
        f( e )
    }

    static void main()
    {
        Console.println( "[T1] 0 参有返回值静态引用直接传参" )
        callF( Probe.z0 )
        Console.println( "  T1 ok" )

        Console.println( "[T2] 0 参 void 静态引用直接传参" )
        callF( Probe.a0 )
        Console.println( "  T2 ok" )

        Console.println( "[T3] 1 参静态引用直接传参" )
        callF( Probe.a1 )
        Console.println( "  T3 ok" )

        Console.println( "[T4] 0 参实例方法引用直接传参" )
        CA ca = CA()
        callF( ca.ttt )
        Console.println( "  T4 ok" )

        Console.println( "[T5] 1 参实例方法引用直接传参" )
        callV( ca.ttt1, 66 )

        Console.println( "[T6] 0 参匿名闭包直接传参" )
        callF( function()
        {
            Console.println( "  anon0() called" );
        } )
        Console.println( "  T6 ok" )

        Console.println( "[probe] all done" )
    }
}
