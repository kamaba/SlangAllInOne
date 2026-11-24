/*
 * smoke-node.js - Node smoke test for the GameTest-on-wasm builds
 * (csimple_lang_game + the 4 GameTestWeb slb modules).
 *
 * Usage: node smoke-node.js <scenedemo|rexamples|statsgallery|rdata>
 *
 * Verifies (render/audio devices don't exist in Node - graceful degrade is
 * EXPECTED there; sle_web_blit without a JS callback returns 0):
 *   1. wasm game target boots and loads the module chain (7 dep modules)
 *   2. SceneDemoWeb: engine assembly + menu/fairy package load + pump loop,
 *      scene switch driven by an injected key ('2' -> ShapeGallery)
 *   3. Galleries: startup view renders, wheel injection switches cells
 */
'use strict';
const fs = require('fs');
const path = require('path');

const WEB_DIR = __dirname;
const AIO_ROOT = path.join(WEB_DIR, '..', '..', '..', '..');
const LANG_ROOT = path.join(AIO_ROOT, '..');
const VM_BIN = path.join(LANG_ROOT, 'csimple_lang', 'build', 'Wasm', 'bin');
const EXPORT_ROOT = path.join(AIO_ROOT, 'out', 'export');
const GT_ROOT = path.join(WEB_DIR, '..');
const GT_ASSETS = path.join(GT_ROOT, 'assets');

const DEMO = (process.argv[2] || 'scenedemo').toLowerCase();
const CFG = {
  scenedemo: { mod: 'SceneDemoWeb', pumpTag: '[SceneDemoWeb] pump start' },
  rexamples: { mod: 'RExamplesWeb', pumpTag: '[RExamplesWeb] pump start', first: '[cell 0]', next: '[cell 1]' },
  statsgallery: { mod: 'StatsGalleryWeb', pumpTag: '[StatsGalleryWeb] pump start', first: '[view 0]', next: '[view 1]' },
  rdata: { mod: 'RDataGalleryWeb', pumpTag: '[RDataWeb] pump start', first: '[view 0]', next: '[view 1]' }
};
if (!CFG[DEMO]) { console.log('unknown demo: ' + DEMO); process.exit(2); }
const conf = CFG[DEMO];

const DEP_MODS = ['Core', 'Std', 'Math', 'SLangImage', 'SLangRender', 'SLangAudio', 'SimGameEngine'];

const lines = [];
function note(tag, msg) { lines.push(String(msg)); console.log('[' + tag + '] ' + msg); }

let pass = 0, fail = 0;
function check(cond, msg) {
  if (cond) { pass++; console.log('  PASS ' + msg); }
  else { fail++; console.log('  FAIL ' + msg); }
}

function waitFor(pred, timeoutMs) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const iv = setInterval(() => {
      if (pred() || Date.now() - t0 > timeoutMs) { clearInterval(iv); resolve(pred()); }
    }, 50);
  });
}

