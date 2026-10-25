# -*- coding: utf-8 -*-
"""
BenchMarkPython.py — SLang BenchMark 的 CPython 等价实现（性能对比用）

逐项对齐同目录下同名 .sl 用例：迭代次数、运算序列、计时范围完全一致；
输出行格式与 SL 侧对齐，便于逐行 diff。

已知语义差异（结果数值不同属预期，不影响耗时可比性）：
- Python int 为任意精度：Int32 求和不会回绕（SL 实测 -1455759936 是 Int32 溢出回绕）
- Python float = IEEE754 double，与 SL `Num` 规范（f64 槽）一致
- CPython re 模块内部缓存已编译模式：compile x2000 计为缓存命中路径

用法：python BenchMarkPython.py
"""

import re
import struct
import time


def now_ms(t0):
    return (time.perf_counter() - t0) * 1000.0


# ============================================================================
# Fibonacci（递归调用开销）
# ============================================================================

def fib(n):
    return n if n <= 1 else fib(n - 1) + fib(n - 2)


def fibonacci_bench():
    print("========== Fibonacci (start) ==========")
    t0 = time.perf_counter()
    total = 0
    for i in range(22):
        total += fib(i)
    dt = now_ms(t0)
    print(f"fib(0..21) sum = {total}  [{dt:.0f}ms]")
    print("========== Fibonacci (end) ==========")


# ============================================================================
# Loop（数组遍历 / while / 步进 for）
# ============================================================================

def loop_bench():
    print("========== Loop (start) ==========")

    # 1. 双层 for + 数组读写（填充不计入计时，与 SL 一致）
    n = 1000
    arr = [0] * n
    for i in range(n):
        arr[i] = i * i
    t0 = time.perf_counter()
    total = 0
    for j in range(3000):
        s = 0
        for i in range(n):
            s += arr[i]
        total += s
    dt = now_ms(t0)
    print(f"array sum x3000 = {total}  [{dt:.0f}ms]")

    # 2. while 循环
    t0 = time.perf_counter()
    wsum = 0
    k = 0
    while k < 5000000:
        wsum += k
        k += 1
    dt = now_ms(t0)
    print(f"while sum 5e6 = {wsum}  [{dt:.0f}ms]")

    # 3. for 步进
    t0 = time.perf_counter()
    step_sum = 0
    for i in range(0, 1000000, 7):
        step_sum += i
    dt = now_ms(t0)
    print(f"for step +7 1e6 = {step_sum}  [{dt:.0f}ms]")

    print("========== Loop (end) ==========")


# ============================================================================
# Levenshtein（DP + 函数调用）
# ============================================================================

def min3(x, y, z):
    if x < y and x < z:
        return x
    if y < z:
        return y
    return z


