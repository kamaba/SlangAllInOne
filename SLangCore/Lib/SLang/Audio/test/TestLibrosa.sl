import SLangAudio;
import Math;
import Std;

# ============================================================================
# TestLibrosa — Audio.Librosa（librosa 1.0.1 分析层 FFI）e2e 测试
# ----------------------------------------------------------------------------
# 断言基准：tools/librosa_golden.txt（Python librosa 1.0.1 对同一合成信号
# s1 产出；生成器 gen_golden.py，C 级对照 verify_librosa.c 480/480 通过）。
# 信号 s1：n=20000@22050Hz，0.5*sin(2pi*440t)+0.25*sin(2pi*880t+0.3)
#          +0.1*sin(2pi*3000t)。
# 运行：test 目录下 slang.exe TestLibrosa.jsonc（编译 + 运行一体）
# ============================================================================

public class TestLibrosa
{
    static Int32 _pass = 0
    static Int32 _fail = 0

    static void check( bool cond, string msg )
    {
        if cond
        {
            _pass = _pass + 1
        }
        else
        {
            _fail = _fail + 1
            Console.println( "[FAIL] " + msg )
        }
    }

    static Float64 adiff( Float64 a, Float64 b )
    {
        Float64 d = a - b
        if d < 0.0
        {
            d = -d
        }
        ret d
    }

    static void checkNear( Float64 got, Float64 want, Float64 tol, string msg )
    {
        check( adiff( got, want ) <= tol, msg + " got=" + got.toString() + " want=" + want.toString() )
    }

    # s1 合成信号（与 gen_golden.py 一致；Float64 sin 后落 Float32）
    static Audio.AudioBuffer synthS1()
    {
        Int32 n = 20000
        Audio.AudioBuffer buf = Audio.AudioBuffer( 22050, 1, n )
        Int32 i = 0
        while i < n
        {
            Float64 t = 1.0 * i
            Float64 v = 0.5 * Mathd.sin( 2.0 * Mathd.Pi * 440.0 * t / 22050.0 )
            v = v + 0.25 * Mathd.sin( 2.0 * Mathd.Pi * 880.0 * t / 22050.0 + 0.3 )
            v = v + 0.1 * Mathd.sin( 2.0 * Mathd.Pi * 3000.0 * t / 22050.0 )
            buf.setSample( i, 0, SystemConvertFloat32( v ) )
            i = i + 1
        }
        ret buf
    }

    # ── 1. FFI 就绪 + 版本 ──────────────────────────────────
    static void testReady()
    {
        Console.println( "----- [1] ensureReady / version -----" )
        check( Audio.Librosa.ensureReady(), "T1a ensureReady (sl_audio_lib preloaded, sla_lr_* bound)" )
        string ver = Audio.Librosa.libVersionString()
        check( ver != null && ver != "", "T1b version string non-empty" )
        Console.println( "librosa version: " + ver )
    }

    # ── 2. 标量换算（golden scal.*） ─────────────────────────
    static void testScalars()
    {
        Console.println( "----- [2] scalar converters -----" )
        checkNear( Audio.Librosa.hzToMel( 1000.0 ), 15.0, 1e-6, "T2a hz_to_mel(1000)" )
        checkNear( Audio.Librosa.hzToMel( 2000.0 ), 25.0818802, 1e-4, "T2b hz_to_mel(2000)" )
        checkNear( Audio.Librosa.melToHz( 25.0 ), 1988.77282, 0.01, "T2c mel_to_hz(25)" )
        checkNear( Audio.Librosa.hzToMidi( 440.0 ), 69.0, 1e-9, "T2d hz_to_midi(440)" )
        checkNear( Audio.Librosa.midiToHz( 69.0 ), 440.0, 1e-9, "T2e midi_to_hz(69)" )
        check( Audio.Librosa.hzToNote( 440.0 ) == "A4", "T2f hz_to_note(440) == A4" )
        check( Audio.Librosa.hzToNote( 261.6256 ) == "C4", "T2g hz_to_note(261.6256) == C4" )
        check( Audio.Librosa.hzToNote( 55.0 ) == "A1", "T2h hz_to_note(55) == A1" )
        checkNear( Audio.Librosa.powerToDb( 0.5, 1.0 ), -3.01029996, 1e-6, "T2i power_to_db(0.5)" )
        checkNear( Audio.Librosa.amplitudeToDb( 0.5, 1.0 ), -6.02059991, 1e-6, "T2j amplitude_to_db(0.5)" )
        checkNear( Audio.Librosa.dbToPower( -30.0, 1.0 ), 0.001, 1e-9, "T2k db_to_power(-30)" )
        checkNear( Audio.Librosa.dbToAmplitude( -30.0, 1.0 ), 0.0316227766, 1e-8, "T2l db_to_amplitude(-30)" )
    }

