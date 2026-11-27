// SlJvExtraUtil.java —— SpecialTest 工程外部 Java 源示例（JavaCode\ 目录）：
// 由工程 jsonc plugins.java_hotspot.sources 引入（Front 读文件内容随 Build
// 请求下发），与全部 @java_hotspot(){} 块体条目同批 javac 合并编译，class
// 部署进插件 classes\SLAtSign\ 包目录。声明 package SLAtSign 与块体生成类
// 同包直调（无需 import）；类为包私有——javac 不要求非 public 类与文件名
//（部署文件名 CsSrc_SlJvExtraUtil.java 由 Front 分配）同名。
package SLAtSign;

class SlJvExtraUtil
{
    static long add( long a, long b )
    {
        return a + b;
    }

    static String greet( String name )
    {
        return "Hi, " + name + "!";
    }
}
