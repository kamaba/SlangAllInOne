# 对照组 1：静态单例自 new（合法模式，静态初始化仅执行一次，不递归 → 应放行）
# 对照组 2：非静态自 new（无限递归 → 应 Error）
# 对照组 3：null 持有引用（合法，不构造 → 应放行）

Singleton
{
    static Singleton s = new()
    static int n = 1
}

SelfLoop
{
    SelfLoop inner = new()
}

Holder
{
    Holder peer = null
}
