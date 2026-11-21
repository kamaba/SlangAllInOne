# Trainer / History —— 训练循环
#
# 典型用法：
#   Module model = Sequential()
#   model.add( Dense(784, 256, EActivation.Relu) )
#   model.add( Dense(256, 10) )
#   Optimizer opt = Adam(0.001f)
#   Trainer t = Trainer(model, opt, "crossEntropy")
#   t.fit( trainSet, valSet )
#
# 支持的 loss 名：mse / mae / bce / crossEntropy

@Nickname("History")
public class History
{
    public List<Float32> trainLoss = null
    public List<Float32> valLoss = null
    public List<Float32> trainAcc = null
    public List<Float32> valAcc = null

    public void _init_()
    {
        this.trainLoss = List<Float32>()
        this.valLoss = List<Float32>()
        this.trainAcc = List<Float32>()
        this.valAcc = List<Float32>()
    }

    public void addTrain( Float32 loss, Float32 acc )
    {
        this.trainLoss.add( loss )
        this.trainAcc.add( acc )
    }

    public void addVal( Float32 loss, Float32 acc )
    {
        this.valLoss.add( loss )
        this.valAcc.add( acc )
    }

    public get int length()
    {
        ret this.trainLoss.length
    }

    public Float32 lastTrainLoss()
    {
        List<Float32> ls = this.trainLoss
        if ls.length == 0
        {
            ret 0.0f
        }
        ret ls._getItem_( ls.length - 1 )
    }

    public Float32 lastValAcc()
    {
        List<Float32> va = this.valAcc
        if va.length == 0
        {
            ret 0.0f
        }
        ret va._getItem_( va.length - 1 )
    }
}

@Nickname("Trainer")
public class Trainer
{
    public Module model = null
    public Optimizer optimizer = null
    public string lossName = "crossEntropy"
    public LRScheduler scheduler = null
    public History history = null

    public Int32 epochs = 1
    public Int32 batchSize = 32
    public Int32 logEvery = 1
    public bool verbose = true

    public void _init_( Module model, Optimizer optimizer, string lossName )
    {
        this.model = model
        this.optimizer = optimizer
        this.lossName = lossName
        this.history = History()
        this.scheduler = null
        this.epochs = 1
        this.batchSize = 32
        this.logEvery = 1
        this.verbose = true
    }

    # ── 损失与梯度分派 ───────────────────────────────────
    public Float32 lossValue( Tensor pred, Tensor target, Array<Int32> labels )
    {
        if this.lossName == "mse"
        {
            ret Loss.mse( pred, target )
        }
        if this.lossName == "mae"
        {
            ret Loss.mae( pred, target )
        }
        if this.lossName == "bce"
        {
            ret Loss.bce( pred, target )
        }
        ret Loss.crossEntropy( pred, labels )
    }

    public Tensor lossGrad( Tensor pred, Tensor target, Array<Int32> labels )
    {
        if this.lossName == "mse"
        {
            ret Loss.mseGrad( pred, target )
        }
        if this.lossName == "mae"
        {
            ret Loss.maeGrad( pred, target )
        }
        if this.lossName == "bce"
        {
            ret Loss.bceGrad( pred, target )
        }
        ret Loss.crossEntropyGrad( pred, labels )
    }

    # ── 单批训练 ─────────────────────────────────────────
    void trainBatch( Batch b )
    {
        this.model.zeroGrad()
        Tensor pred = this.model.forward( b.x )
        Tensor g = this.lossGrad( pred, b.y, b.labels )
        this.model.backward( g )
        this.optimizer.step( this.model.parameters(), this.model.gradients() )
        if this.scheduler != null
        {
            this.scheduler.step()
        }
    }

    # ── 主循环 ───────────────────────────────────────────
    public void fit( Dataset train, Dataset val )
    {
        for e = 0, e < this.epochs, e++
        {
            this.model.train( true )
            DataLoader dl = DataLoader( train, this.batchSize, true, false )
            dl.reset()
            Float32 lossSum = 0.0f
            Float32 accSum = 0.0f
            int batches = 0
            while dl.hasNext()
            {
                Batch b = dl.nextBatch()
                this.trainBatch( b )
                Tensor pred = this.model.forward( b.x )
                lossSum = lossSum + this.lossValue( pred, b.y, b.labels )
                accSum = accSum + Metrics.accuracy( pred, b.labels )
                batches++
            }
            Float32 trainLoss = lossSum / SystemConvertFloat32( batches )
            Float32 trainAcc = accSum / SystemConvertFloat32( batches )

            Float32 valLoss = 0.0f
            Float32 valAcc = 0.0f
            if val != null
            {
                valAcc = this.evaluate( val )
                valLoss = this.evaluateLoss( val )
            }
            this.history.addTrain( trainLoss, trainAcc )
            this.history.addVal( valLoss, valAcc )

            if this.verbose
            {
                if e % this.logEvery == 0
                {
                    SystemPrintln( "epoch " + SystemConvertString( e ) + " loss=" + SystemConvertString( trainLoss ) + " acc=" + SystemConvertString( trainAcc ) + " val_acc=" + SystemConvertString( valAcc ) )
                }
            }
        }
    }

    public void fit( Dataset train )
    {
        this.fit( train, null )
    }

    # ── 评估 ─────────────────────────────────────────────
    public Float32 evaluate( Dataset ds )
    {
        this.model.eval()
        DataLoader dl = DataLoader( ds, this.batchSize, false, false )
        dl.reset()
        int hit = 0
        int total = 0
        while dl.hasNext()
        {
            Batch b = dl.nextBatch()
            Array<Int32> pred = Metrics.predictLabels( this.model.forward( b.x ) )
            for i = 0, i < pred.length, i++
            {
                if pred[i] == b.labels[i]
                {
                    hit++
                }
            }
            total = total + pred.length
        }
        this.model.train( true )
        if total == 0
        {
            ret 0.0f
        }
        ret SystemConvertFloat32( hit ) / SystemConvertFloat32( total )
    }

    public Float32 evaluateLoss( Dataset ds )
    {
        this.model.eval()
        DataLoader dl = DataLoader( ds, this.batchSize, false, false )
        dl.reset()
        Float32 acc = 0.0f
        int batches = 0
        while dl.hasNext()
        {
            Batch b = dl.nextBatch()
            Tensor pred = this.model.forward( b.x )
            acc = acc + this.lossValue( pred, b.y, b.labels )
            batches++
        }
        this.model.train( true )
        if batches == 0
        {
            ret 0.0f
        }
        ret acc / SystemConvertFloat32( batches )
    }

    # ── 推理 ─────────────────────────────────────────────
    public Tensor predict( Tensor x )
    {
        this.model.eval()
        Tensor outV = this.model.forward( x )
        this.model.train( true )
        ret outV
    }

    public Array<Int32> predictLabels( Tensor x )
    {
        ret Metrics.predictLabels( this.predict( x ) )
    }
}
