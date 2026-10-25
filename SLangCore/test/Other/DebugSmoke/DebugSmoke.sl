import Std;

class Point
{
    int x = 1
    int y = 2
}

class Box
{
    Point p = Point()
    Array<int> nums = Array<int>(4)
    int tag = 7
}
class DebugSmoke
{
    static int counter = 10
    static string note = "demo"

    int add( int a, int b )
    {
        int s = a + b
        ret s
    }

    int triple( int x )
    {
        int inner = this.add( x, x )
        int t = this.add( x, inner )
        ret t
    }

    int deepA( int n )
    {
        int r = this.deepB( n + 1 )
        ret r
    }

    int deepB( int n )
    {
        int r = this.deepC( n + 1 )
        ret r
    }

    int deepC( int n )
    {
        int r = this.add( n, 100 )
        ret r
    }

    static int coroBody( int v )
    {
        int lv = v * 2
        ret lv
    }

    static void run()
    {
        # 调试走查用例: 断点/单步/变量/监视/调用堆栈 (DEBUG_PROTOCOL_DESIGN §8.4)
        # Watch 面板建议表达式: a + b / pt.x + arr[1] / pts[0].y / box.tag
        #   / arr[1] * 2 / pi * 2 / msg / a < b / counter / m
        #   / dv.x / dw.inner.z / dvs[0].y
        DebugSmoke d = DebugSmoke()
        int a = 3
        int b = 4
        int c = d.triple( a + b )
        double pi = 3.14
        bool flag = true
        string msg = "hi"
        Point pt = Point()
        pt.x = 41
        pt.y = 43
        Array<int> arr = Array<int>(3)
        arr[0] = 10
        arr[1] = 20
        arr[2] = 30
        Array<Point> pts = Array<Point>(2)
        pts[0] = pt
        pts[1] = Point()
        Box box = Box()
        box.tag = 99
        Map<int, int> m = Map<int, int>()
        m.add( 1, 100 )
        m.add( 2, 200 )
        Vec3 dv = Vec3(){ x = 7, y = 8, z = 9 }
        Wrap dw = Wrap(){ name = "ww", inner = Vec3(){ x = 5, y = 6, z = 7 } }
        Array<Vec3> dvs = Array<Vec3>(2)
        dvs[0] = dv
        int deep = d.deepA( 5 )
        int sum = pts[0].x + arr[1]
        Task h = spawn coroBody( c )
        int r = await h as int
        counter = counter + c + r + sum + deep
        Console.println( "result=" + SystemConvertString( counter ) )
    }
}

data Vec3
{
    x = 1
    y = 2
    z = 3
}

data Wrap
{
    inner = Vec3(){ x = 5, y = 6, z = 7 }
    name = "w"
}
