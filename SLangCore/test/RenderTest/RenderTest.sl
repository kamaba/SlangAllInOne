import SLangRender;
import SLangAudio;
import Math;
import Std;

# GLRenderTest —— 入口类：共享渲染移交状态 + 全 phase 编排（main）
# 原单文件 RenderTest.sl（~6000 行）拆分为主文件 + 10 个分组类：
#   RenderTestHelpers / RenderTestCube / RenderTestQt / RenderTestAudio /
#   RenderTestSmoke / RenderTestPhasesA..E（详细 phase 说明见各文件头注释）
public class RenderTest
{

    # ── 共享渲染移交状态（各 Phase / Qt / Cube 分组类直接读写）──
    public static SLang.RenderPipeline _pipe = null
    public static Int64 _pixels = 0
    public static Int32 _texW = 256
    public static Int32 _texH = 256
    # v3.4：QT 演示聚光灯（暖色，slot 0）—— onTick 每帧摇晃位置 +
    # 强度脉动后 applyTo 重写光照槽（阴影/锥光随灯实时跟随）
    public static Light _lamp = null

    public static void main()
    {
        Console.println( "========== GLRenderTest (SLangRender RHI multi-backend + QT window) ==========" )
        Console.println( "backends: " + SLang.Render.backendList() )

        # ── Phase D：D3D11 后端同效果（先跑，跑完切回 GL 走主流程）──
        Int32 phaseD = RenderTestSmoke.runD3D11Smoke()

        # ── Phase E：Vulkan 后端同效果（本机有 vulkan-1.dll 时必须全绿）──
        Int32 phaseVk = RenderTestSmoke.runVkSmoke()

        # ── Phase F：EGL/GLES 后端（无 GLES 运行库时优雅降级 SKIP）──
        Int32 phaseGles = RenderTestSmoke.runGlesSmoke()

        # 主流程：显式切回 GL 默认后端（initialize 对已初始化态幂等，
        # 不切后端 —— 因此这里用 initializeBackend("gl") 强制切换）
        if SLang.Render.initializeBackend( "gl" ) == false
        {
            Console.println( "FAIL: initialize gl - " + SLang.Render.errorString() )
            ret
        }
        Console.println( "backend : " + SLang.Render.currentBackend() + "  renderer: " + SLang.Render.rendererInfo() )
        Console.println( "version : " + SLang.Render.versionInfo() )

        bool a1 = RenderTestPhasesA.runV1Compat()
        bool a2 = RenderTestPhasesA.runPipeline()
        bool a3 = RenderTestPhasesA.runMultiCameraImage()
        bool phaseA = a1 && a2 && a3

        # Phase L：光照（直射 + 聚光 + 无光回归；当前 GL 后端）
        bool phaseL = RenderTestPhasesB.runLightScene()

        # Phase SHADOW2：N2a 真实阴影（shadow map + PCF 平行光；当前 GL 后端）
        bool phaseShadow2 = RenderTestPhasesB.runShadowMap()

        # Phase CSM：N2b 4 级联（v 分段 + 图集 1x4；当前 GL 后端）
        bool phaseCsm = RenderTestPhasesB.runCsmShadow()

        # Phase G：固化 shader（gen 效果 material>=2）正面断言（当前 GL 后端）
        bool phaseG = RenderTestPhasesB.runGenShaders()

        # Phase CB：CommandBuffer 真录制（录制 -> 整理 -> 提交渲染，当前 GL 后端）
        bool phaseCB = RenderTestPhasesC.runCommandBuffer()

        # Phase INST：GPU 实例化合批（N1：64 实例 1 draw vs 64 draw 像素一致）
        bool phaseInst = RenderTestPhasesC.runInstancing()

        # Phase PASS：Pass 序列提交（Opaque/Transparent/Post/Blit 四 Pass 单流）
        bool phasePass = RenderTestPhasesC.runPassSubmit()

        # Phase FEATURE：Feature 注入（AfterPost 全屏色块 + Volume 覆盖栈）
        bool phaseFeature = RenderTestPhasesD.runFeatureInject()

        # Phase ASSET：RenderPipeline 资产层（资产 -> 实例 -> Render(FrameData)）
        bool phaseAsset = RenderTestPhasesD.runAssetPipeline()

        # Phase ENV：渲染环境查询（支持情况 / 当前选择 / 硬件 / 资源 / 配置 / 帧级统计）
        bool phaseEnv = RenderTestPhasesE.runEnvironmentQuery()

        # Phase RTPOOL：RT 句柄池（同尺寸复用 / releaseAll）
        bool phaseRtpool = RenderTestPhasesD.runRtPool()

        # Phase FS：FrameSettings（后处理开关 / 透明序策略 / 目标缩放）
        bool phaseFs = RenderTestPhasesD.runFrameSettings()

        # Phase DATA：数据层快照（CullingData / FrameData / PassData）
        bool phaseData = RenderTestPhasesE.runDataSnapshot()

        # Phase RAY：软光追 demo（N4a：CPU whitted + SLMC RaySet*/RayRender）
        bool phaseRay = RenderTestPhasesE.runRayTracing()

        # Phase ASYNC：异步提交（N3：SLMC 双缓冲 + 渲染 worker 线程）
        bool phaseAsync = RenderTestPhasesE.runAsyncSubmit()

        # Phase AUDIO：音频模块（SLangAudio：probe / 整段解码 / 流式 / 播放冒烟）
        bool phaseAudProbe = RenderTestAudio.runAudioProbe()
        bool phaseAudClip = RenderTestAudio.runAudioClipDecode()
        bool phaseAudStream = RenderTestAudio.runAudioStream()
        Int32 phaseAudPlay = RenderTestAudio.runAudioPlaybackSmoke()
        Int32 phaseAudSrc = RenderTestAudio.runAudioSource()

        Int32 phaseB = RenderTestQt.runQtWindow()

        string dText = "FAIL"
        if phaseD == 2
        {
            dText = "PASS"
        }
        elif phaseD == 1
        {
            dText = "SKIP"
        }
        string vText = "FAIL"
        if phaseVk == 2
        {
            vText = "PASS"
        }
        elif phaseVk == 1
        {
            vText = "SKIP"
        }
        string gText = "FAIL"
        if phaseGles == 2
        {
            gText = "PASS"
        }
        elif phaseGles == 1
        {
            gText = "SKIP"
        }
        string bText = "FAIL"
        if phaseB == 2
        {
            bText = "PASS"
        }
        elif phaseB == 1
        {
            bText = "SKIP"
        }
        Console.println( "========== GLRenderTest summary ==========" )
        Console.println( "phase D  (d3d11 same-effect) : " + dText )
        Console.println( "phase E  (vk same-effect)    : " + vText )
        Console.println( "phase F  (gles graceful)     : " + gText )
        Console.println( "phase A1 (v1 compat)         : " + ( a1 ? "PASS" : "FAIL" ) )
        Console.println( "phase A2 (13-stage pipe)     : " + ( a2 ? "PASS" : "FAIL" ) )
        Console.println( "phase A3 (multi-cam+img)     : " + ( a3 ? "PASS" : "FAIL" ) )
        Console.println( "phase L  (dir+spot light)    : " + ( phaseL ? "PASS" : "FAIL" ) )
        Console.println( "phase SHADOW2(shadow map)    : " + ( phaseShadow2 ? "PASS" : "FAIL" ) )
        Console.println( "phase CSM  (csm 4 cascades)  : " + ( phaseCsm ? "PASS" : "FAIL" ) )
        Console.println( "phase G  (frozen shaders)   : " + ( phaseG ? "PASS" : "FAIL" ) )
        Console.println( "phase CB (command buffer)   : " + ( phaseCB ? "PASS" : "FAIL" ) )
        Console.println( "phase INST(gpu instancing)  : " + ( phaseInst ? "PASS" : "FAIL" ) )
        Console.println( "phase PASS(pass sequence)   : " + ( phasePass ? "PASS" : "FAIL" ) )
        Console.println( "phase FEATURE(custom pass)  : " + ( phaseFeature ? "PASS" : "FAIL" ) )
        Console.println( "phase ASSET(pipeline asset) : " + ( phaseAsset ? "PASS" : "FAIL" ) )
        Console.println( "phase ENV(render env)       : " + ( phaseEnv ? "PASS" : "FAIL" ) )
        Console.println( "phase RTPOOL(rt handle pool): " + ( phaseRtpool ? "PASS" : "FAIL" ) )
        Console.println( "phase FS  (frame settings)   : " + ( phaseFs ? "PASS" : "FAIL" ) )
        Console.println( "phase DATA(data layer)       : " + ( phaseData ? "PASS" : "FAIL" ) )
        Console.println( "phase RAY (software raytr)   : " + ( phaseRay ? "PASS" : "FAIL" ) )
        Console.println( "phase ASYNC(async submit)   : " + ( phaseAsync ? "PASS" : "FAIL" ) )
        Console.println( "phase AUD-P (audio probe)   : " + ( phaseAudProbe ? "PASS" : "FAIL" ) )
        Console.println( "phase AUD-C (audio clip)    : " + ( phaseAudClip ? "PASS" : "FAIL" ) )
        Console.println( "phase AUD-S (audio stream)  : " + ( phaseAudStream ? "PASS" : "FAIL" ) )
        string apText = "FAIL"
        if phaseAudPlay == 2
        {
            apText = "PASS"
        }
        elif phaseAudPlay == 1
        {
            apText = "SKIP"
        }
        Console.println( "phase AUD-PLAY(waveOut)     : " + apText )
        string asText = "FAIL"
        if phaseAudSrc == 2
        {
            asText = "PASS"
        }
        elif phaseAudSrc == 1
        {
            asText = "SKIP"
        }
        Console.println( "phase AUD-SRC (audio source): " + asText )
        Console.println( "phase B  (QT window)         : " + bText )
        # 终判：主流程全绿 + D3D11/VK 可用即 PASS，GLES 允许 SKIP（环境无 GLES 库）
        bool allOk = phaseA
        if !phaseL
        {
            allOk = false
        }
        if !phaseShadow2
        {
            allOk = false
        }
        if !phaseCsm
        {
            allOk = false
        }
        if !phaseG
        {
            allOk = false
        }
        if !phaseCB
        {
            allOk = false
        }
        if !phaseInst
        {
            allOk = false
        }
        if !phasePass
        {
            allOk = false
        }
        if !phaseFeature
        {
            allOk = false
        }
        if !phaseAsset
        {
            allOk = false
        }
        if !phaseEnv
        {
            allOk = false
        }
        if !phaseRtpool
        {
            allOk = false
        }
        if !phaseFs
        {
            allOk = false
        }
        if !phaseData
        {
            allOk = false
        }
        if !phaseRay
        {
            allOk = false
        }
        if !phaseAsync
        {
            allOk = false
        }
        if phaseB == 0
        {
            allOk = false
        }
        if phaseD == 0
        {
            allOk = false
        }
        if phaseVk != 2
        {
            allOk = false
        }
        if phaseGles == 0
        {
            allOk = false
        }
        if !phaseAudProbe
        {
            allOk = false
        }
        if !phaseAudClip
        {
            allOk = false
        }
        if !phaseAudStream
        {
            allOk = false
        }
        if phaseAudPlay == 0
        {
            allOk = false
        }
        if phaseAudSrc == 0
        {
            allOk = false
        }
        if allOk
        {
            Console.println( "GLRenderTest: PASS" )
        }
        else
        {
            Console.println( "GLRenderTest: FAIL" )
        }
    }

    # ── Phase D：D3D11 后端同效果验证（返回 2=PASS 1=SKIP 0=FAIL）────
    # 与 GL 主流程共用 A1/A2/A3 三套断言函数（完全相同的像素断言），
    # 差异仅在后端名 —— 这就是"不同操作系统/驱动渲染一样效果"的验收。
}
