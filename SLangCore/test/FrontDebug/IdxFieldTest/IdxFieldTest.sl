import Core;
import Std;

# Front 崩溃最小复现（第三十四轮）：list[idx] 的 idx 为字段时
# ParseStatements/MetaCallNode.HandleVisit 空引用崩溃（troubleshooting/06 第三十三轮）
namespace CodeTest
{
    public class IdxFieldTest
    {
        static List<string> _stack = null
        static int _pos = 0

        static int main()
        {
            _stack = List<string>()
            _stack.add( "a" )
            _stack.add( "b" )
            _pos = 1
            string x = _stack[_pos]
            Console.writeLine( x )
            ret 0
        }
    }
}