    # ── 3. stft / mel / mfcc / chroma / 谱特征（golden s1.*） ─
    static void testStftFeatures()
    {
        Console.println( "----- [3] stft / mel / mfcc / chroma / spectral -----" )
        Audio.AudioBuffer buf = TestLibrosa.synthS1()
        Audio.LibrosaMatrix s = Audio.Librosa.stft( buf )
        check( s != null, "T3a stft matrix created" )
        if s == null
        {
            ret
        }
        check( s.rowCount() == 1025, "T3b stft rows == 1025" )
        check( s.colCount() == 40, "T3c stft cols == 40" )
        check( s.isValid(), "T3d stft isValid" )

        # mel 频谱
        Audio.LibrosaMatrix mel = Audio.Librosa.melspectrogramOfStft( s, 22050, 128 )
        check( mel != null, "T3e melspectrogram matrix created" )
        if mel != null
        {
            check( mel.rowCount() == 128, "T3f mel rows == 128" )
            checkNear( mel.at( 0, 0 ), 2.34566379, 5e-4, "T3g mel[0][0]" )
            mel.free()
        }

        # mfcc（经由 mel）
        Audio.LibrosaMatrix mel2 = Audio.Librosa.melspectrogramOfStft( s, 22050, 128 )
        Audio.LibrosaMatrix mfcc = Audio.Librosa.mfccOfMel( mel2, 20 )
        check( mfcc != null, "T3h mfcc matrix created" )
        if mfcc != null
        {
            check( mfcc.rowCount() == 20, "T3i mfcc rows == 20" )
            checkNear( mfcc.at( 0, 0 ), -158.986099, 0.032, "T3j mfcc[0][0]" )
            mfcc.free()
        }
        if mel2 != null
        {
            mel2.free()
        }

        # chroma
        Audio.LibrosaMatrix ch = Audio.Librosa.chromaOfStft( s, 22050 )
        check( ch != null, "T3k chroma matrix created" )
        if ch != null
        {
            check( ch.rowCount() == 12, "T3l chroma rows == 12" )
            checkNear( ch.at( 0, 0 ), 0.0103867762, 1e-4, "T3m chroma[0][0]" )
            ch.free()
        }

        # 调音估计
        checkNear( Audio.Librosa.tuningOfStft( s, 22050 ), 0.02, 0.011, "T3n estimate_tuning" )

        # 谱向量特征（逐帧）
        Array<Float32> cen = Audio.Librosa.centroidOfStft( s, 22050 )
        check( cen != null, "T3o centroid vector created" )
        if cen != null
        {
            checkNear( cen[ 0 ], 1032.19263, 0.25, "T3p centroid[0]" )
            checkNear( cen[ 39 ], 1682.09473, 0.4, "T3q centroid[39]" )
        }
        Array<Float32> bw = Audio.Librosa.bandwidthOfStft( s, 22050 )
        check( bw != null, "T3r bandwidth vector created" )
        if bw != null
        {
            checkNear( bw[ 0 ], 1218.3197, 0.3, "T3s bandwidth[0]" )
        }
        Array<Float32> ro = Audio.Librosa.rolloffOfStft( s, 22050 )
        check( ro != null, "T3t rolloff vector created" )
        if ro != null
        {
            checkNear( ro[ 0 ], 2368.65234, 0.6, "T3u rolloff[0]" )
        }
        Array<Float32> fl = Audio.Librosa.flatnessOfStft( s )
        check( fl != null, "T3v flatness vector created" )
        if fl != null
        {
            checkNear( fl[ 0 ], 0.000316188991, 1e-6, "T3w flatness[0]" )
        }

        # istft 往返（黄金误差 2.38e-7）
        Audio.AudioBuffer back = Audio.Librosa.istft( s, 512, 20000, 22050 )
        check( back != null, "T3x istft buffer created" )
        if back != null
        {
            check( back.frameCount() == 20000, "T3y istft length == 20000" )
            Float64 err = 0.0
            Int32 i = 0
            while i < 20000
            {
                Float64 d = buf.getSample( i, 0 ) - back.getSample( i, 0 )
                if d < 0.0
                {
                    d = -d
                }
                if d > err
                {
                    err = d
                }
                i = i + 1
            }
            checkNear( err, 0.0, 1e-5, "T3z istft roundtrip max-err" )
        }

        s.free()
    }

    # ── 4. rms / zcr / tempo（golden s1.*） ──────────────────
    static void testTimeDomain()
    {
        Console.println( "----- [4] rms / zcr / tempo -----" )
        Audio.AudioBuffer buf = TestLibrosa.synthS1()
        Array<Float32> rms = Audio.Librosa.rms( buf )
        check( rms != null, "T4a rms vector created" )
        if rms != null
        {
            checkNear( rms[ 0 ], 0.284050494, 6e-5, "T4b rms[0]" )
        }
        Array<Float32> zcr = Audio.Librosa.zeroCrossingRate( buf )
        check( zcr != null, "T4c zcr vector created" )
        if zcr != null
        {
            checkNear( zcr[ 0 ], 0.041015625, 1e-3, "T4d zcr[0]" )
        }
        Float64 bpm = Audio.Librosa.tempo( buf )
        checkNear( bpm, 123.046875, 1.0, "T4e tempo" )
    }

    public static void run()
    {
        Console.println( "=== TestLibrosa: Audio.Librosa (librosa 1.0.1 port) FFI e2e ===" )
        testReady()
        testScalars()
        testStftFeatures()
        testTimeDomain()
        Console.println( "" )
        Console.println( "=== TOTAL PASS=" + _pass.toString() + " FAIL=" + _fail.toString() + " ===" )
        if _fail > 0
        {
            OS.Kernel.exit( 1 )
        }
    }
}

# ── VM 入口（Project._main_ 为 C VM 入口方法约定） ──────────────
Project
{
    _main_()
    {
        TestLibrosa.run()
    }
}
