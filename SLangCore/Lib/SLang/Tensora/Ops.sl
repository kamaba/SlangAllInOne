import Math;
# Ops —— 张量算子集合（放 Tensor 之外的高层算子）
#
# 包含：
#   卷积相关（im2col / conv2d / maxPool2d / avgPool2d）
#   组合类（concat / stack / oneHot / topK）
#   度量与归一化（cosine / normalize / standardize）
#   自动微分辅助（reduceTo：把梯度按广播逆运算还原到目标形状）

@Nickname("Ops")
public class Ops
{
    # ── im2col：把 [C,H,W] 的输入展开成 [outH*outW, C*k*k] ──
    public static Tensor im2col( Tensor input, Int32 kernel, Int32 stride, Int32 padding )
    {
        int c = input.shape().dims[0]
        int h = input.shape().dims[1]
        int w = input.shape().dims[2]
        int outH = ( h + 2 * padding - kernel ) / stride + 1
        int outW = ( w + 2 * padding - kernel ) / stride + 1
        Tensor col = Tensor( Shape.matrix( outH * outW, c * kernel * kernel ) )
        int row = 0
        for oy = 0, oy < outH, oy++
        {
            for ox = 0, ox < outW, ox++
            {
                int col2 = 0
                for ch = 0, ch < c, ch++
                {
                    for ky = 0, ky < kernel, ky++
                    {
                        for kx = 0, kx < kernel, kx++
                        {
                            int iy = oy * stride - padding + ky
                            int ix = ox * stride - padding + kx
                            Float32 v = 0.0f
                            if iy >= 0
                            {
                                if iy < h
                                {
                                    if ix >= 0
                                    {
                                        if ix < w
                                        {
                                            v = input.at( ch, iy, ix )
                                        }
                                    }
                                }
                            }
                            col.setAt( row, col2, v )
                            col2++
                        }
                    }
                }
                row++
            }
        }
        ret col
    }

