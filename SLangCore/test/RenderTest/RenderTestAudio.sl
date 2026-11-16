import SLangRender;
import SLangAudio;
import Math;
import Std;

# Phase AUDIO：音频模块冒烟（SLangAudio：probe / 整段解码 / 流式 / 播放）：
#   runAudioProbe          4 fixture（wav/mp4-sowt/aac-adts/mp4a-aac）探测
#   runAudioClipDecode     AudioClip 整段解码 + 帧数断言
#   runAudioStream         AudioStream 流式喂入/拉取 + 裸 PCM 直通守恒
#   runAudioPlaybackSmoke  waveOut 播放冒烟（AudioIO.playFile）
#   自包含分组（audioFixture/audioReadAllBytes/audioCheckClip 仅内部使用）
public class RenderTestAudio
{

    # ══════════════════════════════════════════════════════════════════
    # Phase AUDIO：SLangAudio 模块端到端（probe / 整段解码 / 流式 / 播放）
    # fixture：test_audio.wav / test_audio.mp4(sowt-PCM) /
    #          test_audio.aac(ADTS) / test_audio_aac.mp4(mp4a-AAC)
    # 后端：sl_audio_lib.dll（minimp4 + minimp3 CC0；MF AAC MFT；waveOut）
    # ══════════════════════════════════════════════════════════════════

    # fixture 路径（相对 CWD 优先，绝对路径兜底，同 test_image.png 约定）
    public static string audioFixture( string name )
    {
        string rel = "SlangAllInOne/SLangCore/test/RenderTest/" + name
        if SystemFileExists( rel )
        {
            ret rel
        }
        ret "D:/project/lang/SlangAllInOne/SLangCore/test/RenderTest/" + name
    }

    # 读整个文件到 Array<UInt8>（SystemFileRead 走 ByteBuffer 注册表句柄
    # 桥接 —— 第二参不是裸指针，见 Core/IO/ByteBuffer.handle 注记）


    # 读整个文件到 Array<UInt8>（SystemFileRead 走 ByteBuffer 注册表句柄
    # 桥接 —— 第二参不是裸指针，见 Core/IO/ByteBuffer.handle 注记）
    public static Array<UInt8> audioReadAllBytes( string path )
    {
        Int64 size = SystemFileGetSize( path )
        if size <= 0
        {
            ret null
        }
        Int32 n = SystemConvertInt32( size )
        if n <= 0 || n > 4194304
        {
            ret null
        }
        Int64 h = SystemFileOpen( path, 1 )
        if h == 0
        {
            ret null
        }
        ByteBuffer bb = ByteBuffer( n )
        Int32 got = SystemFileRead( h, bb.handle, n )
        SystemFileClose( h )
        if got != n
        {
            ret null
        }
        ret bb.toArray()
    }

    # 单 fixture 整段解码校验：元数据 + s16Bytes + 非静音 + 时长


    # 单 fixture 整段解码校验：元数据 + s16Bytes + 非静音 + 时长
    public static bool audioCheckClip( string name, Int32 srcId, Int64 minFrames )
    {
        Audio.AudioClip clip = Audio.AudioClip.loadFile( audioFixture( name ) )
        if clip == null
        {
            Console.println( "[aud] FAIL: decode " + name + " - " + Audio.AudioIO.lastErrorText() )
            ret false
        }
        if clip.sampleRate != 44100 || clip.channels != 1 || clip.frameCount < minFrames || clip.sourceFormatId != srcId
        {
            Console.println( "[aud] FAIL: meta " + name + " (src=" + clip.sourceFormatId.toString() + ")" )
            clip.free()
            ret false
        }
        Array<UInt8> pcm = clip.s16Bytes()
        if pcm == null || pcm.length != SystemConvertInt32( clip.frameCount * 2 )
        {
            Console.println( "[aud] FAIL: s16Bytes " + name )
            clip.free()
            ret false
        }
        Int32 nonzero = 0
        Int32 i = 0
        while i < pcm.length && i < 4096
        {
            if pcm[ i ] != 0
            {
                nonzero = nonzero + 1
            }
            i = i + 1
        }
        if nonzero < 64
        {
            Console.println( "[aud] FAIL: silent " + name )
            clip.free()
            ret false
        }
        if clip.duration < 1.5f || clip.duration > 2.5f
        {
            Console.println( "[aud] FAIL: duration " + name )
            clip.free()
            ret false
        }
        Int32 framesText = SystemConvertInt32( clip.frameCount )
        Console.println( "[aud] ok " + name + " (src=" + clip.sourceFormatId.toString() + ", frames=" + framesText.toString() + ")" )
        clip.free()
        ret true
    }

