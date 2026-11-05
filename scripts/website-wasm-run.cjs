/*
 * website-wasm-run.cjs - run a compiled Playground module under the WEBSITE's
 * wasm VM (SLangOfficialWebsite/web/public/wasm assets), exactly like the
 * browser-side web/src/lib/wasmRunner.ts does:
 *   1. require() the Emscripten MODULARIZE factory (csimple_lang.js)
 *   2. stage the root module + Core/Std/Math deps into MEMFS
 *      (/work/out/playground/Playground + /work/out/export/<dep>)
 *   3. callMain(['run','--no-banner', <root>]), capture print/printErr
 *   4. print one JSON line: { "lines": [...], "err": [...], "exit": n }
 *
 * NOTE: csimple_lang.js must be required from a directory NOT under a
 * package.json with "type":"module" (web/ is) - the caller stages a copy.
 *
 * Usage: node website-wasm-run.cjs <module.slb|module.json> <wasmAssetDir>
 */
const fs = require('fs');
const path = require('path');

const modPath = process.argv[2];
const ASSET_BASE = process.argv[3];
const ROOT_DIR = '/work/out/playground/Playground';

async function main() {
  if (!modPath || !ASSET_BASE) {
    process.stdout.write(JSON.stringify({ lines: [], err: ['usage: node website-wasm-run.cjs <module> <assetDir>'], exit: -1 }));
    process.exit(1);
  }
  const createModule = require(path.join(ASSET_BASE, 'csimple_lang.js'));
  const deps = {};
  for (const d of ['Core', 'Std', 'Math']) {
    deps[d] = fs.readFileSync(path.join(ASSET_BASE, d + '.module.json'), 'utf8');
  }
  const rootBytes = fs.readFileSync(modPath);
  const rootName = path.basename(modPath);

  const lines = [];
  const err = [];
  const mod = await createModule({
    print: (t) => lines.push(t),
    printErr: (t) => err.push(t),
    noInitialRun: true,
  });
  const FS = mod.FS;
  FS.mkdirTree(ROOT_DIR);
  FS.mkdirTree('/work/out/export/Core');
  FS.mkdirTree('/work/out/export/Std');
  FS.mkdirTree('/work/out/export/Math');
  FS.writeFile(ROOT_DIR + '/' + rootName, rootBytes);
  FS.writeFile('/work/out/export/Core/Core.module.json', deps.Core);
  FS.writeFile('/work/out/export/Std/Std.module.json', deps.Std);
  FS.writeFile('/work/out/export/Math/Math.module.json', deps.Math);
  let exit = 0;
  try {
    mod.callMain(['run', '--no-banner', ROOT_DIR + '/' + rootName]);
  } catch (e) {
    exit = e && typeof e.status === 'number' ? e.status : -1;
  }
  process.stdout.write(JSON.stringify({ lines, err, exit }));
}
main().catch((e) => {
  process.stdout.write(JSON.stringify({ lines: [], err: [String((e && e.message) || e)], exit: -1 }));
  process.exit(1);
});
