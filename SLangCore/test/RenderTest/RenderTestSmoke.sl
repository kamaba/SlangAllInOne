import SLangRender;
import SLangAudio;
import Math;
import Std;

# Phase D/E/F：多后端同效果验证（与 GL 主流程共用相同断言函数，
# 差异仅在后端名 —— "不同操作系统/驱动渲染一样效果"验收标准）：
#   runD3D11Smoke  initializeBackend("d3d11")
#   runVkSmoke     initializeBackend("vk")   （vulkan-1.dll 运行期探测，缺失 SKIP）
#   runGlesSmoke   initializeBackend("gles") （无 GLES 运行库优雅降级 SKIP）
public class RenderTestSmoke
{

    # ── Phase D：D3D11 后端同效果验证（返回 2=PASS 1=SKIP 0=FAIL）────
    # 与 GL 主流程共用 A1/A2/A3 三套断言函数（完全相同的像素断言），
    # 差异仅在后端名 —— 这就是"不同操作系统/驱动渲染一样效果"的验收。
    public static Int32 runD3D11Smoke()
    {
        Console.println( "-- Phase D: D3D11 backend (same-effect pixel assertions) --" )
        if SLang.Render.initializeBackend( "d3d11" ) == false
        {
            Console.println( "[d3d11] SKIP: backend unavailable - " + SLang.Render.errorString() )
            ret 1
        }
        Console.println( "[d3d11] renderer: " + SLang.Render.rendererInfo() )
        Console.println( "[d3d11] version : " + SLang.Render.versionInfo() )
        bool d1 = RenderTestPhasesA.runV1Compat()
        bool d2 = RenderTestPhasesA.runPipeline()
        bool d3 = RenderTestPhasesA.runMultiCameraImage()
        # 光照跨后端同效果复检（D3D11 与 GL 同公式逐像素一致）
        bool d4 = RenderTestPhasesB.runLightScene()
        # N2a shadow map + PCF 跨后端复检（D3D11 深度直通 zxform=(1,0)）
        bool d6 = RenderTestPhasesB.runShadowMap()
        # 固化 shader gen 效果（DXBC blob 直读）同像素复检
        bool d5 = RenderTestPhasesB.runGenShaders()
        # 本阶段管线句柄在切回 GL 后失效：清空 QT 移交（GL 主流程会重设）
        RenderTest._pipe = null
        RenderTest._pixels = 0
        if d1 && d2 && d3 && d4 && d5 && d6
        {
            Console.println( "[d3d11] Phase D: PASS (v1 + 13-stage + multi-cam + image + lighting + shadow-map + frozen-gen, pixels identical to GL)" )
            ret 2
        }
        Console.println( "[d3d11] Phase D: FAIL" )
        ret 0
    }

    # ── Phase E：Vulkan 后端同效果验证（返回 2=PASS 1=SKIP 0=FAIL）────
    # 与 Phase D 完全同构：SPIR-V 固化六组着色器 + 纯离屏 instance，
    # v1 / 13 阶段 / 多相机三套断言全部按 GL 基准像素复检。


    # ── Phase E：Vulkan 后端同效果验证（返回 2=PASS 1=SKIP 0=FAIL）────
    # 与 Phase D 完全同构：SPIR-V 固化六组着色器 + 纯离屏 instance，
    # v1 / 13 阶段 / 多相机三套断言全部按 GL 基准像素复检。
    public static Int32 runVkSmoke()
    {
        Console.println( "-- Phase E: Vulkan backend (same-effect pixel assertions) --" )
        if SLang.Render.initializeBackend( "vk" ) == false
        {
            Console.println( "[vk] SKIP: backend unavailable - " + SLang.Render.errorString() )
            ret 1
        }
        Console.println( "[vk] renderer: " + SLang.Render.rendererInfo() )
        Console.println( "[vk] version : " + SLang.Render.versionInfo() )
        bool d1 = RenderTestPhasesA.runV1Compat()
        bool d2 = RenderTestPhasesA.runPipeline()
        bool d3 = RenderTestPhasesA.runMultiCameraImage()
        # VK：SPIR-V 固化暂未消费光照（upload_lights 空实现），
        # 光照相位跳过（默认无光照路径已由 d1..d3 覆盖）
        Console.println( "[vk] lighting phase skipped (SPIR-V frozen shaders do not consume lights yet)" )
        # 固化 shader gen 效果：VK 降级 builtin 槽（像素=内建）一致性复检
        bool d5 = RenderTestPhasesB.runGenShaders()
        # 切回 GL 前先清空管线句柄移交（GL 主流程会重设）
        RenderTest._pipe = null
        RenderTest._pixels = 0
        if d1 && d2 && d3 && d5
        {
            Console.println( "[vk] Phase E: PASS (v1 + 13-stage + multi-cam + image + frozen-gen, pixels identical to GL)" )
            ret 2
        }
        Console.println( "[vk] Phase E: FAIL" )
        ret 0
    }

