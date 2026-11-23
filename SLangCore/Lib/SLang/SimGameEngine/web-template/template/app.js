/*
 * app.js - SimGameEngine wasm 通用 web 宿主模板（2026-11-23）。
 *
 * 页面只是"平台后端"，引擎（渲染/音频/输入/时间）整体跑在 wasm 里：
 *   1. 按 APP_CONFIG 拉取 SLB/资源，写入 MEMFS 同构目录
 *      （/work/out/export/... 与桌面 out/export 布局同构，模块装载器按此找依赖）
 *   2. boot wasm（createModule）→ 把 canvas 交给 Emscripten EGL → WebGL2
 *   3. 引擎每帧 readback RGBA8 → sle_web_blit → onBlit → texImage2D 上屏
 *   4. 键盘/鼠标事件 → Module._sle_input_set_*（引擎 C 输入表，
 *      与桌面 QT 宿主喂的是同一张表；键码 = Qt::Key 枚举值）
 *   5. 首次用户手势恢复 WebAudio（引擎 sl_audio_wave_web 复用同一 AudioContext）
 *
 * 接入新工程：只改下面 APP_CONFIG + 资源清单，其余不动。
 */
(function () {
  'use strict';

  // ══════════════════════════════════════════════════════════════════
  // APP_CONFIG —— 新工程唯一的必改点
  // ══════════════════════════════════════════════════════════════════
  var APP_CONFIG = {
    // wasm 产物（csimple_lang build 目标链接 sim engine/render/audio 后的 js 载体）
    wasmScript: 'wasm/csimple_lang_game.js',
    // 主模块（本工程的 SL 编译产物；server.js 会把它映射到 out/export/<NAME>/）
    rootModuleName: 'MyGameWeb',
    rootSlbUrl: 'mod/MyGameWeb.module.slb',
    // MEMFS 内的落盘路径必须与桌面 out/export 同构：/work/out/export/<Name>/
    rootSlbMemPath: '/work/out/export/MyGameWeb/MyGameWeb.module.slb',
    // 依赖模块清单（与 jsonc imports 一致；引擎渲染必带 SLangRender + SimGameEngine）
    depMods: ['Core', 'Std', 'Math', 'SLangImage', 'SLangRender', 'SLangAudio', 'SimGameEngine'],
    // 工程私有资源：url = server.js 暴露的虚拟路径；mem = MEMFS 绝对路径
    assets: [
      // { url: 'sfx/eat.wav', mem: '/work/mygame/sfx/eat.wav' },
    ],
    // 渲染分辨率（RenderSystem.init / readback 尺寸；canvas width/height 属性须一致）
    renderWidth: 320,
    renderHeight: 320
  };
  // FairyGUI 命中测试会从引擎表坐标里减去桌面 QLabel 的 (10,10) 偏移，
  // 因此 JS 注入鼠标坐标时 +10 补偿；不用 FairyUI 的工程保持 10 也无副作用。
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

  // ── Qt::Key 码表（引擎 InputSystem 常量：字母/数字 = ASCII，功能键 0x01000000+）──
  var QT_KEY = {
    ArrowUp: 16777235, ArrowDown: 16777237,
    ArrowLeft: 16777234, ArrowRight: 16777236,
    Space: 32, Enter: 16777220,
    KeyW: 87, KeyA: 65, KeyS: 83, KeyD: 68, KeyR: 82, KeyP: 80,
    Escape: 16777216, ControlLeft: 16777249, ControlRight: 16777249,
    F12: 16777334, Home: 16777232
  };

  // ── 呈现路径（引擎像素 → 屏幕）：独立 WebGL2 program，全屏三角贴图 ──
  var gl = null;
  var presentTex = null;
  var presProg = null;
  var presBuf = null;
  var presAPos = 0;

  function initPresent() {
    // preserveDrawingBuffer：外部 readPixels/截图可取呈现后画面（诊断用）
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

  // 引擎 C 侧每帧回调（sle_web_glue.c EM_JS 按 Module.__<name> 查找）。
  // 关键：引擎 GLES 渲染与本呈现共享同一个 WebGL2 context，渲染会改写
  // program/activeTexture/attrib 绑定 —— 每次 blit 前必须完整恢复呈现
  // 状态，否则 drawArrays 用错状态 → GL_INVALID_OPERATION + 黑屏。
  function onBlit(ptr, w, h) {
    if (!gl || !mod) return false;
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
    return true;
  }

  // ── 输入注入（引擎 C 表；游戏层经 InputSystem 门面查询）──────────────
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
    // 浏览器自动播放策略：首个用户手势时 resume；引擎 wave_web 后端
    // 复用该 AudioContext（Module.__slaAudio.ctx）
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
    }
    ensureAudioResume();
  });
  window.addEventListener('keyup', function (e) {
    var k = QT_KEY[e.code];
    if (k !== undefined) {
      sendKey(k, false);
    }
  });
  canvas.addEventListener('mousemove', function (e) {
    var r = canvas.getBoundingClientRect();
    // CSS 缩放换算回画布像素坐标再注入
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

  // MEMFS 同构布局：/work/out/export/<模块名>/ 与桌面 out/export 完全一致，
  // SL 模块装载器按该布局解析 import 依赖 —— 这是页面侧唯一的"布局契约"。
  function stageAssets(Module, mods) {
    var FS = Module.FS;
    FS.mkdirTree(APP_CONFIG.rootSlbMemPath.replace(/\/[^/]+$/, ''));
    FS.writeFile(APP_CONFIG.rootSlbMemPath, rootSlb);
    for (var i = 0; i < APP_CONFIG.depMods.length; i++) {
      var name = APP_CONFIG.depMods[i];
      var dir = '/work/out/export/' + name;
      FS.mkdirTree(dir);
      FS.writeFile(dir + '/' + name + '.module.json', mods[name].json);
      if (mods[name].slb) {
        FS.writeFile(dir + '/' + name + '.module.slb', mods[name].slb);
      }
    }
    for (var a = 0; a < ASSET_LIST.length; a++) {
      var p = ASSET_LIST[a].mem.split('/');
      p.pop();
      FS.mkdirTree(p.join('/'));
      FS.writeFile(ASSET_LIST[a].mem, assetFiles[a]);
    }
  }

  var rootSlb = null;
  var ASSET_LIST = APP_CONFIG.assets;
  var assetFiles = null;

  var loads = [fetchBin(APP_CONFIG.rootSlbUrl)];
  APP_CONFIG.depMods.forEach(function (name) {
    loads.push(fetchText('mod/' + name + '.module.json'));
    loads.push(fetchBin('mod/' + name + '.module.slb'));
  });
  ASSET_LIST.forEach(function (a) { loads.push(fetchBin(a.url)); });

  Promise.all(loads).then(function (res) {
    rootSlb = new Uint8Array(res[0]);
    var idx = 1;
    var mods = {};
    APP_CONFIG.depMods.forEach(function (name) {
      mods[name] = { json: res[idx], slb: new Uint8Array(res[idx + 1]) };
      idx += 2;
    });
    assetFiles = ASSET_LIST.map(function () { return new Uint8Array(res[idx++]); });

    var script = document.createElement('script');
    script.src = APP_CONFIG.wasmScript;
    script.onload = function () {
      setStatus('VM 装配中（引擎初始化 + 模块装载）…');
      window.createModule({
        canvas: canvas,               // Emscripten EGL 在其上建 WebGL2 上下文
        print: function (t) { appendStatus(String(t)); },
        printErr: function (t) { appendStatus(String(t)); },
        noInitialRun: true
      }).then(function (Module) {
        mod = Module;
        window.__mod = Module;        // 调试通道：控制台可达 wasm 导出
        // 平台桥回调：sle_web_glue.c 的 EM_JS 按下列固定名查找（契约名，
        // 不可改；要改名必须同步改 cvm_sim_engine_lib/sle_web_glue.c 重链）：
        //   __snakeOnBlit(ptr,w,h)          像素块上屏
        //   __snakeCanvasWidth/Height()     画布尺寸（引擎窗口尺寸回调）
        Module.__snakeOnBlit = onBlit;
        Module.__snakeCanvasWidth = function () { return canvas.width; };
        Module.__snakeCanvasHeight = function () { return canvas.height; };
        if (!initPresent()) return;
        stageAssets(Module, mods);
        setStatus('运行中（引擎泵帧 @16ms，点击画布任意处恢复声音）');
        try {
          // noInitialRun + 显式 callMain：argv[2] = MEMFS 主模块路径
          Module.callMain(['run', '--no-banner', APP_CONFIG.rootSlbMemPath]);
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
      setStatus('wasm js 加载失败（先构建 game wasm 目标）', true);
    };
    document.head.appendChild(script);
  }).catch(function (e) {
    setStatus('资源加载失败: ' + (e && e.message ? e.message : e), true);
  });
})();
