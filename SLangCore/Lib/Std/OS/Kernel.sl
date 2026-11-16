# ============================================================================
# Std/OS/Kernel.sl — 进程级内核语义（2026-11-13 第十八/十九轮）
#
# SystemExit 系统调用的封装：以指定退出码终止当前 VM 进程。
#   OS.Kernel.exit( 1 )   # 以退出码 1 终止（之后不再返回）
#
# 退出码语义（C VM 侧）：
#   - 正数 code 透传为进程退出码（csimple_lang run / slang 裸工程 /
#     slang test 的进程 exit code）；
#   - code <= 0 归一为 1（0 是「正常结束」，不能由 exit 越权表达）。
#
# 形态说明：namespace OS（与 Process 同位）；顶层无 namespace 版实测在引用
# 方不可见（fullName 混入 namespaceList 被建成同名命名空间节点，见 Q-38）。
# ============================================================================

namespace OS
{
    public class Kernel extends Object
    {
        # 以指定退出码终止当前 VM 进程（不返回；code <= 0 归一为 1）
        public static void exit( Int32 code )
        {
            SystemExit( code );
        }
    }
}