    # ── Phase AUD-P：探测（4 fixture 头解析，不解码 PCM）─────────────


    # ── Phase AUD-P：探测（4 fixture 头解析，不解码 PCM）─────────────
    public static bool runAudioProbe()
    {
        Console.println( "-- Phase AUD-P: audio probe (wav / mp4-pcm / aac-adts / mp4-aac) --" )
        if Audio.AudioIO.ensureReady() == false
        {
            Console.println( "[aud] FAIL: ensureReady" )
            ret false
        }
        Console.println( "[aud] backends: " + Audio.AudioIO.backendsText() )

        Audio.AudioInfo iw = Audio.AudioIO.probeFile( audioFixture( "test_audio.wav" ) )
        if iw == null || iw.sampleRate != 44100 || iw.channels != 1 || iw.srcFormatId != 1 || iw.frameCount != 88200
        {
            Console.println( "[aud] FAIL: probe wav" )
            ret false
        }
        Audio.AudioInfo im = Audio.AudioIO.probeFile( audioFixture( "test_audio.mp4" ) )
        if im == null || im.sampleRate != 44100 || im.channels != 1 || im.srcFormatId != 7 || im.frameCount != 88200
        {
            Console.println( "[aud] FAIL: probe mp4-pcm" )
            ret false
        }
        Audio.AudioInfo ia = Audio.AudioIO.probeFile( audioFixture( "test_audio.aac" ) )
        if ia == null || ia.sampleRate != 44100 || ia.channels != 1 || ia.srcFormatId != 6
        {
            Console.println( "[aud] FAIL: probe aac-adts" )
            ret false
        }
        Audio.AudioInfo ic = Audio.AudioIO.probeFile( audioFixture( "test_audio_aac.mp4" ) )
        if ic == null || ic.sampleRate != 44100 || ic.channels != 1 || ic.srcFormatId != 9 || ic.frameCount != 88064
        {
            Console.println( "[aud] FAIL: probe mp4-aac" )
            ret false
        }
        Console.println( "[aud] probe PASS (4 fixtures: 44100Hz mono)" )
        ret true
    }

    # ── Phase AUD-C：整段解码（预载 AudioClip，提前播放的数据基础）────


    # ── Phase AUD-C：整段解码（预载 AudioClip，提前播放的数据基础）────
    public static bool runAudioClipDecode()
    {
        Console.println( "-- Phase AUD-C: whole-decode clips (preloaded, instant-play ready) --" )
        bool ok1 = audioCheckClip( "test_audio.wav", 1, 88200 )
        bool ok2 = audioCheckClip( "test_audio.mp4", 7, 88200 )
        bool ok3 = audioCheckClip( "test_audio.aac", 6, 80000 )
        bool ok4 = audioCheckClip( "test_audio_aac.mp4", 9, 80000 )
        if ok1 && ok2 && ok3 && ok4
        {
            Console.println( "[aud] clip PASS (wav/mp4-pcm/aac/mp4-aac)" )
            ret true
        }
        ret false
    }

    # ── Phase AUD-S：流式解码（feed 压缩流 / 拉 PCM / 裸 PCM 直通）───


