import Std;

Project
{
    _main_()
    {
        Tuple t = Tuple.create( 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 )
        int n = t.length
        Console.println( "len=" + n.toString() )
        string s = "a{0}b{1}"
        string r2 = s.format( 1, "x" )
        Console.println( r2 )
        string r3 = String.toFormat( "c{0}-{1}-{2}", 1, 2, 3 )
        Console.println( r3 )
    }
}
