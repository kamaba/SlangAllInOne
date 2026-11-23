/* =========================================================================
 * sl_audio_wave_web.c —— Codec：WebAudio 播放内核（wasm 载体，2026-11-22）
 *
 * 替代 Codec/sl_audio_wave.c（waveOut，Windows 专属）的 Emscripten 实现，
 * 接口契约与 sla_wave_* 八函数逐一同构（sl_audio_internal.h）：
 *   - 打开：AudioContext（首次惰性创建）+ 每 player 一个环形缓冲 +
 *     ScriptProcessorNode（4096 帧）消费环；
 *   - enqueue：S16LE interleaved 块按指针直拷 JS 环（HEAP16 视图，
 *     Float32 归一化在 JS 侧回放时进行）；
 *   - 背压：buffered() 回读 JS 环水位（替代 waveOut 服务线程的
 *     WHDR_DONE 归还节奏），position = 已消费帧数；
 *   - 浏览器自动播放策略：AudioContext 由 JS 宿主在首次用户交互时
 *     resume（本文件只做 state 检查，不阻塞）。
 * 线程模型：wasm 单线程协作式，无锁（原 wave.c 的 CRITICAL_SECTION
 * 保护在这里不必要）。
 * 注意：EM_ASM 宏体内禁止"裸逗号"（预处理器会把花括号内的逗号当宏
 * 参数分隔符）——JS 全部用分号/赋值/括号保护的风格书写。
 * ========================================================================= */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <emscripten.h>

typedef struct SlaWaveOut
{
    int used;
    int sr, ch;
    int paused;
    int vol0100;                /* 0..100（映射 JS 侧 vol 0..1）      */
    int js_id;                  /* JS 侧 player 表槽位（1 起始）      */
} SlaWaveOut;

#define SLA_WAVE_WEB_MAX 8
static SlaWaveOut s_wave[SLA_WAVE_WEB_MAX];

/* JS 侧状态（module 级单例 Module.__slaAudio）：
 *   { ctx, players[id] = { ring Float32Array, cap, w, r, frames, played,
 *     ch, sr, paused, vol, node } } */

SlaWaveOut* sla_wave_open(int sample_rate, int channels)
{
    int i;
    SlaWaveOut* w = NULL;
    if (channels <= 0 || channels > 2 || sample_rate <= 0)
    {
        return NULL;
    }
    for (i = 0; i < SLA_WAVE_WEB_MAX; ++i)
    {
        if (!s_wave[i].used)
        {
            w = &s_wave[i];
            break;
        }
    }
    if (!w)
    {
        return NULL;
    }
    w->js_id = EM_ASM_INT({
        var A;
        if ((typeof Module.__slaAudio === 'undefined') || (!Module.__slaAudio)) {
            A = {};
            A.ctx = null;
            A.players = [];
            Module.__slaAudio = A;
        } else {
            A = Module.__slaAudio;
        }
        var id = 1;
        while ((id < A.players.length) && (A.players[id])) id++;
        if (!A.ctx) {
            var Ctor = (typeof window !== 'undefined') && (window.AudioContext || window.webkitAudioContext);
            if (!Ctor) return 0;
            A.ctx = new Ctor();
        }
        var cap = $0;
        var ring = new Float32Array(cap * $1);
        var node = A.ctx.createScriptProcessor(4096, 0, $1);
        var st = {};
        st.ring = ring; st.cap = cap; st.w = 0; st.r = 0;
        st.frames = 0; st.played = 0; st.ch = $1; st.sr = $0;
        st.paused = 0; st.vol = 1.0; st.node = node;
        node.onaudioprocess = function (ev) {
            var ob = ev.outputBuffer;
            var n = ob.length;
            var ch = st.ch;
            var total = st.cap * ch;
            for (var c = 0; c < ch; c++) {
                var out = ob.getChannelData(c);
                for (var k = 0; k < n; k++) {
                    var v = 0.0;
                    if ((!st.paused) && (st.frames > 0)) {
                        v = st.ring[st.r];
                        st.r = (st.r + 1) % total;
                        st.frames--;
                        st.played++;
                    }
                    out[k] = v * st.vol;
                }
            }
        };
        node.connect(A.ctx.destination);
        A.players[id] = st;
        return id;
    }, sample_rate, channels);
    if (w->js_id <= 0)
    {
        w->js_id = 0;
        return NULL;
    }
    w->used = 1;
    w->sr = sample_rate;
    w->ch = channels;
    w->paused = 0;
    w->vol0100 = 100;
    return w;
}