    # ── Phase AUD-S：流式解码（feed 压缩流 / 拉 PCM / 裸 PCM 直通）───
    public static bool runAudioStream()
    {
        Console.println( "-- Phase AUD-S: streaming decode (wav + aac-adts + pcm passthrough) --" )

        # wav 流：文件字节分两半喂入 -> 拉干
        Array<UInt8> wavBytes = audioReadAllBytes( audioFixture( "test_audio.wav" ) )
        if wavBytes == null
        {
            Console.println( "[aud] FAIL: read wav bytes" )
            ret false
        }
        Audio.AudioStream stm = Audio.AudioStream.create()
        if stm == null
        {
            Console.println( "[aud] FAIL: stream create" )
            ret false
        }
        Int32 halfLen = wavBytes.length / 2
        Array<UInt8> firstHalf = Array<UInt8>( halfLen )
        Array<UInt8> secondHalf = Array<UInt8>( wavBytes.length - halfLen )
        Int32 i = 0
        while i < halfLen
        {
            firstHalf[ i ] = wavBytes[ i ]
            i = i + 1
        }
        while i < wavBytes.length
        {
            secondHalf[ i - halfLen ] = wavBytes[ i ]
            i = i + 1
        }
        stm.feed( firstHalf )
        stm.feed( secondHalf )
        Int64 producedWav = 0
        while true
        {
            Array<UInt8> chunk = stm.readS16Bytes( 4096 )
            if chunk == null
            {
                break
            }
            producedWav = producedWav + chunk.length / 2
        }
        if stm.sampleRate != 44100 || stm.channels != 1 || producedWav < 88000
        {
            Int32 pw = SystemConvertInt32( producedWav )
            Console.println( "[aud] FAIL: stream wav (produced=" + pw.toString() + ")" )
            stm.free()
            ret false
        }
        Int32 pwOk = SystemConvertInt32( producedWav )
        Console.println( "[aud] ok stream wav (frames=" + pwOk.toString() + ")" )
        stm.free()

        # aac-adts 流：整文件喂入 -> 拉干（MF AAC MFT 后端）
        Array<UInt8> aacBytes = audioReadAllBytes( audioFixture( "test_audio.aac" ) )
        if aacBytes == null
        {
            Console.println( "[aud] FAIL: read aac bytes" )
            ret false
        }
        Audio.AudioStream stm2 = Audio.AudioStream.create()
        if stm2 == null
        {
            Console.println( "[aud] FAIL: stream2 create" )
            ret false
        }
        stm2.feed( aacBytes )
        Int64 producedAac = 0
        while true
        {
            Array<UInt8> chunk = stm2.readS16Bytes( 4096 )
            if chunk == null
            {
                break
            }
            producedAac = producedAac + chunk.length / 2
        }
        if stm2.sampleRate != 44100 || stm2.channels != 1 || producedAac < 80000
        {
            Int32 pa = SystemConvertInt32( producedAac )
            Console.println( "[aud] FAIL: stream aac (produced=" + pa.toString() + ")" )
            stm2.free()
            ret false
        }
        Int32 paOk = SystemConvertInt32( producedAac )
        Console.println( "[aud] ok stream aac (frames=" + paOk.toString() + ")" )
        stm2.free()

        # 裸 PCM 直通：wav 解出的 S16 喂 PCM 流 -> 原样拉回（帧数守恒）
        Audio.AudioClip clip = Audio.AudioClip.loadFile( audioFixture( "test_audio.wav" ) )
        if clip == null
        {
            Console.println( "[aud] FAIL: clip for pcm passthrough" )
            ret false
        }
        Array<UInt8> pcm = clip.s16Bytes()
        Int64 frames = clip.frameCount
        clip.free()
        if pcm == null
        {
            Console.println( "[aud] FAIL: s16Bytes for passthrough" )
            ret false
        }
        Audio.AudioStream stm3 = Audio.AudioStream.createPcm( Audio.ESampleFormat.S16, 44100, 1 )
        if stm3 == null
        {
            Console.println( "[aud] FAIL: pcm stream create" )
            ret false
        }
        stm3.feed( pcm )
        Int64 producedPcm = 0
        while true
        {
            Array<UInt8> chunk = stm3.readS16Bytes( 4096 )
            if chunk == null
            {
                break
            }
            producedPcm = producedPcm + chunk.length / 2
        }
        stm3.free()
        if producedPcm != frames
        {
            Int32 pin = SystemConvertInt32( frames )
            Int32 pout = SystemConvertInt32( producedPcm )
            Console.println( "[aud] FAIL: pcm passthrough (in=" + pin.toString() + ", out=" + pout.toString() + ")" )
            ret false
        }
        Int32 ppOk = SystemConvertInt32( producedPcm )
        Console.println( "[aud] ok pcm passthrough (frames=" + ppOk.toString() + ")" )
        Console.println( "[aud] stream PASS" )
        ret true
    }

    # ── Phase AUD-PLAY：播放冒烟（waveOut；无声卡环境优雅降级 SKIP）──


