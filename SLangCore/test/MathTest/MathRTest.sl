import Std;
import Math;

# MathRTest —— Math 库 R base 风格四类扩展的冒烟断言
# 覆盖 MathRBasic / MathStats / MathDist / MathVec 的主要入口。
class MathRTest
{
    static Int32 pass = 0
    static Int32 fail = 0

    static check( string name, bool cond )
    {
        if cond
        {
            Console.println( "  [PASS] " + name )
            MathRTest.pass = MathRTest.pass + 1
        }
        else
        {
            Console.println( "  [FAIL] " + name )
            MathRTest.fail = MathRTest.fail + 1
        }
    }

    static bool near( Float64 a, Float64 b )
    {
        Float64 d = a - b
        if d < 0.0d
        {
            d = 0.0d - d
        }
        ret d < 0.0001d
    }

    static List<Float64> oneToFour()
    {
        List<Float64> v = List<Float64>()
        v.add( 1.0d )
        v.add( 2.0d )
        v.add( 3.0d )
        v.add( 4.0d )
        ret v
    }

    static testBasic()
    {
        Console.println( "===== MathRTest.testBasic =====" )
        List<Float64> v = MathRTest.oneToFour()
        MathRTest.check( "basic.sum", MathRBasic.sum( v ) == 10.0d )
        MathRTest.check( "basic.prod", MathRBasic.prod( v ) == 24.0d )
        MathRTest.check( "basic.minOf", MathRBasic.minOf( v ) == 1.0d )
        MathRTest.check( "basic.maxOf", MathRBasic.maxOf( v ) == 4.0d )
        MathRTest.check( "basic.rangeOf", MathRBasic.rangeOf( v ) == 3.0d )
        List<Float64> cs = MathRBasic.cumsum( v )
        MathRTest.check( "basic.cumsum", cs.length == 4 && cs._getItem_( 3 ) == 10.0d )
        List<Float64> df = MathRBasic.diff( v )
        MathRTest.check( "basic.diff", df.length == 3 && df._getItem_( 2 ) == 1.0d )
        MathRTest.check( "basic.factorial", MathRBasic.factorial( 5 ) == 120.0d )
        MathRTest.check( "basic.choose", MathRBasic.choose( 5, 2 ) == 10.0d )
        MathRTest.check( "basic.roundDigits", MathRBasic.roundDigits( 1.23456d, 2 ) == 1.23d )
        MathRTest.check( "basic.ceiling", MathRBasic.ceiling( 1.2d ) == 2.0d )
        MathRTest.check( "basic.floor", MathRBasic.floor( 1.8d ) == 1.0d )
    }

    static testStats()
    {
        Console.println( "===== MathRTest.testStats =====" )
        List<Float64> v = MathRTest.oneToFour()
        MathRTest.check( "stats.mean", MathStats.mean( v ) == 2.5d )
        MathRTest.check( "stats.median", MathStats.median( v ) == 2.5d )
        MathRTest.check( "stats.variance", MathRTest.near( MathStats.variance( v ), 1.6666667d ) )
        MathRTest.check( "stats.sd", MathRTest.near( MathStats.sd( v ), 1.2909944d ) )
        MathRTest.check( "stats.quantile", MathStats.quantile( v, 0.25d ) == 1.75d )
        MathRTest.check( "stats.covariance", MathStats.covariance( v, v ) > 1.6d )
        MathRTest.check( "stats.correlation", MathRTest.near( MathStats.correlation( v, v ), 1.0d ) )
        List<Float64> z = MathStats.scale( v )
        MathRTest.check( "stats.scale", z.length == 4 && MathRTest.near( MathStats.mean( z ), 0.0d ) )
        string s = MathStats.summary( v )
        MathRTest.check( "stats.summary", s.length > 10 )

        List<Float64> x = List<Float64>()
        List<Float64> y = List<Float64>()
        x.add( 1.0d )
        x.add( 2.0d )
        x.add( 3.0d )
        y.add( 3.0d )
        y.add( 5.0d )
        y.add( 7.0d )
        MathRTest.check( "stats.lm.slope", MathRTest.near( MathStats.lmSlope( x, y ), 2.0d ) )
        MathRTest.check( "stats.lm.intercept", MathRTest.near( MathStats.lmIntercept( x, y ), 1.0d ) )
        MathRTest.check( "stats.tTest", MathStats.tTest( v, 0.0d ) > 3.0d )

        List<Float64> obs = List<Float64>()
        List<Float64> exp = List<Float64>()
        obs.add( 12.0d )
        obs.add( 8.0d )
        exp.add( 10.0d )
        exp.add( 10.0d )
        MathRTest.check( "stats.chisqTest", MathRTest.near( MathStats.chisqTest( obs, exp ), 0.8d ) )

        List<Float64> g1 = List<Float64>()
        List<Float64> g2 = List<Float64>()
        g1.add( 1.0d )
        g1.add( 2.0d )
        g1.add( 3.0d )
        g2.add( 4.0d )
        g2.add( 5.0d )
        g2.add( 6.0d )
        MathRTest.check( "stats.aov", MathStats.aov( g1, g2 ) > 1.0d )
    }

