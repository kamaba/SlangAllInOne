/* =========================================================================
 * sle_web_glue.h —— SimGameEngine wasm 平台桥（web 载体，2026-11-22）
 *
 * 职责边界（分层约束）：本桥只服务【平台宿主层】（WebPlatform.sl 等价
 * 桌面 QTHost 的角色），游戏逻辑层不得调用——游戏层只走引擎公开 API
 * （Application/InputSystem/RenderSystem/SLangAudio/FairyGUI）。
 * 全部 EM_JS/EM_ASM 直连 JS 宿主回调（Module.__snakeOnBlit 等），
 * 供 WebPlatform 的 @DllStaticImport("sl_sim_engine_lib", ...) 绑定。
 * ========================================================================= */
#ifndef SLE_WEB_GLUE_H
#define SLE_WEB_GLUE_H

#ifdef __cplusplus
extern "C" {
#endif

/* 呈现一帧：ptr = RGBA8 top-down 块（引擎 readback 契约），w×h 像素。
 * JS 侧回调 Module.__snakeOnBlit(ptr, w, h) 上屏（texImage2D）。 */
int sle_web_blit(int64_t ptr, int32_t w, int32_t h);

/* 画布尺寸（CSS 像素；游戏层布局决策的宿主窗口等价读数）。 */
int32_t sle_web_window_width(void);
int32_t sle_web_window_height(void);

#ifdef __cplusplus
}
#endif

#endif /* SLE_WEB_GLUE_H */