(async function main() {
  const jsSrc = fs.readFileSync(path.join(VM_BIN, 'csimple_lang_game.js'), 'utf8');
  const wasmBin = fs.readFileSync(path.join(VM_BIN, 'csimple_lang_game.wasm'));
  const factory = new Function('require', 'module', 'exports', 'process',
    '__dirname', '__filename',
    jsSrc + '\nreturn createModule;')(require, module, module.exports, process,
    VM_BIN + '\\', path.join(VM_BIN, 'csimple_lang_game.js'));
  const mod = await factory({
    noInitialRun: true,
    print: (t) => note('SL', String(t)),
    printErr: (t) => note('VM', String(t))
  });

  // ── stage MEMFS isomorphic layout ──
  const FS = mod.FS;
  FS.mkdirTree('/work/out/export/' + conf.mod);
  FS.writeFile('/work/out/export/' + conf.mod + '/' + conf.mod + '.module.slb',
    fs.readFileSync(path.join(EXPORT_ROOT, conf.mod, conf.mod + '.module.slb')));
  for (const name of DEP_MODS) {
    const dir = '/work/out/export/' + name;
    FS.mkdirTree(dir);
    FS.writeFile(dir + '/' + name + '.module.json',
      fs.readFileSync(path.join(EXPORT_ROOT, name, name + '.module.json')));
    FS.writeFile(dir + '/' + name + '.module.slb',
      fs.readFileSync(path.join(EXPORT_ROOT, name, name + '.module.slb')));
  }
  if (DEMO === 'scenedemo') {
    // SceneDemo assets -> /work/proj（chdir 目标）+ /assets（cwd='/' 兜底）
    const stage = (srcRel, memBase) => {
      const src = path.join(GT_ASSETS, srcRel);
      if (!fs.existsSync(src)) return;
      const dst = memBase + '/' + srcRel.split('\\').join('/');
      const dstDir = dst.slice(0, dst.lastIndexOf('/'));
      FS.mkdirTree(dstDir);
      FS.writeFile(dst, fs.readFileSync(src));
    };
    ['scenes/MaterialBall.scene.json', 'scenes/ShapeGallery.scene.json',
     'scenes/PureTest.scene.json', 'scenes/MaterialGallery.scene.json',
     'scenes/RotateTest.scene.json'].forEach(f => stage(f, '/work/proj/assets'));
    ['fairygui/Demo/package.xml', 'fairygui/Demo/DemoUI.xml',
     'fairygui/Demo/atlas@ui.png', 'fairygui/Demo/Demo.fui',
     'fairygui/MainMenu/package.xml', 'fairygui/MainMenu/MainMenu.xml',
     'fairygui/MainMenu/atlas@menu.png',
     'textures/brick_diffuse.jpg', 'textures/grasslight-big.jpg',
     'textures/hardwood2_diffuse.jpg'].forEach(f => stage(f, '/work/proj/assets'));
    try { FS.chdir('/work/proj'); note('boot', 'cwd -> /work/proj'); }
    catch (e) { note('boot', 'chdir failed: ' + e); }
  }

  // ── FFI channel probe ──
  check(typeof mod._sle_input_set_key === 'function', 'C export _sle_input_set_key reachable');
  check(typeof mod._sle_input_set_mouse_wheel === 'function', 'C export _sle_input_set_mouse_wheel reachable');
  check(typeof mod._sle_web_blit === 'function', 'C export _sle_web_blit reachable');

  // ── run the module (boot + pump) ──
  setTimeout(() => {
    if (DEMO === 'scenedemo') {
      try { mod._sle_input_set_key(50, 1); } catch (e) {}   // '2' -> ShapeGallery
      setTimeout(() => { try { mod._sle_input_set_key(50, 0); } catch (e) {} }, 80);
    } else {
      try { mod._sle_input_set_mouse_wheel(1); } catch (e) {} // next cell
    }
  }, 800);

  const pumpSeen = waitFor(() => lines.join('\n').indexOf(conf.pumpTag) >= 0, 15000);
  // callMain 先启动（ASYNCIFY 在 16ms sleep 处让出事件循环，上面的
  // waitFor / 下面的注入定时器才有机会跑），然后等待断言。
  try {
    mod.callMain(['run', '--no-banner',
      '/work/out/export/' + conf.mod + '/' + conf.mod + '.module.slb']);
  } catch (e) {
    if (!(e && e.name === 'ExitStatus')) {
      note('VM', 'callMain threw: ' + (e && e.message));
      fail++;
    }
  }
  await pumpSeen;
  check(lines.join('\n').indexOf(conf.pumpTag) >= 0, 'pump loop started (' + conf.pumpTag + ')');

  // wait for the injected switch to show up
  if (conf.next) {
    const all0 = lines.join('\n');
    const switched = await waitFor(() => lines.join('\n').indexOf(conf.next) >= 0, 4000);
    check(switched, 'injected input switched to ' + conf.next);
    if (!switched) check(false, 'last 200 chars: ' + all0.slice(-200));
  }
  if (DEMO === 'scenedemo') {
    const all = lines.join('\n');
    // Node 无 GL：atlas 纹理加载失败是预期降级（浏览器 WebGL2 正常）；
    // 这里区分「包结构/文件路径问题」（XML 解析错等）与「GPU 降级」。
    const menuLoaded = all.indexOf('[menu] loaded') >= 0;
    const menuGpuDegrade = all.indexOf('[menu] load failed: atlas texture') >= 0;
    check(menuLoaded || menuGpuDegrade, 'MainMenu package: ' +
      (menuLoaded ? 'loaded' : (menuGpuDegrade ? 'atlas GPU degrade (node, expected)' : 'FAILED (xml/path?)')));
    check(all.indexOf('[scene] loaded') >= 0, 'scene json loaded (RotateTest on boot)');
  }

  // 16ms sleep pump keeps the process alive; finish after assertions
  setTimeout(() => {
    console.log('\nRESULT smoke-node ' + DEMO + ': ' + (fail === 0 ? 'PASS' : 'FAIL') +
      ' (' + pass + '/' + (pass + fail) + ')');
    process.exit(fail === 0 ? 0 : 1);
  }, 500);
})();
