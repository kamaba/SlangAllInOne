import Tensora

import Math;

# =============================================================
# Txt2WavModel.sl —— 神经网络层（仿 Tacotron：编码器 + 注意力解码器）
#
# 混合路线：网络结构是真实的神经组件（Embedding / GRU / softmax 注意力 /
# Dense postnet，全部经 Tensora 前向计算），参数由规则设定而非训练——
# 训练要学的"音素声学映射"，这里直接用语音学规则表注入权重。
#
#   Embedding: 音素 id → 8 维声学特征（共振峰/浊音/振幅/时长/噪声/带宽）
#   GRU 编码器: 权重注入为"一阶惯性环节"——隐状态 ≈ 0.35·x + 0.64·h_prev，
#              效果 = 音素间协同发音（coarticulation）平滑
#   注意力解码器: 规则焦点位置 + softmax → 帧级参数（音素边界交叉淡化），
#              等价 FastSpeech 的时长扩展 + Location-Sensitive Attention
#   Postnet Dense: 振幅补偿（浊音分量加成）后再输出帧级声学参数
#
# 特征布局（8 维）：
#   0 F1n=F1/2000   1 F2n=F2/6000   2 F3n=F3/4000   3 voiced
#   4 amp·0.5       5 durMs/250     6 noiseMix·0.5  7 bwN·0.5
# =============================================================

public class Txt2WavEncoder
{
    public Embedding embed = null
    public GRUCell gru = null
    public Int32 dim = 8

    _init_( Int32 vocabSize )
    {
        this.embed = Embedding( vocabSize, this.dim )
        this.gru = GRUCell( this.dim, this.dim )
        this.applyRules()
    }

    # ── 规则参数注入 ─────────────────────────────────────
    # 嵌入表：直接写音素声学特征（scaled 到 |x| ≤ 0.5，控 tanh 失真）
    # GRU：z 门偏置 = logit(0.65)、r 门偏置 = 4（≈全开）、
    #      n 门输入权重 = 单位阵 → h' ≈ 0.35·tanh(x) + 0.64·h_prev
    void applyRules()
    {
        Txt2WavLexicon lex = Txt2WavLexicon()
        Int32 fd = lex.featDim
        Int32 p = 0
        while p < lex.phoneCount
        {
            Int32 rowBase = p * fd
            Float32 f1 = lex.feats[ rowBase + 0 ]
            Float32 f2 = lex.feats[ rowBase + 1 ]
            Float32 f3 = lex.feats[ rowBase + 2 ]
            Float32 voiced = lex.feats[ rowBase + 3 ]
            Float32 amp = lex.feats[ rowBase + 4 ]
            Float32 dur = lex.feats[ rowBase + 5 ]
            Float32 nmx = lex.feats[ rowBase + 6 ]
            Float32 bwn = lex.feats[ rowBase + 7 ]

            this.embed.table.setAt( p, 0, f1 / 2000.0f )
            this.embed.table.setAt( p, 1, f2 / 6000.0f )
            this.embed.table.setAt( p, 2, f3 / 4000.0f )
            this.embed.table.setAt( p, 3, voiced )
            this.embed.table.setAt( p, 4, amp * 0.5f )
            this.embed.table.setAt( p, 5, dur / 250.0f )
            this.embed.table.setAt( p, 6, nmx * 0.5f )
            this.embed.table.setAt( p, 7, bwn * 0.5f )
            p = p + 1
        }

        # GRU 规则权重：wAll 形状 [3h, in+h]（行=门，列=输入），forward 用 concat·wAllᵀ
        # 全零后 n 门（行 2h..3h-1）输入块放单位阵 → z_n = tanh(x)
        this.gru.wAll.fillValue( 0.0f )
        Int32 h = this.dim
        Int32 j = 0
        while j < h
        {
            this.gru.wAll.setAt( 2 * h + j, j, 1.0f )
            j = j + 1
        }
        # 偏置：z 门 0.62（σ≈0.65 续航权重）、r 门 4.0（σ≈0.98 全开）、n 门 0
        this.gru.bias.fillValue( 0.0f )
        j = 0
        while j < h
        {
            this.gru.bias.setAt( 0, j, 0.62f )
            this.gru.bias.setAt( 0, h + j, 4.0f )
            j = j + 1
        }
    }

    # ids: [P] → encOut: [P, 8]（协同发音平滑后的音素声学特征）
    Tensor forward( Array<Int32> ids )
    {
        Int32 pcount = ids.length
        # 每句重置 GRU 隐状态（避免跨句泄漏）
        this.gru.hPrev = Tensor( Shape.matrix( 1, this.dim ) )
        Tensor idsT = Tensor( Shape.matrix( pcount, 1 ) )
        Int32 i = 0
        while i < pcount
        {
            idsT.setAt( i, 0, SystemConvertFloat32( ids[ i ] ) )
            i = i + 1
        }
        Tensor x = this.embed.forward( idsT )
        Tensor outV = Tensor( Shape.matrix( pcount, this.dim ) )
        i = 0
        while i < pcount
        {
            Tensor ht = this.gru.forward( x.row( i ) )
            Int32 j = 0
            while j < this.dim
            {
                outV.setAt( i, j, ht.at( 0, j ) )
                j = j + 1
            }
            i = i + 1
        }
        ret outV
    }
}

