# 类构造循环引用（用户示例）：NewA new NewB / NewB new NewC / NewC new NewA
# 三节点构造环 —— 编译期应 Error 阻断（运行期 new 任一类会无限递归构造）

NewA
{
    NewB b = new()
}

NewB
{
    NewC c = new()
}

NewC
{
    NewA a = new()
}
