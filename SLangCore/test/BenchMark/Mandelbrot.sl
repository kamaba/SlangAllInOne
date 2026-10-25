import Std

# Mandelbrot - 曼德博集合基准：浮点迭代 + 逃逸判断 + 边界统计
# 浮点字面量统一带 d 后缀（无后缀默认 Float32，带 d 走 Float64，与 Python double 同口径）
# 区域 [-2,2) x [-2,2)，iterSum 累加全部迭代次数，inside 统计未逃逸点数
Mandelbrot
{
    static Int64 iterSum = 0L
    static int insideCount = 0

    static fun()
    {
        Console.println("========== Mandelbrot (start) ==========")

        w = 240
        h = 180
        maxIter = 150
        rounds = 3

        nowMs = Environment.sys.nowMillis()
        for r = 0, r < rounds, r++
        {
            Mandelbrot.render(w, h, maxIter)
        }
        nowMs = Environment.sys.nowMillis() - nowMs
        Console.println("mandelbrot 240x180 x3  [$nowMs.toString() ms]  iterSum = " + Mandelbrot.iterSum.toString() + "  inside = " + Mandelbrot.insideCount.toString())

        Console.println("========== Mandelbrot (end) ==========")
    }

    # 渲染一帧，累计迭代总数与集合内点数（静态字段跨轮累加）
    static render(int w, int h, int maxIter)
    {
        for py = 0, py < h, py++
        {
            y0 = py * 4.0d / h - 2.0d
            for px = 0, px < w, px++
            {
                x0 = px * 4.0d / w - 2.0d
                x = 0.0d
                y = 0.0d
                iter = 0
                while (iter < maxIter && x * x + y * y <= 4.0d)
                {
                    xtemp = x * x - y * y + x0
                    y = 2.0d * x * y + y0
                    x = xtemp
                    iter++
                }
                Mandelbrot.iterSum += iter
                if (iter == maxIter)
                {
                    Mandelbrot.insideCount++
                }
            }
        }
    }
}