    # 单通道卷积（输入 [C,H,W]，卷积核 [C,k,k]，输出 [1,outH,outW]）
    public static Tensor conv2d( Tensor input, Tensor kernel, Int32 stride, Int32 padding )
    {
        int c = input.shape().dims[0]
        int h = input.shape().dims[1]
        int w = input.shape().dims[2]
        int k = kernel.shape().dims[1]
        int outH = ( h + 2 * padding - k ) / stride + 1
        int outW = ( w + 2 * padding - k ) / stride + 1
        Tensor outV = Tensor( Shape.cube( 1, outH, outW ) )
        for oy = 0, oy < outH, oy++
        {
            for ox = 0, ox < outW, ox++
            {
                Float32 acc = 0.0f
                for ch = 0, ch < c, ch++
                {
                    for ky = 0, ky < k, ky++
                    {
                        for kx = 0, kx < k, kx++
                        {
                            int iy = oy * stride - padding + ky
                            int ix = ox * stride - padding + kx
                            if iy >= 0
                            {
                                if iy < h
                                {
                                    if ix >= 0
                                    {
                                        if ix < w
                                        {
                                            acc = acc + input.at( ch, iy, ix ) * kernel.at( ch, ky, kx )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                outV.setAt( 0, oy, ox, acc )
            }
        }
        ret outV
    }

    public static Tensor maxPool2d( Tensor input, Int32 pool, Int32 stride )
    {
        int c = input.shape().dims[0]
        int h = input.shape().dims[1]
        int w = input.shape().dims[2]
        int outH = ( h - pool ) / stride + 1
        int outW = ( w - pool ) / stride + 1
        Tensor outV = Tensor( Shape.cube( c, outH, outW ) )
        for ch = 0, ch < c, ch++
        {
            for oy = 0, oy < outH, oy++
            {
                for ox = 0, ox < outW, ox++
                {
                    Float32 m = input.at( ch, oy * stride, ox * stride )
                    for py = 0, py < pool, py++
                    {
                        for px = 0, px < pool, px++
                        {
                            Float32 v = input.at( ch, oy * stride + py, ox * stride + px )
                            if v > m
                            {
                                m = v
                            }
                        }
                    }
                    outV.setAt( ch, oy, ox, m )
                }
            }
        }
        ret outV
    }

    public static Tensor avgPool2d( Tensor input, Int32 pool, Int32 stride )
    {
        int c = input.shape().dims[0]
        int h = input.shape().dims[1]
        int w = input.shape().dims[2]
        int outH = ( h - pool ) / stride + 1
        int outW = ( w - pool ) / stride + 1
        Tensor outV = Tensor( Shape.cube( c, outH, outW ) )
        Float32 inv = 1.0f / SystemConvertFloat32( pool * pool )
        for ch = 0, ch < c, ch++
        {
            for oy = 0, oy < outH, oy++
            {
                for ox = 0, ox < outW, ox++
                {
                    Float32 acc = 0.0f
                    for py = 0, py < pool, py++
                    {
                        for px = 0, px < pool, px++
                        {
                            acc = acc + input.at( ch, oy * stride + py, ox * stride + px )
                        }
                    }
                    outV.setAt( ch, oy, ox, acc * inv )
                }
            }
        }
        ret outV
    }

    # ── 组合 / 转换 ──────────────────────────────────────
    # axis=0 纵向拼接（增加行），axis=1 横向拼接（增加列）
    public static Tensor concat( Array<Tensor> list, Int32 axis )
    {
        int total = 0
        for i = 0, i < list.length, i++
        {
            if axis == 0
            {
                total = total + list[i].rows()
            }
            else
            {
                total = total + list[i].cols()
            }
        }
        int other = list[0].cols()
        if axis != 0
        {
            other = list[0].rows()
        }
        Tensor r = null
        if axis == 0
        {
            r = Tensor( Shape.matrix( total, other ) )
        }
        else
        {
            r = Tensor( Shape.matrix( other, total ) )
        }
        int cursor = 0
        for i = 0, i < list.length, i++
        {
            Tensor t = list[i]
            for a = 0, a < t.rows(), a++
            {
                for b = 0, b < t.cols(), b++
                {
                    if axis == 0
                    {
                        r.setAt( cursor + a, b, t.at( a, b ) )
                    }
                    else
                    {
                        r.setAt( a, cursor + b, t.at( a, b ) )
                    }
                }
            }
            if axis == 0
            {
                cursor = cursor + t.rows()
            }
            else
            {
                cursor = cursor + t.cols()
            }
        }
        ret r
    }

    # 方法名 stackTensors：stack 是小写容器构造糖（stack() => Stack），类成员名须避让
    public static Tensor stackTensors( Array<Tensor> tensors )
    {
        int rows = tensors.length
        int cols = tensors[0].size()
        Tensor r = Tensor( Shape.matrix( rows, cols ) )
        for i = 0, i < rows, i++
        {
            for j = 0, j < cols, j++
            {
                r.setAt( i, j, tensors[i].at( j ) )
            }
        }
        ret r
    }

    public static Tensor oneHot( Array<Int32> labels, Int32 classCount )
    {
        Tensor r = Tensor( Shape.matrix( labels.length, classCount ) )
        for i = 0, i < labels.length, i++
        {
            r.setAt( i, labels[i], 1.0f )
        }
        ret r
    }

    # 取一维张量中最大的 k 个下标
    public static Array<Int32> topK( Tensor v, Int32 k )
    {
        Array<Int32> idx = Rng.rangeArray( v.size() )
        # 简单选择排序取前 k（数据量大时可换堆）
        for i = 0, i < k, i++
        {
            int best = i
            for j = i + 1, j < idx.length, j++
            {
                if v.at( idx[j] ) > v.at( idx[best] )
                {
                    best = j
                }
            }
            Int32 tmp = idx[i]
            idx[i] = idx[best]
            idx[best] = tmp
        }
        Array<Int32> res = Array<Int32>( k )
        for i = 0, i < k, i++
        {
            res[i] = idx[i]
        }
        ret res
    }

    # ── 参数聚合（复合层用：把子层的参数/梯度摊平成一维数组）──
    public static Array<Tensor> join4( Array<Tensor> a, Array<Tensor> b, Array<Tensor> c, Array<Tensor> d )
    {
        int n = a.length + b.length + c.length + d.length
        Array<Tensor> r = Array<Tensor>( n )
        int k = 0
        for i = 0, i < a.length, i++
        {
            r[k] = a[i]
            k++
        }
        for i = 0, i < b.length, i++
        {
            r[k] = b[i]
            k++
        }
        for i = 0, i < c.length, i++
        {
            r[k] = c[i]
            k++
        }
        for i = 0, i < d.length, i++
        {
            r[k] = d[i]
            k++
        }
        ret r
    }

    public static Array<Tensor> joinLayers( Array<Layer> layers, Int32 kind )
    {
        int n = 0
        for i = 0, i < layers.length, i++
        {
            if kind == 0
            {
                n = n + layers[i].parameters().length
            }
            else
            {
                n = n + layers[i].gradients().length
            }
        }
        Array<Tensor> r = Array<Tensor>( n )
        int k = 0
        for i = 0, i < layers.length, i++
        {
            Array<Tensor> src = null
            if kind == 0
            {
                src = layers[i].parameters()
            }
            else
            {
                src = layers[i].gradients()
            }
            for j = 0, j < src.length, j++
            {
                r[k] = src[j]
                k++
            }
        }
        ret r
    }

    # ── 度量 / 归一化 ────────────────────────────────────
    public static Float32 cosine( Tensor a, Tensor b )
    {
        Float32 dot = 0.0f
        Float32 na = 0.0f
        Float32 nb = 0.0f
        for i = 0, i < a.size(), i++
        {
            Float32 x = a.at( i )
            Float32 y = b.at( i )
            dot = dot + x * y
            na = na + x * x
            nb = nb + y * y
        }
        ret dot / ( Mathf.sqrt( na ) * Mathf.sqrt( nb ) + 0.0000001f )
    }

    public static Tensor normalize( Tensor x )
    {
        Float32 acc = 0.0f
        for i = 0, i < x.size(), i++
        {
            acc = acc + x.at( i ) * x.at( i )
        }
        Float32 norm = Mathf.sqrt( acc ) + 0.0000001f
        ret x.scale( 1.0f / norm )
    }

    public static Tensor standardize( Tensor x, Float32 mean, Float32 std )
    {
        Tensor r = x.addScalar( 0.0f - mean )
        ret r.scale( 1.0f / ( std + 0.0000001f ) )
    }

    # ── 自动微分辅助 ─────────────────────────────────────
    # 把梯度 g 按广播的逆运算累加回 target 形状
    public static Tensor reduceTo( Tensor g, Shape target )
    {
        if g.shape().equals( target )
        {
            ret g.clone()
        }
        Tensor r = Tensor.zeros( target )
        for f = 0, f < g.size(), f++
        {
            Array<Int32> idx = g.shape().unflatten( f )
            Array<Int32> t = Array<Int32>( target.rank() )
            int shift = idx.length - target.rank()
            for i = 0, i < target.rank(), i++
            {
                int src = shift + i
                if src < 0
                {
                    t[i] = 0
                }
                elif target.dims[i] == 1
                {
                    t[i] = 0
                }
                else
                {
                    t[i] = idx[ src ]
                }
            }
            int off = target.offset( t )
            r.setAt( off, r.at( off ) + g.at( f ) )
        }
        ret r
    }

    # ══════════════════════════════════════════════════════
    # 索引算子（设计文档 §2.5 缺口表：index_select/gather/scatter/
    # masked_fill/nonzero；I32 dtype 实装前索引以 F32 承载）
    # ══════════════════════════════════════════════════════

    # 辅助：取张量某维长度（成员链+下标须拆局部变量，SL 语法约束）
    static Int32 dimOf( Tensor t, Int32 axis )
    {
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        ret dm[axis]
    }

    # index_select：沿 axis 取 idxArr 列出的下标组成新张量
    public static Tensor indexSelect( Tensor src, Int32 axis, Array<Int32> idxArr )
    {
        int rk = src.rank()
        int n = idxArr.length
        Array<Int32> outDims = Array<Int32>( rk )
        for a = 0, a < rk, a++
        {
            int dv = Ops.dimOf( src, a )
            if a == axis
            {
                dv = n
            }
            outDims[a] = dv
        }
        Shape outShape = Shape( outDims )
        Tensor res = Tensor( outShape )
        for f = 0, f < outShape.size(), f++
        {
            Array<Int32> oidx = outShape.unflatten( f )
            int pickIdx = idxArr[ oidx[axis] ]
            Array<Int32> sidx = Array<Int32>( rk )
            for a = 0, a < rk, a++
            {
                sidx[a] = oidx[a]
            }
            sidx[axis] = pickIdx
            res.setAt( f, src.at( sidx ) )
        }
        ret res
    }

    # gather：out[..] = src[..（axis 位替换为 idx 值）..]；
    # 输出形状 = idx 形状（对齐 torch.gather）
    public static Tensor gather( Tensor src, Int32 axis, Tensor idx )
    {
        int rk = src.rank()
        Shape idxShape = idx.shape()
        Tensor res = Tensor( idxShape.clone() )
        for f = 0, f < idxShape.size(), f++
        {
            Array<Int32> oidx = idxShape.unflatten( f )
            int iv = SystemConvertInt32( idx.at( f ) )
            Array<Int32> sidx = Array<Int32>( rk )
            for a = 0, a < rk, a++
            {
                sidx[a] = oidx[a]
            }
            sidx[axis] = iv
            res.setAt( f, src.at( sidx ) )
        }
        ret res
    }

    # scatter：out = src 克隆，沿 axis 按 idx 放 value（对齐 torch.scatter）
    public static Tensor scatter( Tensor src, Int32 axis, Tensor idx, Tensor value )
    {
        int rk = src.rank()
        Tensor res = src.clone()
        Shape idxShape = idx.shape()
        for f = 0, f < idxShape.size(), f++
        {
            Array<Int32> oidx = idxShape.unflatten( f )
            int iv = SystemConvertInt32( idx.at( f ) )
            Array<Int32> sidx = Array<Int32>( rk )
            for a = 0, a < rk, a++
            {
                sidx[a] = oidx[a]
            }
            sidx[axis] = iv
            res.setAt( sidx, value.at( f ) )
        }
        ret res
    }

    # masked_fill：mask（广播）非 0 处填 v（对齐 torch.masked_fill）
    public static Tensor maskedFill( Tensor src, Tensor mask, Float32 v )
    {
        Shape broad = Shape.broadcastShape( src.shape(), mask.shape() )
        if broad == null
        {
            ret null
        }
        Tensor res = Tensor( broad )
        for f = 0, f < broad.size(), f++
        {
            Array<Int32> idx = broad.unflatten( f )
            Float32 mv = mask.pick( idx )
            if mv != 0.0f
            {
                res.setAt( f, v )
            }
            else
            {
                res.setAt( f, src.pick( idx ) )
            }
        }
        ret res
    }

    # nonzero：返回非零元素的扁平下标（v1 一维扁平语义）
    public static Array<Int32> nonzero( Tensor t )
    {
        List<Int32> hits = List<Int32>()
        for f = 0, f < t.size(), f++
        {
            Float32 v = t.at( f )
            if v != 0.0f
            {
                hits.add( f )
            }
        }
        Array<Int32> res = Array<Int32>( hits.length )
        for i = 0, i < hits.length, i++
        {
            res[i] = hits._getItem_( i )
        }
        ret res
    }

    # ══════════════════════════════════════════════════════
    # 形状算子（设计文档 §2.5 缺口表：squeeze/unsqueeze/expand/
    # repeat/pad/cat 任意维/stack/flip/narrow/chunk）
    # ══════════════════════════════════════════════════════

    # squeeze：去掉全部长度 1 的维
    public static Tensor squeeze( Tensor t )
    {
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        int kept = 0
        for a = 0, a < rk, a++
        {
            int dv = dm[a]
            if dv != 1
            {
                kept++
            }
        }
        if kept == rk
        {
            ret t.clone()
        }
        Array<Int32> outDims = Array<Int32>( kept )
        int w = 0
        for a = 0, a < rk, a++
        {
            int dv = dm[a]
            if dv != 1
            {
                outDims[w] = dv
                w++
            }
        }
        ret t.reshape( Shape( outDims ) )
    }

    # squeeze 指定轴（仅该轴为 1 时生效）
    public static Tensor squeezeAxis( Tensor t, Int32 axis )
    {
        int dv = Ops.dimOf( t, axis )
        if dv != 1
        {
            ret t.clone()
        }
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        Array<Int32> outDims = Array<Int32>( rk - 1 )
        int w = 0
        for a = 0, a < rk, a++
        {
            if a != axis
            {
                outDims[w] = dm[a]
                w++
            }
        }
        ret t.reshape( Shape( outDims ) )
    }

    # unsqueeze：在 axis 位置插入长度 1 的维
    public static Tensor unsqueeze( Tensor t, Int32 axis )
    {
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        Array<Int32> outDims = Array<Int32>( rk + 1 )
        int w = 0
        for a = 0, a < rk + 1, a++
        {
            if a == axis
            {
                outDims[w] = 1
            }
            else
            {
                outDims[w] = dm[ a - 1 ]
            }
            w++
        }
        ret t.reshape( Shape( outDims ) )
    }

    # expand：尺寸 1 的维扩展到目标形状（复制语义，无 view）
    public static Tensor expand( Tensor t, Shape target )
    {
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        if target.rank() != rk
        {
            ret null
        }
        for a = 0, a < rk, a++
        {
            int dv = dm[a]
            int tv = target.dims[a]
            if dv != 1 && dv != tv
            {
                ret null
            }
        }
        Tensor res = Tensor( target )
        for f = 0, f < target.size(), f++
        {
            Array<Int32> idx = target.unflatten( f )
            res.setAt( f, t.pick( idx ) )
        }
        ret res
    }

    # repeat（tile 语义）：每维重复 tiles[a] 次（对齐 torch.Tensor.repeat）
    public static Tensor repeatTile( Tensor t, Array<Int32> tiles )
    {
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        Array<Int32> outDims = Array<Int32>( rk )
        for a = 0, a < rk, a++
        {
            outDims[a] = dm[a] * tiles[a]
        }
        Shape outShape = Shape( outDims )
        Tensor res = Tensor( outShape )
        for f = 0, f < outShape.size(), f++
        {
            Array<Int32> idx = outShape.unflatten( f )
            Array<Int32> sidx = Array<Int32>( rk )
            for a = 0, a < rk, a++
            {
                sidx[a] = idx[a] % dm[a]
            }
            res.setAt( f, t.at( sidx ) )
        }
        ret res
    }

    # pad：最后一维左右常量填充
    public static Tensor padLastDim( Tensor t, Int32 left, Int32 right, Float32 v )
    {
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        int last = dm[ rk - 1 ]
        Array<Int32> outDims = Array<Int32>( rk )
        for a = 0, a < rk, a++
        {
            outDims[a] = dm[a]
        }
        outDims[ rk - 1 ] = last + left + right
        Shape outShape = Shape( outDims )
        Tensor res = Tensor( outShape, v )
        for f = 0, f < s.size(), f++
        {
            Array<Int32> idx = s.unflatten( f )
            Array<Int32> oidx = Array<Int32>( rk )
            for a = 0, a < rk, a++
            {
                oidx[a] = idx[a]
            }
            int lc = idx[ rk - 1 ]
            oidx[ rk - 1 ] = lc + left
            res.setAt( oidx, t.at( f ) )
        }
        ret res
    }

    # cat 任意维（对齐 torch.cat）：沿 axis 拼接，其余维须一致
    public static Tensor catTensors( Array<Tensor> list, Int32 axis )
    {
        int n = list.length
        Tensor first = list[0]
        int rk = first.rank()
        int total = 0
        for i = 0, i < n, i++
        {
            total = total + Ops.dimOf( list[i], axis )
        }
        Array<Int32> outDims = Array<Int32>( rk )
        for a = 0, a < rk, a++
        {
            int dv = Ops.dimOf( first, a )
            if a == axis
            {
                dv = total
            }
            outDims[a] = dv
        }
        Shape outShape = Shape( outDims )
        Tensor res = Tensor( outShape )
        Array<Int32> starts = Array<Int32>( n )
        int acc = 0
        for i = 0, i < n, i++
        {
            starts[i] = acc
            acc = acc + Ops.dimOf( list[i], axis )
        }
        for f = 0, f < outShape.size(), f++
        {
            Array<Int32> idx = outShape.unflatten( f )
            int c = idx[axis]
            int k = 0
            for i = 0, i < n, i++
            {
                int st = starts[i]
                int en = st + Ops.dimOf( list[i], axis )
                if c >= st && c < en
                {
                    k = i
                }
            }
            Tensor src = list[k]
            int st2 = starts[k]
            Array<Int32> sidx = Array<Int32>( rk )
            for a = 0, a < rk, a++
            {
                sidx[a] = idx[a]
            }
            sidx[axis] = c - st2
            res.setAt( f, src.at( sidx ) )
        }
        ret res
    }

    # stack：新轴堆叠（对齐 torch.stack）；全部张量同形状
    public static Tensor stackAxis( Array<Tensor> list, Int32 axis )
    {
        int n = list.length
        Tensor first = list[0]
        Shape s = first.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        Array<Int32> outDims = Array<Int32>( rk + 1 )
        int w = 0
        for a = 0, a < rk + 1, a++
        {
            if a == axis
            {
                outDims[w] = n
            }
            else
            {
                outDims[w] = dm[ a - 1 ]
            }
            w++
        }
        Shape outShape = Shape( outDims )
        Tensor res = Tensor( outShape )
        for f = 0, f < outShape.size(), f++
        {
            Array<Int32> idx = outShape.unflatten( f )
            int which = idx[axis]
            Array<Int32> sidx = Array<Int32>( rk )
            int w2 = 0
            for a = 0, a < rk + 1, a++
            {
                if a != axis
                {
                    sidx[w2] = idx[a]
                    w2++
                }
            }
            Tensor src = list[which]
            res.setAt( f, src.at( sidx ) )
        }
        ret res
    }

    # flip：沿 axis 反转（对齐 torch.flip）
    public static Tensor flip( Tensor t, Int32 axis )
    {
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        int d = dm[axis]
        Tensor res = Tensor( s.clone() )
        for f = 0, f < s.size(), f++
        {
            Array<Int32> idx = s.unflatten( f )
            idx[axis] = d - 1 - idx[axis]
            res.setAt( idx, t.at( f ) )
        }
        ret res
    }

    # narrow：沿 axis 切片 [start, start+length)（对齐 torch.narrow）
    public static Tensor narrow( Tensor t, Int32 axis, Int32 start, Int32 length )
    {
        Shape s = t.shape()
        Array<Int32> dm = s.dims
        int rk = dm.length
        Array<Int32> outDims = Array<Int32>( rk )
        for a = 0, a < rk, a++
        {
            outDims[a] = dm[a]
        }
        outDims[axis] = length
        Shape outShape = Shape( outDims )
        Tensor res = Tensor( outShape )
        for f = 0, f < outShape.size(), f++
        {
            Array<Int32> oidx = outShape.unflatten( f )
            Array<Int32> sidx = Array<Int32>( rk )
            for a = 0, a < rk, a++
            {
                sidx[a] = oidx[a]
            }
            sidx[axis] = oidx[axis] + start
            res.setAt( f, t.at( sidx ) )
        }
        ret res
    }

    # chunk：沿 axis 均分 n 块（不整除时前面块更大，对齐 torch.chunk）
    public static Array<Tensor> chunk( Tensor t, Int32 n, Int32 axis )
    {
        int d = Ops.dimOf( t, axis )
        int baseLen = d / n
        int rem = d % n
        Array<Tensor> res = Array<Tensor>( n )
        int start = 0
        for i = 0, i < n, i++
        {
            int len = baseLen
            if i < rem
            {
                len = baseLen + 1
            }
            res[i] = Ops.narrow( t, axis, start, len )
            start = start + len
        }
        ret res
    }
}