def levenshtein_distance(a, b):
    m = len(a)
    n = len(b)
    prev = [0] * (n + 1)
    curr = [0] * (n + 1)
    for j in range(n + 1):
        prev[j] = j
    for i in range(1, m + 1):
        curr[0] = i
        for j in range(1, n + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            del_ = prev[j] + 1
            ins = curr[j - 1] + 1
            sub = prev[j - 1] + cost
            curr[j] = min3(del_, ins, sub)
        prev, curr = curr, prev
    return prev[n]


def levenshtein_bench():
    print("========== Levenshtein (start) ==========")
    a = [10, 20, 30, 40, 50, 60]
    b = [10, 25, 30, 35, 40, 50, 65]

    dist = levenshtein_distance(a, b)
    print(f"levenshtein(a,b) = {dist}")

    t0 = time.perf_counter()
    total = 0
    for r in range(5000):
        total += levenshtein_distance(a, b)
    dt = now_ms(t0)
    print(f"levenshtein x5000 = {total}  [{dt:.0f}ms]")
    print("========== Levenshtein (end) ==========")


# ============================================================================
# DataTypes（整型 / 浮点 / 混合 / bool）
# ============================================================================

def datatypes_bench():
    print("========== DataTypes (start) ==========")

    # 1. Int32（Python int 不回绕，数值与 SL 不同属预期）
    t0 = time.perf_counter()
    s32 = 0
    for i in range(2000000):
        s32 += i
    dt = now_ms(t0)
    print(f"Int32 sum 2e6 = {s32}  [{dt:.0f}ms]")

    # 2. Int64
    t0 = time.perf_counter()
    s64 = 0
    for i in range(2000000):
        s64 += i
    dt = now_ms(t0)
    print(f"Int64 sum 2e6 = {s64}  [{dt:.0f}ms]")

    # 3. Num (double)
    t0 = time.perf_counter()
    sf = 0.0
    for i in range(2000000):
        sf += i * 1.5
    dt = now_ms(t0)
    print(f"Num sum 2e6 = {sf}  [{dt:.0f}ms]")

    # 4. 混合运算（int/float 混用 + 取模）
    t0 = time.perf_counter()
    mix = 0.0
    for i in range(1000000):
        mix = mix + i / 3.0 + i % 7
    dt = now_ms(t0)
    print(f"Mixed ops 1e6 = {mix}  [{dt:.0f}ms]")

    # 5. bool 短路判断
    t0 = time.perf_counter()
    count = 0
    for i in range(1000000):
        if i % 3 == 0 and i % 5 == 0:
            count += 1
    dt = now_ms(t0)
    print(f"bool mod 1e6 = {count}  [{dt:.0f}ms]")

    print("========== DataTypes (end) ==========")


# ============================================================================
# StringBench（拼接 / 插值 / format / 比较）
# ============================================================================

def string_bench():
    print("========== StringBench (start) ==========")

    # 1. 字符串拼接
    t0 = time.perf_counter()
    s = ""
    for i in range(10000):
        s = s + "ab"
    dt = now_ms(t0)
    print(f"concat 1e4  [{dt:.0f}ms]")

    # 2. 插值构建（SL: "v=$i s=${(i * 2).toString()}"）
    t0 = time.perf_counter()
    t = ""
    for i in range(10000):
        t = f"v={i} s={i * 2}"
    dt = now_ms(t0)
    print(f"interp 1e4  [{dt:.0f}ms]")

    # 3. format
    t0 = time.perf_counter()
    u = ""
    for i in range(10000):
        u = "{0}-{1}".format(i, i + 1)
    dt = now_ms(t0)
    print(f"format 1e4  [{dt:.0f}ms]")

    # 4. 字符串比较
    t0 = time.perf_counter()
    c = 0
    for i in range(100000):
        if s == t:
            c += 1
    dt = now_ms(t0)
    print(f"compare 1e5  count={c}  [{dt:.0f}ms]")

    # 5. 最终内容校验
    print(f"concat endswith ab = {s == u}")

    print("========== StringBench (end) ==========")


# ============================================================================
# RegExpBench（编译 / 命中 / 全扫 / matchAll / replace / 分组 / backref / UTF-8）
# ============================================================================

def regexp_bench():
    print("========== RegExpBench (start) ==========")

    # 主文本："abc123 def456 ghi789 " x 4000 = 80000 字节
    chunk = "abc123 def456 ghi789 "
    text = ""
    for i in range(4000):
        text = text + chunk
    print(f"text bytes = {len(text)}")

    # 0. 编译开销 x2000（CPython 命中 re 内部缓存）
    t0 = time.perf_counter()
    for i in range(2000):
        re_c = re.compile("([a-z]+)([0-9]+)")
    dt = now_ms(t0)
    print(f"compile x2000  [{dt:.0f} ms]")

    # 1. search 早命中 "def456" x500
    re1 = re.compile("def456")
    t0 = time.perf_counter()
    hit = ""
    for i in range(500):
        hit = re1.search(text).group(0)
    dt = now_ms(t0)
    print(f"search hit x500  [{dt:.0f} ms]  value={hit}")

    # 2. search 全扫不命中 "zzz999" x20
    re2 = re.compile("zzz999")
    t0 = time.perf_counter()
    miss = True
    for i in range(20):
        miss = re2.search(text) is None
    dt = now_ms(t0)
    print(f"search miss x20  [{dt:.0f} ms]  miss={miss}")

    # 3. matchAll "[a-z]+" x5
    re3 = re.compile("[a-z]+")
    t0 = time.perf_counter()
    words = 0
    for i in range(5):
        words = len(re3.findall(text))
    dt = now_ms(t0)
    print(f"matchAll x5  [{dt:.0f} ms]  count={words}")

    # 4. replace "[0-9]+" x5
    re4 = re.compile("[0-9]+")
    t0 = time.perf_counter()
    rep = ""
    for i in range(5):
        rep = re4.sub("#", text)
    dt = now_ms(t0)
    print(f"replace x5  [{dt:.0f} ms]  len={len(rep)}")

    # 5. 分组捕获 search + group 取值 x200
    re5 = re.compile("([a-z]+)([0-9]+)")
    t0 = time.perf_counter()
    g1 = ""
    g2 = ""
    for i in range(200):
        m = re5.search(text)
        g1 = m.group(1)
        g2 = m.group(2)
    dt = now_ms(t0)
    print(f"group search x200  [{dt:.0f} ms]  g1={g1} g2={g2}")

    # 6. backref 文本 "abc abc def def " x 2000 = 32000 字节
    chunk2 = "abc abc def def "
    text2 = ""
    for i in range(2000):
        text2 = text2 + chunk2
    re6 = re.compile(r"(\w+) \1")
    t0 = time.perf_counter()
    pairs = 0
    for i in range(10):
        pairs = len(re6.findall(text2))
    dt = now_ms(t0)
    print(f"backref matchAll x10  [{dt:.0f} ms]  count={pairs}")

    # 7. UTF-8 中文："中文测试123 " x 2000
    chunk3 = "中文测试123 "
    text3 = ""
    for i in range(2000):
        text3 = text3 + chunk3
    re7 = re.compile("测试[0-9]+")
    t0 = time.perf_counter()
    zh = ""
    for i in range(100):
        zh = re7.search(text3).group(0)
    dt = now_ms(t0)
    print(f"utf8 search x100  [{dt:.0f} ms]  value={zh}")

    print("========== RegExpBench (end) ==========")


# ============================================================================
# NQueens（N 皇后递归回溯）
# ============================================================================

def nqueens_place(queens, row, n):
    if row == n:
        return 1
    count = 0
    for col in range(n):
        ok = 1
        for i in range(row):
            if queens[i] == col or queens[i] - i == col - row or queens[i] + i == col + row:
                ok = 0
                break
        if ok == 1:
            queens[row] = col
            count += nqueens_place(queens, row + 1, n)
    return count


def nqueens_solve(n):
    queens = [0] * n
    return nqueens_place(queens, 0, n)


def nqueens_bench():
    print("========== NQueens (start) ==========")

    # 1. n=11 单轮（解数 2680）
    t0 = time.perf_counter()
    solutions = nqueens_solve(11)
    dt = now_ms(t0)
    print(f"nqueens(11) solutions = {solutions}  [{dt:.0f} ms]")

    # 2. n=9 x10 轮
    t0 = time.perf_counter()
    total = 0
    for r in range(10):
        total += nqueens_solve(9)
    dt = now_ms(t0)
    print(f"nqueens(9) x10 = {total}  [{dt:.0f} ms]")

    print("========== NQueens (end) ==========")


# ============================================================================
# Sieve（埃拉托斯特尼素数筛）
# ============================================================================

def sieve_count_primes(n):
    is_composite = [0] * (n + 1)
    count = 0
    for i in range(2, n + 1):
        if is_composite[i] == 0:
            count += 1
            if i <= n // i:
                j = i * i
                while j <= n:
                    is_composite[j] = 1
                    j += i
    return count


def sieve_bench():
    print("========== Sieve (start) ==========")

    # 1. 1e6 单轮
    t0 = time.perf_counter()
    primes = sieve_count_primes(1000000)
    dt = now_ms(t0)
    print(f"sieve 1e6 primes = {primes}  [{dt:.0f} ms]")

    # 2. 5e5 x5 轮
    t0 = time.perf_counter()
    total = 0
    for r in range(5):
        total += sieve_count_primes(500000)
    dt = now_ms(t0)
    print(f"sieve 5e5 x5 = {total}  [{dt:.0f} ms]")

    print("========== Sieve (end) ==========")


# ============================================================================
# QuickSort（Hoare 分区快排 + Park-Miller LCG 数据）
# ============================================================================

def quicksort(a, lo, hi):
    if lo >= hi:
        return
    i = lo
    j = hi
    p = a[(lo + hi) // 2]
    while i <= j:
        while a[i] < p:
            i += 1
        while a[j] > p:
            j -= 1
        if i <= j:
            a[i], a[j] = a[j], a[i]
            i += 1
            j -= 1
    quicksort(a, lo, j)
    quicksort(a, i, hi)


def quicksort_bench():
    print("========== QuickSort (start) ==========")

    n = 30000
    rounds = 5
    arr = [0] * n

    total_ms = 0.0
    checksum = 0
    for r in range(rounds):
        seed = 42 + r
        for i in range(n):
            seed = (seed * 16807) % 2147483647
            arr[i] = seed
        t0 = time.perf_counter()
        quicksort(arr, 0, n - 1)
        total_ms += now_ms(t0)
        for i in range(n):
            checksum += arr[i]
            if i > 0 and arr[i - 1] > arr[i]:
                print(f"SORTED CHECK FAILED at {i}")
    print(f"quicksort 3e4 x5  [{total_ms:.0f} ms]  checksum = {checksum}")

    print("========== QuickSort (end) ==========")


# ============================================================================
# MatrixMul（朴素三重循环矩阵乘法，扁平数组行主序）
# ============================================================================

def matmul(a, b, c, n):
    for i in range(n):
        for j in range(n):
            s = 0
            for k in range(n):
                s += a[i * n + k] * b[k * n + j]
            c[i * n + j] = s


def matmul_bench():
    print("========== MatrixMul (start) ==========")

    n = 100
    rounds = 3
    a = [0] * (n * n)
    b = [0] * (n * n)
    c = [0] * (n * n)

    for i in range(n):
        for j in range(n):
            a[i * n + j] = (i + j) % 100
            b[i * n + j] = (i * 7 + j * 3) % 100

    t0 = time.perf_counter()
    for r in range(rounds):
        matmul(a, b, c, n)
    dt = now_ms(t0)

    checksum = 0
    for i in range(n * n):
        checksum += c[i]
    print(f"matmul 100x100 x3  [{dt:.0f} ms]  checksum = {checksum}")

    print("========== MatrixMul (end) ==========")


# ============================================================================
# BinaryTree（二叉树构建 + 求和，对象分配/GC 压力）
# ============================================================================

class BenchNode:
    __slots__ = ("value", "left", "right")

    def __init__(self, v):
        self.value = v
        self.left = None
        self.right = None


def tree_build(depth, value):
    if depth <= 0:
        return None
    node = BenchNode(value)
    node.left = tree_build(depth - 1, value * 2)
    node.right = tree_build(depth - 1, value * 2 + 1)
    return node


def tree_checksum(node):
    if node is None:
        return 0
    return node.value + tree_checksum(node.left) + tree_checksum(node.right)


def binarytree_bench():
    print("========== BinaryTree (start) ==========")

    # 1. depth 12 x10 轮
    t0 = time.perf_counter()
    total = 0
    for r in range(10):
        root = tree_build(12, r + 1)
        total += tree_checksum(root)
    dt = now_ms(t0)
    print(f"tree depth12 x10 checksum = {total}  [{dt:.0f} ms]")

    # 2. depth 16 x2 轮
    t0 = time.perf_counter()
    total2 = 0
    for r in range(2):
        root = tree_build(16, r + 1)
        total2 += tree_checksum(root)
    dt = now_ms(t0)
    print(f"tree depth16 x2 checksum = {total2}  [{dt:.0f} ms]")

    print("========== BinaryTree (end) ==========")


# ============================================================================
# Mandelbrot（曼德博集合浮点迭代）
# ============================================================================

_iter_sum = 0
_inside_count = 0


def mandelbrot_render(w, h, max_iter):
    global _iter_sum, _inside_count
    for py in range(h):
        y0 = py * 4.0 / h - 2.0
        for px in range(w):
            x0 = px * 4.0 / w - 2.0
            x = 0.0
            y = 0.0
            it = 0
            while it < max_iter and x * x + y * y <= 4.0:
                xtemp = x * x - y * y + x0
                y = 2.0 * x * y + y0
                x = xtemp
                it += 1
            _iter_sum += it
            if it == max_iter:
                _inside_count += 1


def mandelbrot_bench():
    print("========== Mandelbrot (start) ==========")

    w = 240
    h = 180
    max_iter = 150
    rounds = 3

    t0 = time.perf_counter()
    for r in range(rounds):
        mandelbrot_render(w, h, max_iter)
    dt = now_ms(t0)
    print(f"mandelbrot 240x180 x3  [{dt:.0f} ms]  iterSum = {_iter_sum}  inside = {_inside_count}")

    print("========== Mandelbrot (end) ==========")


# ============================================================================
# Float32 精度仿真诊断（不计入总时长）
#
# SL 侧 Num/Mixed 两个浮点基准的实测值（2995719503872 / 1.6670932992e11）
# 均为 float32 可精确表示的数，而 `Num` 规范应为 double（f64 精确值
# 2999998500000 / 166669499997 均不可用 float32 表示）。本段用 float32
# 逐步舍入仿真复现该路径，用于判定 SL 实跑是否走了单精度管线。
# ============================================================================

def _f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def float32_diagnostic():
    print("========== Float32 精度仿真诊断（不计入总时长） ==========")
    sf = 0.0
    for i in range(2000000):
        sf = _f32(sf + _f32(i * 1.5))
    print(f"Num   f32 仿真 = {int(sf)}   (SL 实测 2995719503872 / f64 精确 2999998500000)")

    mix = 0.0
    for i in range(1000000):
        mix = _f32(_f32(mix + _f32(i / 3.0)) + _f32(i % 7))
    print(f"Mixed f32 仿真 = {int(mix)}   (SL 实测 166709329920 / f64 精确 166669499997)")


def main():
    print("===== BenchMark _main_ start =====")
    t_all = time.perf_counter()

    fibonacci_bench()
    loop_bench()
    levenshtein_bench()
    datatypes_bench()
    string_bench()
    regexp_bench()

    nqueens_bench()
    sieve_bench()
    quicksort_bench()
    matmul_bench()
    binarytree_bench()
    mandelbrot_bench()

    dt = now_ms(t_all)
    print(f"===== BenchMark _main_ end [{dt:.0f}ms] =====")

    float32_diagnostic()


if __name__ == "__main__":
    main()
