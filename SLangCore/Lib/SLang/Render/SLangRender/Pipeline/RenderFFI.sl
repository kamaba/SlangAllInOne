# RenderFFI —— 原生 FFI 静态绑定单点（doc/05 §3.2 规则 11 / D8）
#
# 本模块全部【新增】后端调用集中在此，用 @DllStaticImport 声明（装配期
# 绑定、零 SL 帧开销）；其它 .sl 禁止出现 SystemCallExternalFunction /
# SystemFFICallXxx / FFI attribute。存量调用按 doc/04 §5 批次迁移至此。
#
# 绑定规范（硬约束）：
#   - sig 必须用 FFI 短名（i32/i64/f32/f64/bool/ptr/utf8）；
#   - 返回 void 省略返回段（禁止 "->void"）；含 ptr 的签名必须手写 sig；
#   - 每个绑定必须提供 fallback 体（查询类返回 0/false、创建类返回 0
#     句柄）—— 无后端 DLL 时引擎可继续 Software 降级而不是崩溃；
#   - @DllStaticImport 函数保持一行转发形态，不参与自动 inline；
#   - FFI 参数 <= 6，超限描述符打包（Memory.alloc + writeXxx -> ptr）。
#
# Unity 对应概念：无（引擎原生层接入点；SLang.Render 侧的 slr_* 直连）。

public class RenderFFI
{
    # ── 命令流（D1 真录制）─────────────────────────────────
    # slr_cmd_execute_stream(pipe, streamPtr, commandCount)：
    # CommandBuffer 录制的 SLMC 命令流整包提交（布局 doc/04 §3.6），
    # C 侧逐 opcode 回放到当前 RHI 后端。调用方：
    # SLang.RenderPipeline.executeCommandBuffer（打包 + 提交 + 释放）。
    @DllStaticImport( "sl_render_lib", "slr_cmd_execute_stream", "i64,ptr,i32->bool" )
    public static bool ffiCmdExecuteStream( Int64 pipe, Int64 streamPtr, Int32 commandCount )
    {
        ret false
    }

    # ── 资源占用计数（Environment.Render 资源查明；0 = 未占用/DLL 缺失）──
    # slr_context_count() / slr_pipeline_count() / slr_texture_count()：
    # 全局注册表 used 槽位计数（上限 SLR_MAX_CTX=16 / SLR_MAX_PIPES=32 /
    # SLR_MAX_TEX=64，C 侧 sl_render.c）。调用方：Environment.Render.query。
    @DllStaticImport( "sl_render_lib", "slr_context_count", "->i32" )
    public static Int32 ffiContextCount()
    {
        ret 0
    }

    @DllStaticImport( "sl_render_lib", "slr_pipeline_count", "->i32" )
    public static Int32 ffiPipelineCount()
    {
        ret 0
    }

    @DllStaticImport( "sl_render_lib", "slr_texture_count", "->i32" )
    public static Int32 ffiTextureCount()
    {
        ret 0
    }
}
