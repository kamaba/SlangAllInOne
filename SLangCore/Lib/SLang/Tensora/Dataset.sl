import Math;
# Dataset / DataLoader / Batch / Normalizer —— 数据管道
#
# Dataset   ：特征矩阵 x [N, F] + 标签 y（[N,1] 类别 id 或 [N,C] one-hot）
# DataLoader：按 batch 迭代，支持打乱与丢弃末尾不足一批的数据
# Normalizer：按列统计均值/方差做标准化
# Batch     ：一个批次的 x / y / labels

@Nickname("Batch")
public class Batch
{
    public Tensor x = null
    public Tensor y = null
    public Array<Int32> labels = null
    public int size = 0

    public void _init_( Tensor x, Tensor y, Array<Int32> labels )
    {
        this.x = x
        this.y = y
        this.labels = labels
        this.size = x.rows()
    }
}

@Nickname("Dataset")
public class Dataset
{
    public Tensor x = null
    public Tensor y = null
    public string name = "dataset"

    public void _init_( Tensor x, Tensor y )
    {
        this.x = x
        this.y = y
        this.name = "dataset"
    }

    public void _init_( Tensor x, Tensor y, string name )
    {
        this.x = x
        this.y = y
        this.name = name
    }

    get int count()
    {
        ret this.x.rows()
    }

    get int featureCount()
    {
        ret this.x.cols()
    }

    # y 为 one-hot 时取列数，否则取最大类别 + 1
    get int classCount()
    {
        if this.y.cols() > 1
        {
            ret this.y.cols()
        }
        int mx = 0
        for i = 0, i < this.y.rows(), i++
        {
            int v = SystemConvertInt32( this.y.at( i, 0 ) )
            if v > mx
            {
                mx = v
            }
        }
        ret mx + 1
    }

    # 第 i 个样本的类别 id（支持 one-hot）
    Int32 labelAt( int i )
    {
        if this.y.cols() > 1
        {
            int best = 0
            Float32 m = this.y.at( i, 0 )
            for j = 1, j < this.y.cols(), j++
            {
                if this.y.at( i, j ) > m
                {
                    m = this.y.at( i, j )
                    best = j
                }
            }
            ret best
        }
        ret SystemConvertInt32( this.y.at( i, 0 ) )
    }

    Array<Int32> labels()
    {
        int n = this.count()
        Array<Int32> res = Array<Int32>( n )
        for i = 0, i < n, i++
        {
            res[i] = this.labelAt( i )
        }
        ret res
    }

    # 按给定下标取子集
    Dataset gather( Array<Int32> indices )
    {
        int n = indices.length
        Tensor nx = Tensor( Shape.matrix( n, this.featureCount() ) )
        Tensor ny = Tensor( Shape.matrix( n, this.y.cols() ) )
        for i = 0, i < n, i++
        {
            for j = 0, j < this.x.cols(), j++
            {
                nx.setAt( i, j, this.x.at( indices[i], j ) )
            }
            for j = 0, j < this.y.cols(), j++
            {
                ny.setAt( i, j, this.y.at( indices[i], j ) )
            }
        }
        ret Dataset( nx, ny, this.name )
    }

    # 原地打乱（保持 x / y 对齐）
    void shuffle()
    {
        Array<Int32> order = Rng.current().permutation( this.count() )
        Dataset d = this.gather( order )
        this.x = d.x
        this.y = d.y
    }

    # 切分：前 ratio 为 train，其余为 val
    Dataset trainPart( Float32 ratio )
    {
        int n = this.count()
        int tn = SystemConvertInt32( SystemConvertFloat32( n ) * ratio )
        Array<Int32> idx = Array<Int32>( tn )
        for i = 0, i < tn, i++
        {
            idx[i] = i
        }
        ret this.gather( idx )
    }

    Dataset valPart( Float32 ratio )
    {
        int n = this.count()
        int tn = SystemConvertInt32( SystemConvertFloat32( n ) * ratio )
        int vn = n - tn
        Array<Int32> idx = Array<Int32>( vn )
        for i = 0, i < vn, i++
        {
            idx[i] = tn + i
        }
        ret this.gather( idx )
    }

    override string toString()
    {
        ret "Dataset(" + this.name + ", n=" + SystemConvertString( this.count() ) + ", f=" + SystemConvertString( this.featureCount() ) + ")"
    }
}

@Nickname("DataLoader")
public class DataLoader
{
    public Dataset ds = null
    public Int32 batchSize = 32
    public bool shuffle = true
    public bool dropLast = false

    Array<Int32> _order = null
    int _cursor = 0
    int _batchCount = 0

    public void _init_( Dataset ds, Int32 batchSize )
    {
        this._init_( ds, batchSize, true, false )
    }

    public void _init_( Dataset ds, Int32 batchSize, bool shuffle, bool dropLast )
    {
        this.ds = ds
        this.batchSize = batchSize
        this.shuffle = shuffle
        this.dropLast = dropLast
        this._order = Rng.rangeArray( ds.count() )
        this._cursor = 0
        this._batchCount = ds.count() / batchSize
        if !this.dropLast
        {
            if ds.count() % batchSize != 0
            {
                this._batchCount = this._batchCount + 1
            }
        }
    }

    get int batchCount()
    {
        ret this._batchCount
    }

    # 开始新一轮遍历
    void reset()
    {
        this._cursor = 0
        if this.shuffle
        {
            this._order = Rng.current().shuffle( this._order )
        }
    }

    bool hasNext()
    {
        ret this._cursor < this._batchCount
    }

    # 取第 i 批（不改变游标）
    Batch at( Int32 i )
    {
        int start = i * this.batchSize
        int end = start + this.batchSize
        if end > this.ds.count()
        {
            end = this.ds.count()
        }
        int n = end - start
        Array<Int32> idx = Array<Int32>( n )
        for k = 0, k < n, k++
        {
            idx[k] = this._order[ start + k ]
        }
        Dataset sub = this.ds.gather( idx )
        ret Batch( sub.x, sub.y, sub.labels() )
    }

    # next 为保留字，改名 nextBatch()
    Batch nextBatch()
    {
        Batch b = this.at( this._cursor )
        this._cursor = this._cursor + 1
        ret b
    }
}

@Nickname("Normalizer")
public class Normalizer
{
    public Tensor mean = null
    public Tensor std = null

    public void _init_()
    {
        this.mean = null
        this.std = null
    }

    # 按列统计（x: [N, F]）
    void fit( Tensor x )
    {
        this.mean = x.sumAlong( 0 ).scale( 1.0f / SystemConvertFloat32( x.rows() ) )
        Tensor stdT = Tensor( this.mean.shape() )
        for j = 0, j < x.cols(), j++
        {
            Float32 acc = 0.0f
            for i = 0, i < x.rows(), i++
            {
                Float32 d = x.at( i, j ) - this.mean.at( 0, j )
                acc = acc + d * d
            }
            stdT.setAt( 0, j, Mathf.sqrt( acc / SystemConvertFloat32( x.rows() ) ) + 0.0000001f )
        }
        this.std = stdT
    }

    Tensor transform( Tensor x )
    {
        ret x.sub( this.mean ).div( this.std )
    }

    Tensor inverse( Tensor x )
    {
        ret x.mul( this.std ).add( this.mean )
    }
}
