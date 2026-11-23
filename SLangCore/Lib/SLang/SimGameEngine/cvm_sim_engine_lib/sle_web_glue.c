/* =========================================================================
 * sle_web_glue.c —— SimGameEngine wasm 平台桥实现（见 sle_web_glue.h）
 * Emscripten 专属：整文件仅在 __EMSCRIPTEN__ 构建编入（桌面 VS 工程
 * 不包含本文件，保持桌面路径零改动）。
 * ========================================================================= */
#if defined(__EMSCRIPTEN__)

#include <stdint.h>
#include <emscripten.h>
#include "sle_web_glue.h"

/* JS 回调约定（game.js 实现）：
 *   Module.__snakeOnBlit(ptr, w, h)        像素块上屏
 *   Module.__snakeCanvasWidth()            画布 CSS 宽
 *   Module.__snakeCanvasHeight()           画布 CSS 高 */
EM_JS(int, sle_web_blit_js, (int ptr, int w, int h), {
    if (Module.__snakeOnBlit) return Module.__snakeOnBlit(ptr, w, h) ? 1 : 0;
    return 0;
});
EM_JS(int, sle_web_canvas_w_js, (void), {
    return Module.__snakeCanvasWidth ? Module.__snakeCanvasWidth() : 0;
});
EM_JS(int, sle_web_canvas_h_js, (void), {
    return Module.__snakeCanvasHeight ? Module.__snakeCanvasHeight() : 0;
});

int sle_web_blit(int64_t ptr, int32_t w, int32_t h)
{
    if (ptr <= 0 || w <= 0 || h <= 0)
    {
        return 0 - 1;
    }
    /* wasm32 线性地址 < 4GB，截断到 i32 传 JS 安全 */
    return sle_web_blit_js((int)(intptr_t)ptr, (int)w, (int)h);
}

int32_t sle_web_window_width(void)
{
    return (int32_t)sle_web_canvas_w_js();
}

int32_t sle_web_window_height(void)
{
    return (int32_t)sle_web_canvas_h_js();
}

#endif /* __EMSCRIPTEN__ */