int64_t sla_wave_enqueue(SlaWaveOut* w, const short* pcm, int64_t frames)
{
    if (!w || !w->used || !pcm || frames <= 0)
    {
        return 0;
    }
    return EM_ASM_INT({
        var st = null;
        if (Module.__slaAudio) st = Module.__slaAudio.players[$0];
        if (!st) return 0;
        var src = new Int16Array(Module.HEAP16.buffer, $1, ($2 * st.ch));
        var total = st.cap * st.ch;
        var n = 0;
        for (var i = 0; i < $2; i++) {
            if (st.frames >= total) break;      /* 环满即止（返回已入帧数）*/
            for (var c = 0; c < st.ch; c++) {
                st.ring[st.w] = src[(i * st.ch) + c] / 32768.0;
                st.w = (st.w + 1) % total;
            }
            st.frames++;
            n++;
        }
        return n;
    }, w->js_id, (int)(intptr_t)pcm, (int)frames);
}

int sla_wave_pause(SlaWaveOut* w, int paused)
{
    if (!w || !w->used)
    {
        return 0;
    }
    w->paused = paused;
    EM_ASM({
        var st = null;
        if (Module.__slaAudio) st = Module.__slaAudio.players[$0];
        if (st) st.paused = $1;
        var A = Module.__slaAudio;
        if (A && A.ctx) {
            if (($1) && (A.ctx.state === 'running')) A.ctx.suspend();
            else if ((!$1) && (A.ctx.state === 'suspended')) A.ctx.resume();
        }
    }, w->js_id, paused ? 1 : 0);
    return 1;
}

int sla_wave_stop(SlaWaveOut* w)
{
    if (!w || !w->used)
    {
        return 0;
    }
    EM_ASM({
        var st = null;
        if (Module.__slaAudio) st = Module.__slaAudio.players[$0];
        if (st) { st.r = 0; st.w = 0; st.frames = 0; st.paused = 0; }
    }, w->js_id);
    w->paused = 0;
    return 1;
}

int64_t sla_wave_position(SlaWaveOut* w)
{
    if (!w || !w->used)
    {
        return 0;
    }
    return EM_ASM_INT({
        var st = null;
        if (Module.__slaAudio) st = Module.__slaAudio.players[$0];
        return st ? st.played : 0;
    }, w->js_id);
}

int sla_wave_volume(SlaWaveOut* w, int vol0100)
{
    if (!w || !w->used)
    {
        return 0;
    }
    if (vol0100 < 0) vol0100 = 0;
    if (vol0100 > 100) vol0100 = 100;
    w->vol0100 = vol0100;
    EM_ASM({
        var st = null;
        if (Module.__slaAudio) st = Module.__slaAudio.players[$0];
        if (st) st.vol = $1 / 100.0;
    }, w->js_id, vol0100);
    return 1;
}

int64_t sla_wave_buffered(SlaWaveOut* w)
{
    if (!w || !w->used)
    {
        return 0;
    }
    return EM_ASM_INT({
        var st = null;
        if (Module.__slaAudio) st = Module.__slaAudio.players[$0];
        return st ? st.frames : 0;
    }, w->js_id);
}

void sla_wave_close(SlaWaveOut* w)
{
    if (!w || !w->used)
    {
        return;
    }
    EM_ASM({
        var A = Module.__slaAudio;
        if (A) {
            var st = A.players[$0];
            if (st) {
                try { st.node.disconnect(); } catch (e) {}
                A.players[$0] = null;
            }
        }
    }, w->js_id);
    w->used = 0;
    w->js_id = 0;
}

int sla_wave_device_available(void)
{
    return EM_ASM_INT({
        var Ctor = (typeof window !== 'undefined') && (window.AudioContext || window.webkitAudioContext);
        return Ctor ? 1 : 0;
    });
}
