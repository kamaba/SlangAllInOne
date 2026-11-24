import Tensora

import Math;

import Std

import SLangAudio;

# =============================================================
# Txt2Wav.sl —— 主管线 + 控制台 demo
#
# 用法：
#   slang Txt2Wav.jsonc            （编译 + 运行）
# 运行形态：
#   自动探测 CUDA：可用 → gpu_cuda，否则 cpu
#   内置 3 句英文演示（前两句最短，保证首响应速度）
#   之后进入交互模式：输入英文合成；行前缀 "cpu:" / "gpu:" 强制设备；
#   空行 / quit / exit 退出
# 输出：
#   每句合成 txt2wav_N.wav（16kHz 单声道 16bit PCM，写入当前目录）
# =============================================================

# ── 引擎：组装前端 / 编码器 / 解码器 / 声码器 ──────────────
public class Txt2WavEngine
{
    public Txt2WavFrontend frontend = null
    public Txt2WavEncoder encoder = null
    public Txt2WavDecoder decoder = null
    public Txt2WavVocoder vocoder = null
    public Device dev = null
    public bool useGpu = false

    # 最近一次合成的统计
    public Int32 lastPhones = 0
    public Int32 lastFrames = 0
    public Int32 lastSamples = 0
    public Int64 lastFrontendMs = 0
    public Int64 lastNeuralMs = 0
    public Int64 lastVocoderMs = 0
    public Int32 synthCount = 0

    _init_( bool wantGpu )
    {
        Backends.setCudaEnabled( true )
        bool gpu = false
        if wantGpu
        {
            if Backends.available( EDeviceKind.GPU )
            {
                gpu = true
            }
        }
        this.useGpu = gpu
        if gpu
        {
            this.dev = Device.gpu( 0 )
        }
        else
        {
            this.dev = Device.cpu()
        }
        this.frontend = Txt2WavFrontend()
        this.encoder = Txt2WavEncoder( this.frontend.lexicon().phoneCount )
        this.decoder = Txt2WavDecoder()
        this.vocoder = Txt2WavVocoder( this.dev, gpu )
    }

    # ── 完整合成：text → 波形样本 ─────────────────────────
    Array<Float32> synthesize( string text )
    {
        Int64 t0 = SystemTimerNowMillis()

        # 1. 前端：文本 → 音素 id
        Array<string> phones = this.frontend.toPhones( text )
        Array<Int32> ids = this.frontend.encode( phones )
        this.lastPhones = ids.length

        # 每音素帧数（时长规则 → 16ms 帧）
        Array<Int32> durs = Array<Int32>( ids.length )
        Int32 fms = this.decoder.frameMs
        Int32 i = 0
        while i < ids.length
        {
            Int32 pid = ids[ i ]
            Int32 ms = this.frontend.lexicon().durMsOf( pid )
            Int32 fr = ms / fms
            if fr < 1
            {
                fr = 1
            }
            durs[ i ] = fr
            i = i + 1
        }
        Int64 t1 = SystemTimerNowMillis()

        # 2. 神经网络：编码器（协同发音）+ 注意力解码（时长展开）
        Tensor enc = this.encoder.forward( ids )
        Tensor ctx = this.decoder.forward( enc, durs, this.dev )
        this.lastFrames = ctx.rows()
        Array<Float32> f0 = this.decoder.makeF0( this.lastFrames, this.frontend.risingTail )
        Int64 t2 = SystemTimerNowMillis()

        # 3. 声码器：谱合成 + Griffin-Lim
        # 快慢路径：GPU 下前两句跳过 GL 打磨（相位传播版已保证连续性），后续句 GL×2 精修；
        # CPU 兜底模式恒为 gl=0（CPU 数组 DFT 无 STFT 快路径）
        Int32 savedGl = this.vocoder.glIters
        if !this.useGpu || this.synthCount < 2
        {
            this.vocoder.glIters = 0
        }
        else
        {
            this.vocoder.glIters = 2
        }
        this.synthCount = this.synthCount + 1
        Array<Float32> y = this.vocoder.synthesize( ctx, f0 )
        this.vocoder.glIters = savedGl
        Int64 t3 = SystemTimerNowMillis()

        this.lastSamples = y.length
        this.lastFrontendMs = t1 - t0
        this.lastNeuralMs = t2 - t1
        this.lastVocoderMs = t3 - t2
        ret y
    }

    # ── 波形 → WAV 文件（缓冲由调用方构造，供 WAV 编码与 Librosa 分析共用）──
    bool writeWav( string path, Audio.AudioBuffer buf )
    {
        Array<UInt8> bytes = Audio.Wav.encode( buf )
        if bytes == null
        {
            ret false
        }
        File.writeAllBytes( path, bytes )
        ret File.exists( path )
    }
}

