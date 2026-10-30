# 迭代器与可迭代契约（标准库统一遍历协议）
# 任何支持 foreach / Range 遍历 / 容器迭代的类型都实现 IIterable<T>，由其返回 IIterator<T>。
# 非泛型版本用于未知元素类型的弱类型场景。

public interface IIterator
{
    # 将迭代器复位到序列起始之前（下一次 moveNext 指向首个元素）。
    void reset()
    # 尝试前进到下一个元素；存在则返回 true，迭代结束返回 false。
    bool moveNext()
    # 获取当前迭代位置的元素（moveNext 返回 true 后有效；弱类型 object）。
    get object current()
}
public interface IIterable
{
    # 返回一个新的迭代器，用于遍历本集合（弱类型）。
    IIterator iterator()
}

public interface IIterator<out T>
{
    # 将迭代器复位到序列起始之前。
    void reset()
    # 尝试前进到下一个元素；存在则返回 true，否则 false。
    bool moveNext()
    # 获取当前位置的元素（强类型 T）。
    get T current()
}
public interface IIterable<T>
{
    # 返回一个强类型新迭代器，用于遍历本集合。
    IIterator<T> iterator()
}