    # ── Phase AUD-PLAY：播放冒烟（waveOut；无声卡环境优雅降级 SKIP）──
    public static Int32 runAudioPlaybackSmoke()
    {
        Console.println( "-- Phase AUD-PLAY: playback smoke (waveOut, SKIP if no device) --" )
        if Audio.AudioPlayer.deviceAvailable() == false
        {
            Console.println( "[aud] SKIP: no audio output device" )
            ret 1
        }
        Audio.AudioClip clip = Audio.AudioClip.loadFile( audioFixture( "test_audio.wav" ) )
        if clip == null
        {
            Console.println( "[aud] FAIL: load wav for playback" )
            ret 0
        }
        Audio.AudioPlayer ply = clip.play( 70 )
        if ply == null
        {
            Console.println( "[aud] FAIL: clip.play - " + Audio.AudioIO.lastErrorText() )
            clip.free()
            ret 0
        }
        Int64 pos0 = ply.position()
        Int32 waited = 0
        while ply.position() < pos0 + 2000 && waited < 60
        {
            SystemSleep( 20 )
            waited = waited + 1
        }
        Int64 pos1 = ply.position()
        Int32 posText = SystemConvertInt32( pos1 )
        Int32 bufText = SystemConvertInt32( ply.buffered() )
        Console.println( "[aud] pos=" + posText.toString() + " buffered=" + bufText.toString() )
        ply.stop()
        ply.free()
        clip.free()
        if pos1 < pos0 + 1000
        {
            Console.println( "[aud] FAIL: playback position did not advance" )
            ret 0
        }
        Console.println( "[aud] playback PASS" )
        ret 2
    }

    # ── Phase AUD-SRC：AudioSource 组件（Unity 风格 clip/volume/loop/
    # playOneShot；waveOut 真实出声，无声卡环境优雅降级 SKIP）──
    public static Int32 runAudioSource()
    {
        Console.println( "-- Phase AUD-SRC: AudioSource component (clip/volume/loop/one-shot, waveOut) --" )
        if Audio.AudioPlayer.deviceAvailable() == false
        {
            Console.println( "[aud] SKIP: no audio output device" )
            ret 1
        }
        Audio.AudioClip clip = Audio.AudioClip.loadFile( audioFixture( "test_audio.wav" ) )
        if clip == null
        {
            Console.println( "[aud] FAIL: load wav for source" )
            ret 0
        }
        Audio.AudioClip shotClip = Audio.AudioClip.loadFile( audioFixture( "test_audio_aac.mp4" ) )
        if shotClip == null
        {
            Console.println( "[aud] FAIL: load mp4-aac for one-shot" )
            clip.free()
            ret 0
        }

        Audio.AudioSource src = Audio.AudioSource()
        src.clip = clip
        src.volume = 0.6f
        src.loop = true
        if src.clip.frameCount != clip.frameCount
        {
            Console.println( "[aud] FAIL: clip setter/getter" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }

        # 播放（真实出声）：主通道 wav 2s 循环
        if src.Play() == false
        {
            Console.println( "[aud] FAIL: Play - " + Audio.AudioIO.lastErrorText() )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }
        SystemSleep( 300 )
        if src.isPlaying == false
        {
            Console.println( "[aud] FAIL: isPlaying after 300ms" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }
        Float32 t0 = src.time
        if t0 < 0.15f
        {
            Console.println( "[aud] FAIL: time did not advance (t=" + t0.toString() + ")" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }

        # one-shot 叠加（aac 片段，不打断主通道）
        if src.playOneShot( shotClip, 0.5f ) == false
        {
            Console.println( "[aud] FAIL: playOneShot" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }
        SystemSleep( 200 )
        if src.oneshotCount < 1
        {
            Console.println( "[aud] FAIL: one-shot not active" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }

        # 暂停/恢复
        if src.Pause() == false || src.isPlaying
        {
            Console.println( "[aud] FAIL: Pause" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }
        SystemSleep( 150 )
        if src.UnPause() == false || src.isPlaying == false
        {
            Console.println( "[aud] FAIL: UnPause" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }

        # 等第一轮播完 -> update() 驱动 loop 重播（2s 片段，已播约 0.65s）
        Int32 guard = 0
        while src.loopCount < 1 && guard < 300
        {
            src.update()
            SystemSleep( 20 )
            guard = guard + 1
        }
        if src.loopCount < 1
        {
            Console.println( "[aud] FAIL: loop did not restart (loopCount=0)" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }
        if src.isPlaying == false
        {
            Console.println( "[aud] FAIL: loop should keep playing" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }
        # one-shot（2s）此时应已被 update() 回收（播完 > 1 轮主通道时长）
        src.update()
        Console.println( "[aud] ok source loop (loopCount=" + src.loopCount.toString() + ", oneshots=" + src.oneshotCount.toString() + ")" )

        # 停播
        if src.Stop() == false || src.isPlaying
        {
            Console.println( "[aud] FAIL: Stop" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }
        if src.loopCount != 0
        {
            Console.println( "[aud] FAIL: loopCount not reset by Stop" )
            src.free()
            clip.free()
            shotClip.free()
            ret 0
        }

        src.free()
        clip.free()
        shotClip.free()
        Console.println( "[aud] AudioSource PASS" )
        ret 2
    }
}
