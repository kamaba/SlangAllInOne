import Std

# BinaryTree - 二叉树构建与遍历基准：对象分配 + GC 压力 + 递归
# 经典 binary-trees 形态：满二叉树，节点值沿路径 v*2 / v*2+1，求和校验
BinaryTreeBench
{
    # 树节点：自引用字段（同 LinkedList.Node 写法）
    # value 用 Int64：求和链路保持 64 位，避免 Int32+Int64 混算被截断回绕
    BenchNode
    {
        Int64 value = 0L
        BenchNode left = null
        BenchNode right = null
        _init_(Int64 v)
        {
            this.value = v
        }
    }

    static fun()
    {
        Console.println("========== BinaryTree (start) ==========")

        # 1. depth 12 x10 轮（每轮 4095 节点：构建 + 求和）
        nowMs = Environment.sys.nowMillis()
        total = 0L
        for r = 0, r < 10, r++
        {
            root = BinaryTreeBench.build(12, r + 1)
            total += BinaryTreeBench.checksum(root)
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("tree depth12 x10 checksum = " + total.toString() + "  [$nowMs.toString() ms]")

        # 2. depth 16 x2 轮（每轮 65535 节点）
        nowMs = Environment.sys.nowMillis()
        total2 = 0L
        for r = 0, r < 2, r++
        {
            root = BinaryTreeBench.build(16, r + 1)
            total2 += BinaryTreeBench.checksum(root)
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("tree depth16 x2 checksum = " + total2.toString() + "  [$nowMs.toString() ms]")

        Console.println("========== BinaryTree (end) ==========")
    }

    # 构建深度 depth 的满二叉树（depth=0 返回 null）
    static BenchNode build(int depth, int value)
    {
        if (depth <= 0)
        {
            ret null
        }
        node = BenchNode(value)
        node.left = BinaryTreeBench.build(depth - 1, value * 2)
        node.right = BinaryTreeBench.build(depth - 1, value * 2 + 1)
        ret node
    }

    # 全树求和
    static Int64 checksum(BenchNode node)
    {
        if (node == null)
        {
            ret 0L
        }
        ret node.value + BinaryTreeBench.checksum(node.left) + BinaryTreeBench.checksum(node.right)
    }
}