    static testDist()
    {
        Console.println( "===== MathRTest.testDist =====" )
        MathDist.setSeed( 42 )
        Float64 u = MathDist.uniform01()
        MathRTest.check( "dist.uniform01", u >= 0.0d && u < 1.0d )
        MathDist.setSeed( 42 )
        Float64 u2 = MathDist.uniform01()
        MathRTest.check( "dist.setSeed", u == u2 )
        Float64 ru = MathDist.runif( 5.0d, 10.0d )
        MathRTest.check( "dist.runif", ru >= 5.0d && ru <= 10.0d )
        MathRTest.check( "dist.dnorm", MathRTest.near( MathDist.dnorm( 0.0d, 0.0d, 1.0d ), 0.3989423d ) )
        MathRTest.check( "dist.pnorm", MathRTest.near( MathDist.pnorm( 0.0d, 0.0d, 1.0d ), 0.5d ) )
        Float64 q975 = MathDist.qnorm( 0.975d, 0.0d, 1.0d )
        MathRTest.check( "dist.qnorm", MathRTest.near( q975, 1.959964d ) )
        MathDist.setSeed( 7 )
        Float64 n1 = MathDist.rnorm( 0.0d, 1.0d )
        MathDist.setSeed( 7 )
        Float64 n2 = MathDist.rnorm( 0.0d, 1.0d )
        MathRTest.check( "dist.rnorm", n1 == n2 )
        Float64 rb = MathDist.rbinom( 10, 5, 0.5d )
        MathRTest.check( "dist.rbinom", rb >= 0.0d && rb <= 50.0d )
        Float64 rp = MathDist.rpois( 3.0d )
        MathRTest.check( "dist.rpois", rp >= 0.0d )
        Float64 re = MathDist.rexp( 2.0d )
        MathRTest.check( "dist.rexp", re >= 0.0d )
        List<Float64> pool = MathRTest.oneToFour()
        List<Float64> picked = MathDist.sample( pool, 2 )
        MathRTest.check( "dist.sample", picked.length == 2 )
    }

    static testVec()
    {
        Console.println( "===== MathRTest.testVec =====" )
        List<Float64> seqv = MathVec.seq( 1.0d, 5.0d, 1.0d )
        MathRTest.check( "vec.seq", seqv.length == 5 && seqv._getItem_( 4 ) == 5.0d )
        List<Float64> repv = MathVec.rep( 2.0d, 3 )
        MathRTest.check( "vec.rep", repv.length == 3 && repv._getItem_( 2 ) == 2.0d )
        List<Float64> raw = List<Float64>()
        raw.add( 3.0d )
        raw.add( 1.0d )
        raw.add( 2.0d )
        raw.add( 1.0d )
        List<Float64> sorted = MathVec.sort( raw )
        MathRTest.check( "vec.sort", sorted._getItem_( 0 ) == 1.0d && sorted._getItem_( 3 ) == 3.0d )
        List<Int32> ord = MathVec.order( raw )
        MathRTest.check( "vec.order", ord._getItem_( 0 ) == 1 )
        List<Float64> reversed = MathVec.rev( sorted )
        MathRTest.check( "vec.rev", reversed._getItem_( 0 ) == 3.0d )
        List<Float64> uniq = MathVec.unique( raw )
        MathRTest.check( "vec.unique", uniq.length == 3 )
        List<Int32> weq = MathVec.whichEqual( raw, 1.0d )
        MathRTest.check( "vec.whichEqual", weq.length == 2 )
        List<Int32> wgt = MathVec.whichGreater( raw, 2.0d )
        MathRTest.check( "vec.whichGreater", wgt.length == 1 )
        MathRTest.check( "vec.matchIndex", MathVec.matchIndex( 2.0d, raw ) == 2 )
        List<Float64> app = MathVec.append( raw, 9.0d )
        MathRTest.check( "vec.append", app.length == 5 && app._getItem_( 4 ) == 9.0d )
        List<Float64> br = List<Float64>()
        br.add( 0.0d )
        br.add( 2.0d )
        br.add( 5.0d )
        MathRTest.check( "vec.cutIndex", MathVec.cutIndex( 3.0d, br ) == 1 )
        List<Int32> mask = List<Int32>()
        mask.add( 1 )
        mask.add( 0 )
        mask.add( 1 )
        mask.add( 0 )
        List<Float64> condResult = MathVec.ifelse( mask, 10.0d, 0.0d )
        MathRTest.check( "vec.ifelse", condResult.length == 4 && condResult._getItem_( 0 ) == 10.0d && condResult._getItem_( 1 ) == 0.0d )
        List<Int32> counts = MathVec.tableCounts( raw )
        MathRTest.check( "vec.tableCounts", counts.length == 3 && counts._getItem_( 0 ) == 2 )
        MathRTest.check( "vec.modeValue", MathVec.modeValue( raw ) == 1.0d )
    }

    static fun()
    {
        Console.println( "===== MathRTest: R base 扩展四类函数 =====" )
        MathRTest.testBasic()
        MathRTest.testStats()
        MathRTest.testDist()
        MathRTest.testVec()
        string result = "===== MathRTest PASS=" + MathRTest.pass.toString() + " FAIL=" + MathRTest.fail.toString() + " ====="
        Console.println( result )
    }
}
