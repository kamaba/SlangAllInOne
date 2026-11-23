﻿/*
 * game.js - SnakeGame browser host (2026-11-22 architecture fix).
 *
 * Layering: SimGameEngine (render/audio/input/time) runs INSIDE the wasm
 * binary (csimple_lang_game build links sl_sim_engine_lib + sl_render_lib
 * GLES backend + sl_audio_lib). The SL game module (SnakeGameWeb.slb:
 * WebHost + SnakeGameBehaviour + SnakeFairy + SnakeSfx) drives the engine
 * via its public API. This page is ONLY the platform backend:
 *   1. boot wasm (createModule) + stage MEMFS isomorphic layout
 *   2. hand Module.canvas to Emscripten EGL -> WebGL2 context (engine RHI
 *      renders into it; readback pixels are blitted via sle_web_blit ->
 *      __snakeOnBlit -> texImage2D)
 *   3. keyboard/mouse events -> Module._sle_input_set_* (engine C input
 *      table; same table the desktop QT bridge feeds)
 *   4. WebAudio context resume on first user gesture (engine's
 *      sl_audio_wave_web.c pushes PCM into a JS ring buffer)
 *
 * NOTE: print/printErr carry SL Console output (diagnostics only) - there
 * is no frame protocol anymore; the engine renders, JS just presents.
 */
