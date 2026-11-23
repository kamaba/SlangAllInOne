/*
 * server.js - zero-dependency static server for the SnakeGame web demo.
 *   node server.js [port]        (default 8093)
 *
 * Routes:
 *   /                      -> index.html (this dir)
 *   /game.js               -> game.js (this dir)
 *   /wasm/csimple_lang_async.{js,wasm}
 *                          -> csimple_lang/build/Wasm/bin/  (ASYNCIFY build)
 *   /mod/{Core,Std}.module.json
 *                          -> SlangAllInOne/out/export/{Core,Std}/
 *   /mod/SnakeGameWeb.module.slb
 *                          -> SlangAllInOne/out/export/SnakeGameWeb/
 *
 * The ASYNCIFY wasm is served from the vm build tree so a rebuild is picked
 * up without copying. The plain csimple_lang.{js,wasm} artifacts (website
 * runtime) are intentionally NOT routed.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_DIR = __dirname;
const AIO_ROOT = path.join(WEB_DIR, '..', '..', '..', '..');  // SlangAllInOne
const LANG_ROOT = path.join(AIO_ROOT, '..');                  // d:\project\lang
const VM_BIN = path.join(LANG_ROOT, 'csimple_lang', 'build', 'Wasm', 'bin');
const EXPORT_ROOT = path.join(AIO_ROOT, 'out', 'export');

const PORT = Number(process.argv[2]) || 8093;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.json': 'application/json; charset=utf-8',
  '.slb': 'application/octet-stream',
  '.css': 'text/css; charset=utf-8',
  '.wav': 'audio/wav',
  '.png': 'image/png',
  '.xml': 'application/xml'
};

const DEP_MODS = ['Core', 'Std', 'Math', 'SLangImage', 'SLangRender', 'SLangAudio', 'SimGameEngine'];
const SFX_DIR = path.join(WEB_DIR, '..', 'sfx');        // samples/SnakeGame/sfx
const FAIRY_DIR = path.join(WEB_DIR, '..', 'fairyui');  // samples/SnakeGame/fairyui

// route -> absolute file path
function resolve(urlPath) {
  if (urlPath === '/' || urlPath === '/index.html') {
    return path.join(WEB_DIR, 'index.html');
  }
  if (urlPath === '/game.js') {
    return path.join(WEB_DIR, 'game.js');
  }
  if (urlPath.indexOf('/wasm/csimple_lang_game.') === 0) {
    const name = path.basename(urlPath);
    return path.join(VM_BIN, name);
  }
  // legacy routes kept for the protocol-era demo smoke scripts
  if (urlPath.indexOf('/wasm/csimple_lang_async.') === 0) {
    const name = path.basename(urlPath);
    return path.join(VM_BIN, name);
  }
  if (urlPath === '/mod/SnakeGameWeb.module.slb') {
    return path.join(EXPORT_ROOT, 'SnakeGameWeb', 'SnakeGameWeb.module.slb');
  }
  const modMatch = urlPath.match(/^\/mod\/(\w+)\.module\.(json|slb)$/);
  if (modMatch && DEP_MODS.indexOf(modMatch[1]) >= 0) {
    return path.join(EXPORT_ROOT, modMatch[1],
                     modMatch[1] + '.module.' + modMatch[2]);
  }
  const sfxMatch = urlPath.match(/^\/sfx\/([\w.]+)$/);
  if (sfxMatch) {
    return path.join(SFX_DIR, sfxMatch[1]);
  }
  const fairyMatch = urlPath.match(/^\/fairyui\/([\w.]+)$/);
  if (fairyMatch) {
    return path.join(FAIRY_DIR, fairyMatch[1]);
  }
  return null;
}

const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  const file = resolve(urlPath);
  if (!file || !fs.existsSync(file)) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404: ' + urlPath);
    return;
  }
  res.writeHead(200, {
    'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
    'Cache-Control': 'no-store'
  });
  fs.createReadStream(file).pipe(res);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('SnakeGame web demo: http://127.0.0.1:' + PORT + '/');
  console.log('vm bin : ' + VM_BIN);
  console.log('export : ' + EXPORT_ROOT);
});
