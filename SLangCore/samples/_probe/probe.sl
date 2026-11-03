import Std

ProbeF
{
    static Fun()
    {
        l = list()
        l.add("a")
        l.add("b")
        i = 0
        x = l[i]
        for k = 0, k < l.length, k++
        {
            x = l[k]
        }
    }
}

ProbeG
{
    static Fun()
    {
        a = list()
        a.add("a")
        b = list()
        b.add("b")
        c = list()
        for v in a
        {
            c.add(v)
        }
        for v in b
        {
            c.add(v)
        }
    }
}
