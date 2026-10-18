#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""bench-cpython.py — BenchMark 用例集的 CPython 等价实现（SL vs CPython 对照）

镜像 simple_language/test/BenchMark/*.sl 的各计时段：同工作量、同循环形态、
同段落顺序（Fibonacci -> Loop -> Levenshtein -> DataTypes -> StringBench -> RegExpBench），
输出行格式与 SL 版对齐，便于逐行比对。

口径说明（对照表须注明）：
- Python int 为任意精度：SL 的 Int32 段会按 4 字节回绕（SL 打印 -1455759936），
  Python 打印真实和 1999999000000；两段耗时对比仍成立（SL 反而做的是更窄的活）。
- RegExp 段两侧引擎均为 C 实现（SL 的 Std.Text.RegExp 回溯引擎下沉 C VM；
  CPython re 模块亦为 C 实现，且对字面量模式有快速扫描优化），非纯解释执行。
- SL 的 RegExp compile x2000 每次真解析；Python re.compile 同模式会命中内部缓存，
  为镜像工作量，每次编译前 re.purge() 绕过缓存（purge 仅清 dict，开销可忽略）。
- utf8 段：SL 按 UTF-8 字节扫描（text3 = 44000 字节）；Python str 按 codepoint
  （18000 字符），字符数口径不同，如实注明。
- 计时统一 perf_counter；打印整数 ms 与 SL nowMillis 对齐，汇总保留浮点。

用法：python scripts\\bench-cpython.py [rounds]   # 默认 3 轮
"""

import re
import sys
import time

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def now_ms():
    return time.perf_counter() * 1000.0


# ---------------------------------------------------------------- Fibonacci

def fib(n):
    return n if n <= 1 else fib(n - 1) + fib(n - 2)


def sec_fibonacci():
    print("========== Fibonacci (start) ==========")
    t0 = now_ms()
    total = 0
    for i in range(22):
        total += fib(i)
    dt = now_ms() - t0
    print("fib(0..21) sum = %d  [%d ms]" % (total, dt))
    print("========== Fibonacci (end) ==========")
    return dt


# ---------------------------------------------------------------- Loop

def sec_loop():
    print("========== Loop (start) ==========")
    n = 1000
    arr = [i * i for i in range(n)]  # 计时外构建，同 SL
    t0 = now_ms()
    total = 0
    for j in range(3000):
        s = 0
        for i in range(n):
            s += arr[i]
        total += s
    dt1 = now_ms() - t0
    print("array sum x3000 = %d  [%d ms]" % (total, dt1))

    t0 = now_ms()
    wsum = 0
    k = 0
    while k < 5000000:
        wsum += k
        k += 1
    dt2 = now_ms() - t0
    print("while sum 5e6 = %d  [%d ms]" % (wsum, dt2))

    t0 = now_ms()
    step_sum = 0
    for i in range(0, 1000000, 7):
        step_sum += i
    dt3 = now_ms() - t0
    print("for step +7 1e6 = %d  [%d ms]" % (step_sum, dt3))
    print("========== Loop (end) ==========")
    return dt1 + dt2 + dt3


# ---------------------------------------------------------------- Levenshtein

def lev_distance(a, b):
    m = len(a)
    n = len(b)
    prev = list(range(n + 1))
    curr = [0] * (n + 1)
    for i in range(1, m + 1):
        curr[0] = i
        for j in range(1, n + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            dele = prev[j] + 1
            ins = curr[j - 1] + 1
            sub = prev[j - 1] + cost
            curr[j] = dele if dele < ins and dele < sub else (ins if ins < sub else sub)
        prev, curr = curr, prev
    return prev[n]


def sec_levenshtein():
    print("========== Levenshtein (start) ==========")
    a = [10, 20, 30, 40, 50, 60]
    b = [10, 25, 30, 35, 40, 50, 65]
    dist = lev_distance(a, b)
    print("levenshtein(a,b) = %d" % dist)
    t0 = now_ms()
    total = 0
    for r in range(5000):
        total += lev_distance(a, b)
    dt = now_ms() - t0
    print("levenshtein x5000 = %d  [%d ms]" % (total, dt))
    print("========== Levenshtein (end) ==========")
    return dt


# ---------------------------------------------------------------- DataTypes

def sec_datatypes():
    print("========== DataTypes (start) ==========")
    t0 = now_ms()
    s32 = 0
    for i in range(2000000):
        s32 += i
    dt1 = now_ms() - t0
    print("Int32 sum 2e6 = %d  [%d ms]  (Python int 无回绕，SL 为 -1455759936)"
          % (s32, dt1))

    t0 = now_ms()
    s64 = 0
    for i in range(2000000):
        s64 += i
    dt2 = now_ms() - t0
    print("Int64 sum 2e6 = %d  [%d ms]" % (s64, dt2))

    t0 = now_ms()
    sf = 0.0
    for i in range(2000000):
        sf += i * 1.5
    dt3 = now_ms() - t0
    print("Num sum 2e6 = %g  [%d ms]" % (sf, dt3))

    t0 = now_ms()
    mix = 0.0
    for i in range(1000000):
        mix = mix + i / 3.0 + i % 7
    dt4 = now_ms() - t0
    print("Mixed ops 1e6 = %g  [%d ms]" % (mix, dt4))

    t0 = now_ms()
    count = 0
    for i in range(1000000):
        if i % 3 == 0 and i % 5 == 0:
            count += 1
    dt5 = now_ms() - t0
    print("bool mod 1e6 = %d  [%d ms]" % (count, dt5))
    print("========== DataTypes (end) ==========")
    return dt1 + dt2 + dt3 + dt4 + dt5


# ---------------------------------------------------------------- StringBench

def sec_stringbench():
    print("========== StringBench (start) ==========")
    t0 = now_ms()
    s = ""
    for i in range(10000):
        s = s + "ab"
    dt1 = now_ms() - t0
    print("concat 1e4  [%d ms]" % dt1)

    t0 = now_ms()
    t = ""
    for i in range(10000):
        t = f"v={i} s={i * 2}"
    dt2 = now_ms() - t0
    print("interp 1e4  [%d ms]" % dt2)

    t0 = now_ms()
    u = ""
    for i in range(10000):
        u = "{0}-{1}".format(i, i + 1)
    dt3 = now_ms() - t0
    print("format 1e4  [%d ms]" % dt3)

    t0 = now_ms()
    c = 0
    for i in range(100000):
        if s == t:
            c += 1
    dt4 = now_ms() - t0
    print("compare 1e5  count=%d  [%d ms]" % (c, dt4))

    print("concat endswith ab = %s" % (s == u))
    print("========== StringBench (end) ==========")
    return dt1 + dt2 + dt3 + dt4


# ---------------------------------------------------------------- RegExpBench

def sec_regexpbench():
    print("========== RegExpBench (start) ==========")
    chunk = "abc123 def456 ghi789 "
    text = chunk * 4000  # 计时外构建，同 SL
    print("text bytes = %d" % len(text.encode("utf-8")))

    t0 = now_ms()
    for i in range(2000):
        re.purge()  # 绕过 re 内部缓存，镜像 SL 每次真编译
        re.compile("([a-z]+)([0-9]+)")
    dt1 = now_ms() - t0
    print("compile x2000  [%d ms]" % dt1)

    re1 = re.compile("def456")
    t0 = now_ms()
    hit = ""
    for i in range(500):
        hit = re1.search(text).group(0)
    dt2 = now_ms() - t0
    print("search hit x500  [%d ms]  value=%s" % (dt2, hit))

    re2 = re.compile("zzz999")
    t0 = now_ms()
    miss = True
    for i in range(20):
        miss = re2.search(text) is None
    dt3 = now_ms() - t0
    print("search miss x20  [%d ms]  miss=%s" % (dt3, miss))

    re3 = re.compile("[a-z]+")
    t0 = now_ms()
    words = 0
    for i in range(5):
        words = len(re3.findall(text))
    dt4 = now_ms() - t0
    print("matchAll x5  [%d ms]  count=%d" % (dt4, words))

    re4 = re.compile("[0-9]+")
    t0 = now_ms()
    rep = ""
    for i in range(5):
        rep = re4.sub("#", text)
    dt5 = now_ms() - t0
    print("replace x5  [%d ms]  len=%d" % (dt5, len(rep)))

    re5 = re.compile("([a-z]+)([0-9]+)")
    t0 = now_ms()
    g1 = ""
    g2 = ""
    for i in range(200):
        m = re5.search(text)
        g1 = m.group(1)
        g2 = m.group(2)
    dt6 = now_ms() - t0
    print("group search x200  [%d ms]  g1=%s g2=%s" % (dt6, g1, g2))

    text2 = "abc abc def def " * 2000
    re6 = re.compile(r"(\w+) \1")
    t0 = now_ms()
    pairs = 0
    for i in range(10):
        pairs = len(re6.findall(text2))
    dt7 = now_ms() - t0
    print("backref matchAll x10  [%d ms]  count=%d" % (dt7, pairs))

    text3 = "中文测试123 " * 2000
    re7 = re.compile("测试[0-9]+")
    t0 = now_ms()
    zh = ""
    for i in range(100):
        zh = re7.search(text3).group(0)
    dt8 = now_ms() - t0
    print("utf8 search x100  [%d ms]  value=%s" % (dt8, zh))
    print("========== RegExpBench (end) ==========")
    return dt1 + dt2 + dt3 + dt4 + dt5 + dt6 + dt7 + dt8


# ---------------------------------------------------------------- main

SECTIONS = [
    ("Fibonacci", sec_fibonacci),
    ("Loop", sec_loop),
    ("Levenshtein", sec_levenshtein),
    ("DataTypes", sec_datatypes),
    ("StringBench", sec_stringbench),
    ("RegExpBench", sec_regexpbench),
]


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    per_round = []  # 每轮各段 ms
    for r in range(rounds):
        print("===== CPython bench round %d/%d =====" % (r + 1, rounds))
        t0 = now_ms()
        times = []
        for name, fn in SECTIONS:
            times.append(fn())
        wall = now_ms() - t0
        per_round.append(times)
        print("===== round %d end [%.0f ms] (sections sum %.0f ms) ====="
              % (r + 1, wall, sum(times)))
        print()

    # 跨轮汇总：各段 min / median + 总计
    print("========== Summary (min / median across %d rounds, ms) =========="
          % rounds)
    totals = []
    for idx, (name, _) in enumerate(SECTIONS):
        vals = sorted(t[idx] for t in per_round)
        med = vals[len(vals) // 2] if len(vals) % 2 == 1 else (vals[len(vals) // 2 - 1] + vals[len(vals) // 2]) / 2.0
        totals.append(vals[0])
        print("%-12s min %8.1f   median %8.1f" % (name, vals[0], med))
    print("%-12s min %8.1f   (sum of per-section min)"
          % ("TOTAL", sum(totals)))


if __name__ == "__main__":
    main()