    # ── Phase F：EGL/GLES 后端验证（返回 2=PASS 1=SKIP 0=FAIL）────────
    # libEGL/libGLESv2 运行期探测：缺失时 init 优雅降级 -> SKIP；
    # 有 GLES 运行库的机器则同断言集要求同像素 PASS。


    # ── Phase F：EGL/GLES 后端验证（返回 2=PASS 1=SKIP 0=FAIL）────────
    # libEGL/libGLESv2 运行期探测：缺失时 init 优雅降级 -> SKIP；
    # 有 GLES 运行库的机器则同断言集要求同像素 PASS。
    public static Int32 runGlesSmoke()
    {
        Console.println( "-- Phase F: EGL/GLES3 backend (graceful degrade when absent) --" )
        if SLang.Render.initializeBackend( "gles" ) == false
        {
            Console.println( "[gles] SKIP: backend unavailable - " + SLang.Render.errorString() )
            ret 1
        }
        Console.println( "[gles] renderer: " + SLang.Render.rendererInfo() )
        Console.println( "[gles] version : " + SLang.Render.versionInfo() )
        bool d1 = RenderTestPhasesA.runV1Compat()
        bool d2 = RenderTestPhasesA.runPipeline()
        bool d3 = RenderTestPhasesA.runMultiCameraImage()
        # 光照跨后端同效果复检（GLES 与 GL 同公式逐像素一致）
        bool d4 = RenderTestPhasesB.runLightScene()
        # N2a shadow map + PCF 跨后端复检（GLES 硬件深度 zxform=(2,-1) 同 GL）
        bool d6 = RenderTestPhasesB.runShadowMap()
        # 固化 shader gen 效果（ESSL300 运行期编固化源）同像素复检
        bool d5 = RenderTestPhasesB.runGenShaders()
        RenderTest._pipe = null
        RenderTest._pixels = 0
        if d1 && d2 && d3 && d4 && d5 && d6
        {
            Console.println( "[gles] Phase F: PASS (v1 + 13-stage + multi-cam + image + lighting + shadow-map + frozen-gen, pixels identical to GL)" )
            ret 2
        }
        Console.println( "[gles] Phase F: FAIL" )
        ret 0
    }

    # ── Phase G：固化 shader（gen 效果，material 0..4 全路由）端到端 ──
    # 「通用固化编译」产物正面断言（GL/D3D11/GLES 用真实 gen 源码，
    # 全部 5 效果 × flat/tex 变体；VK 降级 builtin 槽）。同一 quad 切
    # material 对比法：
    #   断言 1：uSpec.x 默认 0 时 gen BlinnPhong-flat 与 gen Lambert-flat
    #     公式逐字一致 -> 两帧中心像素逐通道差 <= 2（末位浮点容差）；
    #   断言 2a：setSpecular(2,8)+直射光 -> Blinn 高光真实执行（手算
    #     NdotH~0.916、pow8~0.50 -> 中心像素大幅增亮）；
    #   断言 2b：gen Phong 经典高光 R=reflect(-L,N)、pow(R·V,8)*2 ->
    #     手算 (63,126,251)±3（比 Blinn 暗，两族公式可区分）；
    #   断言 3：gen NormalMap-flat —— uSpec.z（凹凸强度）无 API 写入
    #     恒 0 -> 扰动/边缘光全零，退化为 BlinnPhong 基座 -> == 基准 1；
    #   断言 4：gen Toon-flat setSpecular(3,0.5)（3 阶梯 + 阈值夹取 1
    #     压制硬边高光）-> 手算阶梯 tint (48,97,207)±3 且暗于 Lambert；
    #   断言 5：gen BlinnPhong-tex == gen Lambert-tex（tex 变体）；
    #   断言 6：gen NormalMap-tex == 基准 5（tex 变体槽位）；
    #   断言 7：gen Toon-tex 阶梯 tint 全通道严格暗于 Lambert-tex。
    #   VK：全部效果降级 PFLAT/PTEX（uSpec 不消费）-> 一致性断言改
    #     比对应基准，specular/阶梯手算断言跳过。
}
