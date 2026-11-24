/*
 * app.js - GameTest wasm web 宿主（web-template/app.js 的 GameTest 多工程版）。
 *
 * 页面两层 UI（与 SceneDemo H5 同款交互）：
 *   ① 主菜单（index.html 无 ?demo= 参数）：列出 GameTest 的 4 个 wasm 工程，
 *      点一项进入 ?demo=<key>；
 *   ② 演示页：顶部一排按钮菜单 —— 最左「主菜单」返回入口（左键位），
 *      其后为该工程的快捷按钮（键码/滚轮注入引擎 C 输入表）；
 *      SceneDemo 另有渲染分辨率下拉框（canvas 属性即时生效）。
 *
 * 引擎整体跑在 wasm 里（csimple_lang_game）：注入事件 + 上屏像素，无帧协议。
 * 布局契约：/work/out/export/<模块>/<模块>.module.{json,slb}（模块装载器按此
 * 解析 import 依赖）；EM_JS 回调契约名 __snakeOnBlit / __snakeCanvasWidth/Height。
 */
(function () {
  'use strict';

  // ══════════════════════════════════════════════════════════════════
  // DEMOS —— GameTest 4 个 wasm 工程的唯一配置点
  //   mode: 'scene' = SceneDemo（键码按钮 + 分辨率下拉 + 鼠标交互）
  //         'gallery' = 图库（◀/▶ 注入滚轮切格；画布内方向键也可切）
  // ══════════════════════════════════════════════════════════════════
  var DEP_BASE = ['Core', 'Std', 'Math', 'SLangImage', 'SLangRender', 'SLangAudio', 'SimGameEngine'];
  var DEMOS = {
    scenedemo: {
      title: 'SceneDemo',
      desc: '场景管理：5 个场景 / 菜单点击 / WASD + 拖拽 + 滚轮 / Gizmo',
      mode: 'scene',
      rootModuleName: 'SceneDemoWeb',
      renderWidth: 480,
      renderHeight: 480,
      depMods: DEP_BASE,
      // 工程资源（场景 JSON / FairyGUI 包 / 贴图）→ MEMFS 工程目录 + cwd 探测
      chdir: '/work/proj',
      assets: [
        { url: 'gt-assets/scenes/MaterialBall.scene.json',    mem: '/work/proj/assets/scenes/MaterialBall.scene.json' },
        { url: 'gt-assets/scenes/ShapeGallery.scene.json',    mem: '/work/proj/assets/scenes/ShapeGallery.scene.json' },
        { url: 'gt-assets/scenes/PureTest.scene.json',        mem: '/work/proj/assets/scenes/PureTest.scene.json' },
        { url: 'gt-assets/scenes/MaterialGallery.scene.json', mem: '/work/proj/assets/scenes/MaterialGallery.scene.json' },
        { url: 'gt-assets/scenes/RotateTest.scene.json',      mem: '/work/proj/assets/scenes/RotateTest.scene.json' },
        { url: 'gt-assets/fairygui/Demo/package.xml',         mem: '/work/proj/assets/fairygui/Demo/package.xml' },
        { url: 'gt-assets/fairygui/Demo/DemoUI.xml',          mem: '/work/proj/assets/fairygui/Demo/DemoUI.xml' },
        { url: 'gt-assets/fairygui/Demo/atlas@ui.png',        mem: '/work/proj/assets/fairygui/Demo/atlas@ui.png' },
        { url: 'gt-assets/fairygui/Demo/Demo.fui',            mem: '/work/proj/assets/fairygui/Demo/Demo.fui' },
        { url: 'gt-assets/fairygui/MainMenu/package.xml',     mem: '/work/proj/assets/fairygui/MainMenu/package.xml' },
        { url: 'gt-assets/fairygui/MainMenu/MainMenu.xml',    mem: '/work/proj/assets/fairygui/MainMenu/MainMenu.xml' },
        { url: 'gt-assets/fairygui/MainMenu/atlas@menu.png',  mem: '/work/proj/assets/fairygui/MainMenu/atlas@menu.png' },
        { url: 'gt-assets/textures/brick_diffuse.jpg',        mem: '/work/proj/assets/textures/brick_diffuse.jpg' },
        { url: 'gt-assets/textures/grasslight-big.jpg',       mem: '/work/proj/assets/textures/grasslight-big.jpg' },
        { url: 'gt-assets/textures/hardwood2_diffuse.jpg',    mem: '/work/proj/assets/textures/hardwood2_diffuse.jpg' },
        // 场景 JSON 里贴图是绝对路径（桌面遗留）——MEMFS 里镜像同一目录串，
        // 让 MaterialGallery 的 3 张贴图在 wasm 里也能命中
        { url: 'gt-assets/textures/brick_diffuse.jpg',     mem: '/D:/project/lang/SlangAllInOne/SLangCore/samples/GameTest/assets/textures/brick_diffuse.jpg' },
        { url: 'gt-assets/textures/grasslight-big.jpg',    mem: '/D:/project/lang/SlangAllInOne/SLangCore/samples/GameTest/assets/textures/grasslight-big.jpg' },
        { url: 'gt-assets/textures/hardwood2_diffuse.jpg', mem: '/D:/project/lang/SlangAllInOne/SLangCore/samples/GameTest/assets/textures/hardwood2_diffuse.jpg' }
      ],
      buttons: [
        { label: '1', key: 49 }, { label: '2', key: 50 }, { label: '3', key: 51 },
        { label: '4', key: 52 }, { label: '5', key: 53 },
        { label: 'M 菜单', key: 77 }, { label: 'G Gizmo', key: 71 }, { label: 'U UI', key: 85 }
      ]
    },
    rexamples: {
      title: 'RExamples',
      desc: '12 个 R 风格图表：plot/hist/barplot/boxplot/pie/par/legend/abline/lm/MathR',
      mode: 'gallery',
      rootModuleName: 'RExamplesWeb',
      renderWidth: 360,
      renderHeight: 240,
      depMods: DEP_BASE,
      buttons: []
    },
    statsgallery: {
      title: 'StatsGallery',
      desc: '16 视图图库：DrawCanvas 图元 + DrawChart 八接口 + StatsPlot 七类',
      mode: 'gallery',
      rootModuleName: 'StatsGalleryWeb',
      renderWidth: 360,
      renderHeight: 240,
      depMods: DEP_BASE,
      buttons: []
    },
    rdata: {
      title: 'RDataGallery',
      desc: 'Std.RData 五类结构 → RDataChart 六视图',
      mode: 'gallery',
      rootModuleName: 'RDataGalleryWeb',
      renderWidth: 360,
      renderHeight: 240,
      depMods: DEP_BASE,
      buttons: []
    }
  };

  // FairyGUI 命中测试会从引擎表坐标里减去桌面 QLabel 的 (10,10) 偏移，
  // 因此 JS 注入鼠标坐标时 +10 补偿（QTHost.sl 的 mouseLocalX/Y 同步抵消）。
  var MOUSE_OFFSET = 10;
  // wasm 产物（csimple_lang build 目标：引擎 C 库编进二进制）
  var WASM_SCRIPT = 'wasm/csimple_lang_game.js';

  var statusEl = document.getElementById('status');
  var canvas = document.getElementById('cv');

  function setStatus(text, isErr) {
    statusEl.textContent = text;
    statusEl.className = isErr ? 'err' : '';
  }
  function appendStatus(text) {
    statusEl.textContent = (statusEl.textContent + '\n' + text).slice(-800);
    statusEl.scrollTop = statusEl.scrollHeight;
  }

  // ── 主菜单（无 ?demo=）／演示页（有 ?demo=）────────────────────────
  var params = new URLSearchParams(location.search);
  var demoKey = params.get('demo');
  var DEMO = demoKey && DEMOS[demoKey] ? DEMOS[demoKey] : null;

  function buildHomeMenu() {
    var hm = document.getElementById('homeMenu');
    Object.keys(DEMOS).forEach(function (key, i) {
      var d = DEMOS[key];
      var b = document.createElement('button');
      b.className = 'mi';
      b.innerHTML = '<b>' + (i + 1) + '</b>' + d.title + '<small>' + d.desc + '</small>';
      b.onclick = function () { location.href = 'index.html?demo=' + key; };
      hm.appendChild(b);
    });
  }

  if (!DEMO) {
    document.getElementById('stage').style.display = 'none';
    document.getElementById('home').style.display = 'flex';
    buildHomeMenu();
    setStatus('select a sample');
    return; // 主菜单页不装载 wasm
  }
  // 演示页：隐藏主菜单、按 DEMO 配置画布
  document.getElementById('home').style.display = 'none';
  document.getElementById('stage').style.display = 'block';
  document.getElementById('lbl').textContent = '[' + DEMO.renderWidth + 'x' + DEMO.renderHeight + ']';
  canvas.width = DEMO.renderWidth;
  canvas.height = DEMO.renderHeight;
  document.getElementById('homeBtn').onclick = function () { location.href = 'index.html'; };

  // ── 顶部按钮菜单（最左 = 主菜单；其后为工程快捷按钮）────────────────
  var btnBox = document.getElementById('btns');
  if (DEMO.mode === 'scene') {
    // 分辨率下拉框（改 canvas 属性 → SL updateRenderTarget 自动 rs.resize）
    var sel = document.createElement('select');
    var RES = [['480,480', 'Default 480x480'], ['640,360', '640x360'], ['360,640', 'Phone 360x640'],
               ['390,844', 'iPhone 390x844'], ['768,1024', 'Tablet 768x1024'], ['1280,720', 'HD 1280x720']];
    RES.forEach(function (r) {
      var o = document.createElement('option');
      o.value = r[0]; o.textContent = r[1];
      sel.appendChild(o);
    });
    sel.onchange = function () {
      var p = sel.value.split(',');
      var w = parseInt(p[0], 10), h = parseInt(p[1], 10);
      canvas.width = w; canvas.height = h;
      document.getElementById('lbl').textContent = '[' + w + 'x' + h + ']';
    };
    btnBox.appendChild(sel);
  }
  DEMO.buttons.forEach(function (btn) {
    var b = document.createElement('button');
    b.textContent = btn.label;
    b.onclick = function () { sendTap(btn.key); };
    btnBox.appendChild(b);
  });
  if (DEMO.mode === 'gallery') {
    var prev = document.createElement('button');
    prev.textContent = '\u25C0 上一格';
    prev.onclick = function () { injectWheel(-1); };
    var next = document.createElement('button');
    next.textContent = '下一格 \u25B6';
    next.onclick = function () { injectWheel(1); };
    btnBox.appendChild(prev);
    btnBox.appendChild(next);
  }

  // ── Qt::Key 码表（引擎 InputSystem 常量：字母/数字 = ASCII，功能键 0x01000000+）──
  var QT_KEY = {
    ArrowUp: 16777235, ArrowDown: 16777237,
    ArrowLeft: 16777234, ArrowRight: 16777236,
    Space: 32, Enter: 16777220,
    KeyW: 87, KeyA: 65, KeyS: 83, KeyD: 68, KeyR: 82, KeyP: 80,
    KeyM: 77, KeyG: 71, KeyU: 85, KeyO: 79, KeyF: 70, Digit1: 49, Digit2: 50,
    Digit3: 51, Digit4: 52, Digit5: 53, Digit6: 54, Digit7: 55, Digit8: 56, Digit9: 57,
    Escape: 16777216, ControlLeft: 16777249, ControlRight: 16777249,
    F12: 16777334, Home: 16777232
  };

  // ── 输入注入（引擎 C 表；SL 层经 InputSystem/QTHost 门面查询）────────
  var mod = null;
  function sendKey(qtKey, down) {
    if (mod && mod._sle_input_set_key) {
      mod._sle_input_set_key(qtKey, down ? 1 : 0);
    }
  }
  // 顶部按钮 → 一次「按下沿 + 松开」（90ms 后松开，帧循环按按下沿去重）
  function sendTap(qtKey) {
    sendKey(qtKey, true);
    setTimeout(function () { sendKey(qtKey, false); }, 90);
  }
  // 图库切格：直接写滚轮累计（SL 主循环 wheel_take 读后清零）
  function injectWheel(delta) {
    if (mod && mod._sle_input_set_mouse_wheel) {
      mod._sle_input_set_mouse_wheel(delta);
    }
  }
  function sendMousePos(x, y) {
    if (mod && mod._sle_input_set_mouse_pos) {
      mod._sle_input_set_mouse_pos(x + MOUSE_OFFSET, y + MOUSE_OFFSET);
    }
  }
  function sendMouseButton(button, down) {
    if (mod && mod._sle_input_set_mouse_button) {
      mod._sle_input_set_mouse_button(button, down ? 1 : 0);
    }
  }

  function ensureAudioResume() {
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
    sendMousePos(Math.round((e.clientX - r.left) * canvas.width / r.width),
                 Math.round((e.clientY - r.top) * canvas.height / r.height));
  });
  canvas.addEventListener('mousedown', function (e) {
    ensureAudioResume();
    sendMouseButton(e.button === 2 ? 2 : 1, true);
    e.preventDefault();
  });
  window.addEventListener('mouseup', function (e) {
    sendMouseButton(e.button === 2 ? 2 : 1, false);
  });
  canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
  canvas.addEventListener('wheel', function (e) {
    injectWheel(e.deltaY > 0 ? 1 : -1);
    e.preventDefault();
  }, { passive: false });

  // ── 呈现路径（引擎像素 → 屏幕）：独立 WebGL2 program，全屏三角贴图 ──
  var gl = null;
  var presentTex = null;
  var presProg = null;
  var presBuf = null;
  var presAPos = 0;

  function initPresent() {
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

  // 引擎 C 侧每帧回调（sle_web_glue.c EM_JS 按 Module.__<name> 查找；契约名
  // 不可改）。关键：引擎 GLES 渲染与本呈现共享同一 WebGL2 context —— 每次
  // blit 前必须完整恢复呈现状态，否则 GL_INVALID_OPERATION + 黑屏。
  var blitFrames = 0;
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
    blitFrames++;
    return true;
  }
  setInterval(function () {
    var now = Date.now();
    if (!onBlit.t0) onBlit.t0 = now;
    var el = (now - onBlit.t0) / 1000;
    if (el > 0.5) {
      document.getElementById('fps').textContent = (blitFrames / el).toFixed(1) + ' fps';
      blitFrames = 0;
      onBlit.t0 = now;
    }
  }, 500);

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

  // MEMFS 同构布局：/work/out/export/<模块名>/ 与桌面 out/export 完全一致。
  function stageAssets(Module, mods) {
    var FS = Module.FS;
    FS.mkdirTree('/work/out/export/' + DEMO.rootModuleName);
    FS.writeFile('/work/out/export/' + DEMO.rootModuleName + '/' + DEMO.rootModuleName + '.module.slb', rootSlb);
    for (var i = 0; i < DEMO.depMods.length; i++) {
      var name = DEMO.depMods[i];
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
    // cwd 探测兜底：findProjectDir 先查 getCurrentDirectory()+"/assets/..."，
    // chdir 到工程目录；同时镜像一份到 /assets（cwd='/' 时也能命中）。
    if (DEMO.chdir) {
      try {
        FS.mkdirTree('/assets');
        ASSET_LIST.forEach(function (a) {
          if (a.mem.indexOf('/work/proj/') === 0 && a.mem.indexOf('/D:') !== 0) {
            var dst = '/assets' + a.mem.slice('/work/proj'.length);
            var pp = dst.split('/');
            pp.pop();
            FS.mkdirTree(pp.join('/'));
            try { FS.writeFile(dst, FS.readFile(a.mem)); } catch (e2) { /* ignore */ }
          }
        });
        FS.chdir(DEMO.chdir);
        appendStatus('[boot] cwd -> ' + DEMO.chdir);
      } catch (e) {
        appendStatus('[boot] chdir failed (assets fallback /assets): ' + e);
      }
    }
  }

  var rootSlb = null;
  var ASSET_LIST = DEMO.assets || [];
  var assetFiles = null;

  var loads = [fetchBin('mod/' + DEMO.rootModuleName + '.module.slb')];
  DEMO.depMods.forEach(function (name) {
    loads.push(fetchText('mod/' + name + '.module.json'));
    loads.push(fetchBin('mod/' + name + '.module.slb'));
  });
  ASSET_LIST.forEach(function (a) { loads.push(fetchBin(a.url)); });

  Promise.all(loads).then(function (res) {
    rootSlb = new Uint8Array(res[0]);
    var idx = 1;
    var mods = {};
    DEMO.depMods.forEach(function (name) {
      mods[name] = { json: res[idx], slb: new Uint8Array(res[idx + 1]) };
      idx += 2;
    });
    assetFiles = ASSET_LIST.map(function () { return new Uint8Array(res[idx++]); });

    var script = document.createElement('script');
    script.src = WASM_SCRIPT;
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
        // 平台桥回调契约名（sle_web_glue.c 固定查找，不可改）：
        //   __snakeOnBlit(ptr,w,h) / __snakeCanvasWidth/Height()
        Module.__snakeOnBlit = onBlit;
        Module.__snakeCanvasWidth = function () { return canvas.width; };
        Module.__snakeCanvasHeight = function () { return canvas.height; };
        if (!initPresent()) return;
        stageAssets(Module, mods);
        setStatus('运行中（16ms 泵帧；点击画布恢复声音）');
        try {
          Module.callMain(['run', '--no-banner',
            '/work/out/export/' + DEMO.rootModuleName + '/' + DEMO.rootModuleName + '.module.slb']);
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