(function () {
  'use strict';

  // ── MEMFS isomorphic layout (mirrors out/export, WASM_BUILD.md 5.1) ──
  var ROOT_SLB = '/work/out/export/SnakeGameWeb/SnakeGameWeb.module.slb';
  var DEP_MODS = ['Core', 'Std', 'Math', 'SLangImage', 'SLangRender', 'SLangAudio', 'SimGameEngine'];
  // FairyGUI Mouse hit test subtracts the desktop QLabel (10,10) offset from
  // engine-table coords, so JS injects canvas-relative + 10 to compensate.
  var MOUSE_OFFSET = 10;

  var statusEl = document.getElementById('status');
  var canvas = document.getElementById('cv');

  function setStatus(text, isErr) {
    statusEl.textContent = text;
    statusEl.className = isErr ? 'err' : '';
  }
  function appendStatus(text) {
    statusEl.textContent = (statusEl.textContent + '\n' + text).slice(-600);
  }

  // ── Qt::Key map (engine InputSystem constants) ──────────────────────
  var QT_KEY = {
    ArrowUp: 16777235, ArrowDown: 16777237,
    ArrowLeft: 16777234, ArrowRight: 16777236,
    Space: 32, Enter: 16777220,
    KeyW: 87, KeyA: 65, KeyS: 83, KeyD: 68, KeyR: 82, KeyP: 80,
    Escape: 16777216, ControlLeft: 16777249, ControlRight: 16777249,
    F12: 16777334, Home: 16777232
  };

  // ── WebGL2 present path (engine pixels -> screen) ───────────────────
  var gl = null;
  var presentTex = null;
  var presProg = null;
  var presUBO = null;
  var presBuf = null;
  var presAPos = 0;

  function initPresent() {
    // preserveDrawingBuffer：让外部 readPixels/截图能取到呈现后的画面
    // （诊断用途，320x320 开销可忽略）
    gl = canvas.getContext('webgl2', { antialias: false, preserveDrawingBuffer: true });
    if (!gl) { setStatus('WebGL2 不可用', true); return false; }
    var vs = [
      'attribute vec2 a_pos;',
      'varying vec2 v_uv;',
      'void main() {',
      '  gl_Position = vec4(a_pos, 0.0, 1.0);',
      '  v_uv = vec2((a_pos.x + 1.0) * 0.5, 1.0 - (a_pos.y + 1.0) * 0.5);',
      '}'
    ].join('\n');
    var fs = [
      'precision mediump float;',
      'varying vec2 v_uv;',
      'uniform sampler2D u_tex;',
      'void main() { gl_FragColor = texture2D(u_tex, v_uv); }'
    ].join('\n');
    function sh(type, src) {
      var s = gl.createShader(type);
      gl.shaderSource(s, src);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
        throw new Error('shader: ' + gl.getShaderInfoLog(s));
      }
      return s;
    }
    presProg = gl.createProgram();
    gl.attachShader(presProg, sh(gl.VERTEX_SHADER, vs));
    gl.attachShader(presProg, sh(gl.FRAGMENT_SHADER, fs));
    gl.linkProgram(presProg);
    if (!gl.getProgramParameter(presProg, gl.LINK_STATUS)) {
      throw new Error('present program: ' + gl.getProgramInfoLog(presProg));
    }
    gl.useProgram(presProg);
    presBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, presBuf);
    gl.bufferData(gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, -1, 1, 1, 1, -1, -1, 1, 1, 1, -1]), gl.STATIC_DRAW);
    presAPos = gl.getAttribLocation(presProg, 'a_pos');
    gl.enableVertexAttribArray(presAPos);
    gl.vertexAttribPointer(presAPos, 2, gl.FLOAT, false, 0, 0);
    presentTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, presentTex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.uniform1i(gl.getUniformLocation(presProg, 'u_tex'), 0);
    return true;
  }

  // engine -> JS callback (wired by sle_web_glue.c EM_JS)
  window.__blitCount = 0;
  function onBlit(ptr, w, h) {
    if (!gl || !mod) return false;
    // 引擎 GLES 帧渲染与本呈现路径共享同一个 WebGL2 context（EGL shim
    // 与 getContext('webgl2') 命中同一上下文），引擎渲染会改写 program/
    // activeTexture/attrib 绑定——每次 blit 前必须完整恢复呈现状态，
    // 否则 drawArrays 用错状态 → GL_INVALID_OPERATION + 黑屏。
    var view = new Uint8Array(mod.HEAPU8.buffer, ptr, w * h * 4);
    gl.useProgram(presProg);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, presentTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, view);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.bindBuffer(gl.ARRAY_BUFFER, presBuf);
    gl.enableVertexAttribArray(presAPos);
    gl.vertexAttribPointer(presAPos, 2, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    window.__blitCount++;
    return true;
  }

  // ── input injection into the engine C table ─────────────────────────
  var mod = null;
  function sendKey(qtKey, down) {
    if (mod && mod._sle_input_set_key) {
      mod._sle_input_set_key(qtKey, down ? 1 : 0);
    }
  }
  function sendMousePos(x, y) {
    if (mod && mod._sle_input_set_mouse_pos) {
      mod._sle_input_set_mouse_pos(x + MOUSE_OFFSET, y + MOUSE_OFFSET);
    }
  }
  function sendMouseButton(down) {
    if (mod && mod._sle_input_set_mouse_button) {
      mod._sle_input_set_mouse_button(1, down ? 1 : 0);
    }
  }

  function ensureAudioResume() {
    // browser autoplay policy: resume on first user gesture; the engine's
    // wave_web backend reuses this AudioContext (Module.__slaAudio.ctx)
    var A = mod && mod.__slaAudio;
    if (A && A.ctx && A.ctx.state === 'suspended') {
      A.ctx.resume();
    }
  }

  window.addEventListener('keydown', function (e) {
    if (QT_KEY[e.code] !== undefined) e.preventDefault();
    var k = QT_KEY[e.code];
    if (k !== undefined && !e.repeat) {
      sendKey(k, true);
      appendStatus('[key] ' + e.code + ' -> ' + k + ' down (injected=' + !!(mod && mod._sle_input_set_key) + ')');
    }
    ensureAudioResume();
  });
  window.addEventListener('keyup', function (e) {
    var k = QT_KEY[e.code];
    if (k !== undefined) {
      sendKey(k, false);
      appendStatus('[key] ' + e.code + ' -> ' + k + ' up');
    }
  });
  canvas.addEventListener('mousemove', function (e) {
    var r = canvas.getBoundingClientRect();
    sendMousePos(Math.round((e.clientX - r.left) * canvas.width / r.width),
                 Math.round((e.clientY - r.top) * canvas.height / r.height));
  });
  canvas.addEventListener('mousedown', function (e) {
    ensureAudioResume();
    sendMouseButton(true);
    e.preventDefault();
  });
  window.addEventListener('mouseup', function () { sendMouseButton(false); });
  canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });

  // ── wasm VM boot ────────────────────────────────────────────────────
  function fetchBin(url) {
    return fetch(url).then(function (r) {
      if (!r.ok) throw new Error(url + ' HTTP ' + r.status);
      return r.arrayBuffer();
    });
  }
  function fetchText(url) {
    return fetch(url).then(function (r) {
      if (!r.ok) throw new Error(url + ' HTTP ' + r.status);
      return r.text();
    });
  }

  function stageAssets(Module, mods) {
    var FS = Module.FS;
    FS.mkdirTree('/work/out/export/SnakeGameWeb');
    FS.mkdirTree('/work/snake/sfx');
    FS.mkdirTree('/work/snake/fairyui');
    FS.writeFile(ROOT_SLB, rootSlb);
    for (var i = 0; i < DEP_MODS.length; i++) {
      var name = DEP_MODS[i];
      var dir = '/work/out/export/' + name;
      FS.mkdirTree(dir);
      FS.writeFile(dir + '/' + name + '.module.json', mods[name].json);
      if (mods[name].slb) {
        FS.writeFile(dir + '/' + name + '.module.slb', mods[name].slb);
      }
    }
    for (var s = 0; s < sfxNames.length; s++) {
      FS.writeFile('/work/snake/sfx/' + sfxNames[s], sfxFiles[s]);
    }
    if (fairyFiles) {
      for (var u = 0; u < fairyNames.length; u++) {
        FS.writeFile('/work/snake/fairyui/' + fairyNames[u], fairyFiles[u]);
      }
    }
  }

  var rootSlb = null;
  var sfxNames = ['eat.wav', 'die.wav', 'start.wav', 'move.wav', 'bgm.wav'];
  var sfxFiles = null;
  var fairyNames = ['package.xml', 'component.xml', 'atlas.png', 'logo.png', 'go3d.png'];
  var fairyFiles = null;

  // 诊断开关：?noui=1 跳过 FairyUI 资源加载 → SnakeFairy.load 走缺资源
  // 降级（ren.draw 恒 false 不画 UI）→ 纯引擎场景画面，用于区分
  // "场景没画"与"UI 覆盖"。资源请求各自独立（URL 参数不会带上），
  // 必须由页面侧（而非 server 路由）实施。
  var NO_UI = location.search.indexOf('noui=1') >= 0;

  var loads = [fetchBin('mod/SnakeGameWeb.module.slb')];
  DEP_MODS.forEach(function (name) {
    loads.push(fetchText('mod/' + name + '.module.json'));
    loads.push(fetchBin('mod/' + name + '.module.slb'));
  });
  sfxNames.forEach(function (n) { loads.push(fetchBin('sfx/' + n)); });
  if (!NO_UI) {
    fairyNames.forEach(function (n) { loads.push(fetchBin('fairyui/' + n)); });
  }

  Promise.all(loads).then(function (res) {
    rootSlb = new Uint8Array(res[0]);
    var idx = 1;
    var mods = {};
    DEP_MODS.forEach(function (name) {
      mods[name] = { json: res[idx], slb: new Uint8Array(res[idx + 1]) };
      idx += 2;
    });
    sfxFiles = sfxNames.map(function () { return new Uint8Array(res[idx++]); });
    fairyFiles = NO_UI ? null : fairyNames.map(function () { return new Uint8Array(res[idx++]); });

    var script = document.createElement('script');
    script.src = 'wasm/csimple_lang_game.js';
    script.onload = function () {
      setStatus('VM 装配中（引擎初始化 + 模块装载）…');
      window.createModule({
        canvas: canvas,
        print: function (t) { appendStatus(String(t)); },
        printErr: function (t) { appendStatus(String(t)); },
        noInitialRun: true
      }).then(function (Module) {
        mod = Module;
        window.__mod = Module; // 调试通道：浏览器控制台可达 wasm 导出（FS 探针等）
        Module.__snakeOnBlit = onBlit;
        Module.__snakeCanvasWidth = function () { return canvas.width; };
        Module.__snakeCanvasHeight = function () { return canvas.height; };
        if (!initPresent()) return;
        stageAssets(Module, mods);
        setStatus('运行中（引擎泵帧 @16ms，点击画布任意处恢复声音）');
        try {
          Module.callMain(['run', '--no-banner', ROOT_SLB]);
        } catch (e) {
          if (!(e && e.name === 'ExitStatus')) {
            setStatus('VM 异常: ' + (e && e.message ? e.message : e), true);
          }
        }
      }).catch(function (e) {
        setStatus('wasm 实例创建失败: ' + (e && e.message ? e.message : e), true);
      });
    };
    script.onerror = function () {
      setStatus('csimple_lang_game.js 加载失败（先构建 game wasm 目标）', true);
    };
    document.head.appendChild(script);
  }).catch(function (e) {
    setStatus('资源加载失败: ' + (e && e.message ? e.message : e), true);
  });
})();