# ── 控制台 demo ───────────────────────────────────────────
Txt2Wav
{
    static Int32 s_counter = 0

    static string deviceName( Txt2WavEngine eng )
    {
        if eng.useGpu
        {
            ret "gpu_cuda"
        }
        ret "cpu"
    }

    static bool isSpaceChar( Int32 c )
    {
        if c == 32
        {
            ret true
        }
        if c == 13
        {
            ret true
        }
        if c == 10
        {
            ret true
        }
        if c == 9
        {
            ret true
        }
        ret false
    }

    static void runOne( Txt2WavEngine eng, string text )
    {
        if text.length == 0
        {
            ret
        }
        Txt2Wav.s_counter = Txt2Wav.s_counter + 1
        string path = "txt2wav_" + Txt2Wav.s_counter.toString() + ".wav"

        Console.println( "---------------------------------------------------------------" )
        Console.println( "[txt2wav] text    : " + text )
        Console.println( "[txt2wav] device  : " + Txt2Wav.deviceName( eng ) + " (" + eng.dev.name + ")" )

        Array<Float32> y = eng.synthesize( text )

        Float32 dur = SystemConvertFloat32( eng.lastSamples ) / SystemConvertFloat32( eng.vocoder.sampleRate )
        Console.println( "[txt2wav] phones  : " + eng.lastPhones.toString() + "  frames: " + eng.lastFrames.toString() + "  (" + eng.lastFrames.toString() + " x 16ms)" )
        Console.println( "[txt2wav] samples : " + eng.lastSamples.toString() + "  duration ~= " + SystemConvertString( dur ) + "s" )
        Console.println( "[txt2wav] time    : frontend " + eng.lastFrontendMs.toString() + "ms  neural " + eng.lastNeuralMs.toString() + "ms  vocoder(gl x" + eng.vocoder.glIters.toString() + ") " + eng.lastVocoderMs.toString() + "ms" )

        # 波形缓冲（WAV 编码与 Audio.Librosa 分析共用）
        Audio.AudioBuffer buf = Audio.AudioBuffer( eng.vocoder.sampleRate, 1, y.length )
        Int32 i = 0
        while i < y.length
        {
            buf.setSample( i, 0, y[ i ] )
            i = i + 1
        }

        # 静音检测（RMS）：Audio.Librosa 库逐帧 RMS（帧 2048/步 512），取峰值帧
        Float32 rms = 0.0f
        Array<Float32> rmsFrames = Audio.Librosa.rms( buf )
        if rmsFrames != null
        {
            Int32 fi = 0
            while fi < rmsFrames.length
            {
                if rmsFrames[ fi ] > rms
                {
                    rms = rmsFrames[ fi ]
                }
                fi = fi + 1
            }
        }
        Console.println( "[txt2wav] rms     : " + SystemConvertString( rms ) )

        bool ok = eng.writeWav( path, buf )
        if ok
        {
            Int64 sz = File.getSize( path )
            Console.println( "[txt2wav] written : " + path + " (" + sz.toString() + " bytes, 16kHz mono s16)" )
        }
        else
        {
            Console.println( "[txt2wav] FAILED  : cannot write " + path )
        }
    }

    static fun()
    {
        Console.println( "=============================================================== " )
        Console.println( " Txt2Wav - English text-to-speech sample (SLang + Tensora)" )
        Console.println( " pipeline: text -> G2P -> Embedding+GRU -> attention ->" )
        Console.println( "            spectral synth -> Griffin-Lim -> wav" )
        Console.println( "=============================================================== " )

        Backends.setCudaEnabled( true )
        bool hasGpu = Backends.available( EDeviceKind.GPU )
        if hasGpu
        {
            Console.println( "[txt2wav] CUDA device detected, running on gpu_cuda" )
        }
        else
        {
            Console.println( "[txt2wav] no CUDA device, running on cpu" )
        }
        Console.println( "[txt2wav] simd    : " + Backends.simdIsaName() )

        Txt2WavEngine eng = Txt2WavEngine( true )

        # 内置演示句（前两句最短 + 快路径跳过 GL，保证首个合成响应快）
        Txt2Wav.runOne( eng, "Hello world." )
        Txt2Wav.runOne( eng, "This is slang." )
        Txt2Wav.runOne( eng, "The quick brown fox jumps over the lazy dog." )
        Txt2Wav.runOne( eng, "Can you speak english?" )

        # 交互模式
        Console.println( "---------------------------------------------------------------" )
        Console.println( "interactive mode: type english text to synthesize" )
        Console.println( "  prefix 'cpu:' or 'gpu:' to force device, empty/quit to exit" )
        while true
        {
            string line = Console.input( "txt2wav> " )
            if line == null
            {
                break
            }
            string s = line
            Int32 len = s.length
            # 去掉尾部空白（String.length + s[i] 下标读）
            while len > 0
            {
                Int32 lastPos = len - 1
                if Txt2Wav.isSpaceChar( s[ lastPos ] )
                {
                    len = len - 1
                }
                else
                {
                    len = 0 - len
                }
            }
            if len < 0
            {
                len = 0 - len
            }
            s = s.slice( 0, len )

            if s.length == 0
            {
                break
            }
            if Txt2WavLexicon.strEq( s, "quit" ) || Txt2WavLexicon.strEq( s, "exit" )
            {
                break
            }

            # 设备前缀
            bool needNew = false
            Int32 slen = s.length
            if slen > 4 && Txt2WavLexicon.strEq( s.slice( 0, 4 ), "cpu:" )
            {
                if eng.useGpu
                {
                    needNew = true
                }
                s = s.slice( 4, slen )
            }
            elif slen > 4 && Txt2WavLexicon.strEq( s.slice( 0, 4 ), "gpu:" )
            {
                if !eng.useGpu
                {
                    needNew = true
                }
                s = s.slice( 4, slen )
            }
            if needNew
            {
                eng = Txt2WavEngine( !eng.useGpu )
                Console.println( "[txt2wav] device switched to " + Txt2Wav.deviceName( eng ) )
            }
            Txt2Wav.runOne( eng, s )
        }

        Console.println( "[txt2wav] bye" )
    }
}