public class Txt2WavDecoder
{
    public Dense postnet = null
    public Int32 dim = 8

    # 帧时长（毫秒）：16000Hz / hop 256 = 16ms
    public Int32 frameMs = 16

    _init_()
    {
        this.postnet = Dense( this.dim, this.dim )
        this.applyRules()
    }

    # Postnet 规则权重：恒等映射 + 振幅行加 0.2·voiced（浊音响度补偿）
    void applyRules()
    {
        this.postnet.weight.fillValue( 0.0f )
        this.postnet.bias.fillValue( 0.0f )
        Int32 j = 0
        while j < this.dim
        {
            this.postnet.weight.setAt( j, j, 1.0f )
            j = j + 1
        }
        this.postnet.weight.setAt( 4, 3, 0.2f )
    }

    # ── 解码：注意力把音素级特征展开为帧级特征 ───────────
    # enc: [P, 8]（CPU 张量），durs: 每音素帧数，dev: 目标设备
    # 返回 ctx: [T, 8]（在 dev 上）
    Tensor forward( Tensor enc, Array<Int32> durs, Device dev )
    {
        Int32 pcount = durs.length
        Int32 total = 0
        Int32 p = 0
        while p < pcount
        {
            total = total + durs[ p ]
            p = p + 1
        }
        if total < 2
        {
            total = 2
        }

        # 焦点位置：帧 t 属于哪个音素（硬对齐，softmax 后边界自动软化）
        Array<Float32> focus = Array<Float32>( total )
        Int32 t = 0
        p = 0
        while p < pcount
        {
            Int32 k = 0
            while k < durs[ p ]
            {
                if t < total
                {
                    focus[ t ] = SystemConvertFloat32( p )
                    t = t + 1
                }
                k = k + 1
            }
            p = p + 1
        }
        while t < total
        {
            focus[ t ] = SystemConvertFloat32( pcount - 1 )
            t = t + 1
        }

        Tensor focusCol = Tensor( focus, Shape.matrix( total, 1 ) )
        # J 行向量 [1, P] = 0..P-1
        Array<Float32> jarr = Array<Float32>( pcount )
        Int32 q = 0
        while q < pcount
        {
            jarr[ q ] = SystemConvertFloat32( q )
            q = q + 1
        }
        Tensor jRow = Tensor( jarr, Shape.matrix( 1, pcount ) )
        Tensor onesRowP = Tensor.ones( Shape.matrix( 1, pcount ) )
        Tensor onesColT = Tensor.ones( Shape.matrix( total, 1 ) )

        # 注意力打分：logits[t,j] = -18·(focus(t) - j)²（单调对齐）
        Tensor fTile = focusCol.matmul( onesRowP )
        Tensor jTile = onesColT.matmul( jRow )
        Tensor logits = fTile.sub( jTile ).square().scale( -18.0f )

        Device devT = dev
        Tensor logitsD = logits.to( devT )
        Tensor attn = logitsD.softmax()

        Tensor encD = enc.to( devT )
        Tensor ctx = attn.matmul( encD )

        # Postnet（GPU 上跑 Dense 前向）
        Tensor postW = this.postnet.weight.to( devT )
        Tensor postB = this.postnet.bias.to( devT )
        Tensor outV = ctx.matmul( postW.transpose() ).add( postB )
        postW.freeDevice()
        postB.freeDevice()
        ret outV
    }

    # ── F0 轨迹（规则韵律）：降调陈述句 / 升调疑问句 + 微颤音 ──
    Array<Float32> makeF0( Int32 frames, bool rising )
    {
        Array<Float32> f0 = Array<Float32>( frames )
        Int32 t = 0
        Int32 denom = frames - 1
        if denom < 1
        {
            denom = 1
        }
        while t < frames
        {
            Float32 prog = SystemConvertFloat32( t ) / SystemConvertFloat32( denom )
            if frames < 2
            {
                prog = 0.0f
            }
            Float32 f0base = 115.0f
            if rising
            {
                f0base = 112.0f * ( 0.86f + 0.34f * prog )
            }
            else
            {
                f0base = 115.0f * ( 1.0f - 0.14f * prog )
            }
            Float32 vib = 3.5f * Mathf.sin( 6.2831853f * 4.2f * SystemConvertFloat32( t ) * 0.016f )
            f0[ t ] = f0base + vib
            t = t + 1
        }
        ret f0
    }
}
