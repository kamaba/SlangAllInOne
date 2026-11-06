# CsvAvProbe - standalone minimal repro for the ExpendTest CsvTest AV:
# BaseCsv chained getter delegation (this._table.columnCount) suspected broken.
import Std;

# 跨模块继承探针：复现 Std.Text.Csv extends Core.BaseCsv 的同款链路
class LocalCsv extends Core.BaseCsv
{
    public override string toString()
    {
        ret "LocalCsv"
    }
}

Project
{
    _main_()
    {
        var c = Text.Csv("name,age\nalice,30\nbob,25")
        SystemPrintln("rowCount = " + c.rowCount.toString())
        SystemPrintln("columnCount = " + c.columnCount.toString())
        SystemPrintln("getIntByName = " + c.getIntByName(0, "age", 0))
        # 触发本地子类实例化与虚调用（防导出裁剪 + 观测本地继承表）
        var lc = LocalCsv()
        SystemPrintln("lc.rowCount = " + lc.rowCount.toString())
        SystemPrintln("lc.columnCount = " + lc.columnCount.toString())
        SystemPrintln("probe done")
    }
    _before_()
    {
    }
}
