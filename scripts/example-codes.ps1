# example-codes.ps1 - fixed run-page example candidates (Playground.runMain form).
# Dot-sourced by run-website-examples.ps1 -Local. Each: slug -> @{ Code; Expected }.
# Fix policy (user directive): example code adapts to the website pipeline; the
# pipeline (planRun/compile/wasmRunner) and the compiler stay untouched.
#
# Why these forms:
#  - Project{...} entry examples broke: api/compile.ts always writes a Playground.sp
#    whose Project wrapper would duplicate the example's own Project class.
#  - Class-def-only examples broke: planRun auto-wraps bare statements into runMain,
#    which cannot contain class definitions. An explicit Playground.runMain entry
#    makes planRun pass the source through unchanged (regex: /class\s+Playground|runMain/).
$LocalExamples = [ordered]@{}

$LocalExamples['helloworld'] = @{ Code = @'
Playground
{
    static runMain()
    {
        Console.println("Hello, Slang!")
        Console.println("2 + 3 = " + (2 + 3).toString())
        for i = 1, i <= 3, i = i + 1
        {
            Console.println("count = " + i.toString())
        }
    }
}
'@
Expected = "Hello, Slang!`n2 + 3 = 5`ncount = 1`ncount = 2`ncount = 3" }

$LocalExamples['hello'] = @{ Code = @'
import Core;
import Std;

class Greeter
{
    string name = "";

    _init_( string name )
    {
        this.name = name;
    }

    string hello()
    {
        ret "Hello, " + this.name + "!";
    }
}

Playground
{
    static runMain()
    {
        greeter = Greeter( "SLang" );
        Console.println( greeter.hello() );
    }
}
'@
Expected = "Hello, SLang!" }

$LocalExamples['fib'] = @{ Code = @'
import Std

Fibonacci
{
    static fun()
    {
        Console.println( "========== Fibonacci (start) ==========" )
        sum = 0L
        for i = 0, i < 10, i++
        {
            sum += Fibonacci.fib( i )
        }
        Console.println( "fib(0..9) sum = " + sum.toString() )
        Console.println( "========== Fibonacci (end) ==========" )
    }

    static int fib( int n )
    {
        ret n <= 1 ? n : Fibonacci.fib( n - 1 ) + fib( n - 2 )
    }
}

Playground
{
    static runMain()
    {
        Fibonacci.fun()
    }
}
'@
Expected = "========== Fibonacci (start) ==========`nfib(0..9) sum = 88`n========== Fibonacci (end) ==========" }

$LocalExamples['table99'] = @{ Code = @'
import Std

JJ
{
    static Fun()
    {
        for i = 1, i <= 9, i++
        {
            line = ""
            for j = 1, j <= i, j++
            {
                line = line + j.toString() + "x" + i.toString() + "=" + ( j * i ).toString() + " "
            }
            Console.println( line )
        }
    }
}

Playground
{
    static runMain()
    {
        JJ.Fun()
    }
}
'@
Expected = "1x1=1`n1x2=2 2x2=4`n1x3=3 2x3=6 3x3=9`n1x4=4 2x4=8 3x4=12 4x4=16`n1x5=5 2x5=10 3x5=15 4x5=20 5x5=25`n1x6=6 2x6=12 3x6=18 4x6=24 5x6=30 6x6=36`n1x7=7 2x7=14 3x7=21 4x7=28 5x7=35 6x7=42 7x7=49`n1x8=8 2x8=16 3x8=24 4x8=32 5x8=40 6x8=48 7x8=56 8x8=64`n1x9=9 2x9=18 3x9=27 4x9=36 5x9=45 6x9=54 7x9=63 8x9=72 9x9=81" }

