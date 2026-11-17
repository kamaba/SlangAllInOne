import Std

# P2 : two-field probe class (x-component-loss symptom from MathTest)
P2
{
    int x = 0
    int y = 0

    _init_(int a, int b)
    {
        this.x = a
        this.y = b
    }

    int add()
    {
        ret this.x + this.y
    }

    int dot(P2 b)
    {
        ret this.x * b.x + this.y * b.y
    }

    bool eq(P2 b)
    {
        ret this.x == b.x && this.y == b.y
    }

    # same shape as Float16_3x3._ne_ = ret !this._eq_(b)
    bool ne(P2 b)
    {
        ret !this.eq(b)
    }
}

JitSeamTest
{
    # check : concat + if/else (CMP_BR fusion candidate inside a callee)
    static check(bool cond, string name)
    {
        if (cond)
        {
            Console.println("[PASS] " + name)
        }
        else
        {
            Console.println("[FAIL] " + name)
        }
    }

    # addi : int params arithmetic in callee
    static int addi(int a, int b)
    {
        ret a + b
    }

    # mark : string concat returning from callee (prefix-loss symptom)
    static string mark(string name)
    {
        ret "[A] " + name
    }

    static probe(string tag)
    {
        Console.println("---- probe " + tag + " ----")
        Console.println("addi(2,3) = " + addi(2, 3))
        P2 p = P2(1, 2)
        P2 q = P2(3, 4)
        Console.println("p.add() = " + p.add())
        Console.println("p.dot(q) = " + p.dot(q))
        Console.println("mark() = " + mark("tail"))
        check(addi(2, 3) == 5, "addi(2,3)==5 [" + tag + "]")
        check(p.add() == 3, "p.add()==3 [" + tag + "]")
        check(p.dot(q) == 11, "p.dot(q)==11 [" + tag + "]")
        check(p.ne(q), "p.ne(q) [" + tag + "]")
        check(!p.ne(p), "!p.ne(p) [" + tag + "]")
    }

    static fun()
    {
        Console.println("===== JitSeamTest (start) =====")

        # round 1 : before JIT threshold (interpreted under default config)
        probe("round1")

        # warmup : cross the default JIT threshold (1500) for every probe callee
        acc = 0
        for i = 0, i < 3000, i++
        {
            acc += addi(i, 1)
            check(true, "warm")
        }
        Console.println("warm acc = " + acc)

        P2 w1 = P2(1, 2)
        P2 w2 = P2(3, 4)
        dacc = 0
        nacc = 0
        for i = 0, i < 3000, i++
        {
            dacc += w1.dot(w2)
            if (w1.ne(w2))
            {
                nacc++
            }
        }
        Console.println("warm dacc = " + dacc + " nacc = " + nacc)

        # round 2 : after threshold (JIT-compiled under default config)
        probe("round2")
        Console.println("===== JitSeamTest (end) =====")
    }
}
