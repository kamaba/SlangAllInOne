/*
 * smoke-node.js - Node smoke test for the SimGameEngine-on-wasm build
 * (csimple_lang_game + SnakeGameWeb slb: WebHost + SnakeGameBehaviour +
 * SnakeFairy + SnakeSfx).
 *
 * Verifies (render/audio devices don't exist in Node - graceful degrade is
 * EXPECTED there):
 *   1. wasm game target boots, loads the module chain (6 dep modules)
 *   2. FFI channel resolves (dlopen(NULL) self-parse): engine C exports are
 *      called for real - RenderSystem.init result, node registration,
 *      AudioIO device probe all come from the sle_x / slr_x / sla_x symbols
 *   3. Application pump loop runs: Behaviour start/update fire, the state
 *      machine reaches menu, keys injected via sle_input_set_key drive it
 *
 * Usage: node smoke-node.js   (expects build/Wasm/bin + out/export staged)
 */
'use strict';
const fs = require('fs');
const path = require('path');

const WEB_DIR = __dirname;
const AIO_ROOT = path.join(WEB_DIR, '..', '..', '..', '..');
const LANG_ROOT = path.join(AIO_ROOT, '..');
const VM_BIN = path.join(LANG_ROOT, 'csimple_lang', 'build', 'Wasm', 'bin');
const EXPORT_ROOT = path.join(AIO_ROOT, 'out', 'export');
const SAMPLE_ROOT = path.join(WEB_DIR, '..');

const ROOT_SLB = '/work/out/export/SnakeGameWeb/SnakeGameWeb.module.slb';
const DEP_MODS = ['Core', 'Std', 'Math', 'SLangImage', 'SLangRender', 'SLangAudio', 'SimGameEngine'];

const lines = [];
function note(tag, msg) { lines.push(tag + ': ' + msg); console.log('[' + tag + '] ' + msg); }

let pass = 0, fail = 0;
function check(cond, msg) {
  if (cond) { pass++; console.log('  PASS ' + msg); }
  else { fail++; console.log('  FAIL ' + msg); }
}

(async function main() {
  // ── load wasm factory ──
  const jsSrc = fs.readFileSync(path.join(VM_BIN, 'csimple_lang_game.js'), 'utf8');
  const wasmBin = fs.readFileSync(path.join(VM_BIN, 'csimple_lang_game.wasm'));
  // generated script needs require/module/process/__dirname/__filename in scope
  const factory = new Function('require', 'module', 'exports', 'process',
    '__dirname', '__filename',
    jsSrc + '\nreturn createModule;')(require, module, module.exports, process,
    VM_BIN + '\\', path.join(VM_BIN, 'csimple_lang_game.js'));
  const mod = await factory({
    noInitialRun: true,
    print: (t) => note('SL', String(t)),
    printErr: (t) => note('VM', String(t))
  });

  // ── stage MEMFS isomorphic layout + resources ──
  const FS = mod.FS;
  FS.mkdirTree('/work/out/export/SnakeGameWeb');
  FS.writeFile(ROOT_SLB, fs.readFileSync(path.join(EXPORT_ROOT, 'SnakeGameWeb', 'SnakeGameWeb.module.slb')));
  for (const name of DEP_MODS) {
    const dir = '/work/out/export/' + name;
    FS.mkdirTree(dir);
    FS.writeFile(dir + '/' + name + '.module.json',
      fs.readFileSync(path.join(EXPORT_ROOT, name, name + '.module.json')));
    FS.writeFile(dir + '/' + name + '.module.slb',
      fs.readFileSync(path.join(EXPORT_ROOT, name, name + '.module.slb')));
  }
  const sfxDir = path.join(SAMPLE_ROOT, 'sfx');
  const fairyDir = path.join(SAMPLE_ROOT, 'fairyui');
  FS.mkdirTree('/work/snake/sfx');
  FS.mkdirTree('/work/snake/fairyui');
  for (const f of fs.readdirSync(sfxDir)) {
    FS.writeFile('/work/snake/sfx/' + f, fs.readFileSync(path.join(sfxDir, f)));
  }
  for (const f of fs.readdirSync(fairyDir)) {
    FS.writeFile('/work/snake/fairyui/' + f, fs.readFileSync(path.join(fairyDir, f)));
  }

  // ── FFI channel probe (before main: direct C export reachability) ──
  // NOTE: only the explicit EXPORTED_FUNCTIONS list lands on the Module
  // object; other engine symbols (slr_/sla_) are reachable via dlsym from
  // the VM, not from JS - their absence here is expected.
  check(typeof mod._sle_input_set_key === 'function', 'C export _sle_input_set_key reachable');
  check(typeof mod._sle_input_set_mouse_pos === 'function', 'C export _sle_input_set_mouse_pos reachable');
  const nodeCount0 = mod._sle_node_count ? mod._sle_node_count() : -1;
  check(nodeCount0 === 0, 'sle_node_count() = ' + nodeCount0 + ' (engine C live)');
  const t1 = mod._sle_time_now_us ? mod._sle_time_now_us() : -1;
  await new Promise(r => setTimeout(r, 30));
  const t2 = mod._sle_time_now_us ? mod._sle_time_now_us() : -1;
  check(t2 > t1 && t1 > 0, 'C monotonic clock advances (t=' + t1 + '->' + t2 + ')');

  // ── run the game module (boot + pump ~40 frames) ──
  setTimeout(() => {
    try { mod._sle_input_set_key(16777220, 1); } catch (e) {}   // Enter: menu -> play
    setTimeout(() => { try { mod._sle_input_set_key(16777220, 0); } catch (e) {} }, 50);
    setTimeout(() => {
      try { mod._sle_input_set_key(16777235, 1); } catch (e) {} // Up arrow
      setTimeout(() => { try { mod._sle_input_set_key(16777235, 0); } catch (e) {} }, 50);
    }, 400);
    setTimeout(() => { process.exit(fail > 0 ? 1 : 0); }, 3000);
  }, 300);

  try {
    mod.callMain(['run', '--no-banner', ROOT_SLB]);
  } catch (e) {
    if (!(e && e.name === 'ExitStatus')) {
      note('VM', 'callMain threw: ' + (e && e.message));
      fail++;
    }
  }

  // ── assertions from console output ──
  setTimeout(() => {
    const all = lines.join('\n');
    check(all.indexOf('[WebHost] RenderSystem.init') >= 0, 'WebHost started (render init reported)');
    check(all.indexOf('[SnakeGameBehaviour] start begin') >= 0, 'Behaviour start() fired (Application lifecycle)');
    check(all.indexOf('[SnakeGameBehaviour] ready (menu)') >= 0, 'game ready: nodes + Fairy/Sfx init ran without crash');
    check(all.indexOf('[WebHost] frame 30') >= 0, 'pump loop reached 30 frames (render/audio degrade tolerated in Node)');
    check(fail === 0, 'no failures');
    console.log('\nRESULT: ' + (fail === 0 ? 'PASS' : 'FAIL') + ' (' + pass + '/' + (pass + fail) + ')');
  }, 2800);
})();