$LocalExamples['container'] = @{ Code = @'
import Std

Container
{
    static demoContainers()
    {
        nums = list<int>()
        for i = 0, i < 5, i = i + 1
        {
            nums.add( i * i )
        }
        Console.println( "squares: " + nums.toString() )

        words = map<int,string>()
        words.add( 1, "one" )
        words.add( 2, "two" )
        Console.println( "map length = " + words.length.toString() )

        hs = hashset<int>()
        hs.add( 1 )
        hs.add( 2 )
        hs.add( 2 )
        Console.println( "hashset 去重后长度 = " + hs.length.toString() )
    }
}

Playground
{
    static runMain()
    {
        Container.demoContainers()
    }
}
'@
Expected = "squares: [0,1,4,9,16]`nmap length = 2`nhashset 去重后长度 = 2" }

$LocalExamples['string'] = @{ Code = @'
import Std

StringDemo
{
    static dollarSmoke()
    {
        name = "SLang"
        score = 55
        a = 100
        b = 300

        str = "Name:${name} Score:${score} a+b=${( a + b ).toString()}"
        Console.println( str )
        Console.println( String.toFormat( "a[{}]+b[{}]={}", a, b, a + b ) )
    }
}

Playground
{
    static runMain()
    {
        StringDemo.dollarSmoke()
    }
}
'@
Expected = "Name:SLang Score:55 a+b=400`na[100]+b[300]=400" }

$LocalExamples['coroutine'] = @{ Code = @'
import Core;
import Std;

Playground
{
    static int add2( int a, int b )
    {
        ret a + b;
    }

    static runMain()
    {
        Task t1 = spawn add2( 20, 22 );
        Task t2 = spawn add2( 10, 5 );

        int s1 = await t1 as int;
        int s2 = await t2 as int;

        Console.println( "s1 = $s1" );
        Console.println( "s2 = $s2" );
    }
}
'@
Expected = "s1 = 42`ns2 = 15" }

$LocalExamples['waitall'] = @{ Code = @'
import Core;
import Std;

Playground
{
    static int coroA( int n )
    {
        ret n * 2;
    }

    static int coroB( int n )
    {
        ret n + 30;
    }

    static runMain()
    {
        Task ta = spawn coroA( 3 );
        Task tb = spawn coroB( 3 );
        Coroutine.waitAll2( ta, tb );
        Console.println( "both done" );
    }
}
'@
Expected = "both done" }

$LocalExamples['template'] = @{ Code = @'
import Std

Level1<LevelT1>
{
    LevelT1 LevelMemValue = new()

    _init_( LevelT1 t1 )
    {
        this.LevelMemValue = t1
    }

    LevelT1 com()
    {
        ret this.LevelMemValue
    }

    LevelT3 fun<LevelT3>( LevelT3 t3 )
    {
        ret t3
    }
}

Playground
{
    static runMain()
    {
        box = Level1<int>( 42 )
        Console.println( "com() = " + box.com().toString() )
        Console.println( "fun<string> = " + box.fun<string>( "ok" ) )
    }
}
'@
Expected = "com() = 42`nfun<string> = ok" }

$LocalExamples['exception'] = @{ Code = @'
import Std

enum TestError extends Error
{
    TestError1 = { code = 1, message = "test-error" }
}

TryTest
{
    static string riskyFunc( bool shouldFail ) throws
    {
        if ( shouldFail )
        {
            throw TestError.TestError1
        }
        ret "success"
    }

    static catchBinding() throws
    {
        string captured = "none"
        label bindBlock
        {
            try riskyFunc( true )
        }
        catch TestError ex
        {
            captured = "caught: " + ex.toString()
        }
        Console.println( captured )
    }
}

Playground
{
    static runMain() throws
    {
        TryTest.catchBinding()
    }
}
'@
Expected = "caught: Error (code=1): test-error" }

$LocalExamples['bench-loop'] = @{ Code = @'
import Std

Bench
{
    static loop()
    {
        nowMs = Environment.sys.nowMillis()
        sum = 0L
        for i = 0, i < 1000000, i++
        {
            sum += i
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println( "1e6 loop sum = " + sum.toString() + " [$nowMs ms]" )
    }
}

Playground
{
    static runMain()
    {
        Bench.loop()
    }
}
'@
Expected = "1e6 loop sum = 499999500000 [12 ms]" }
