/*
 * server.js - GameTest wasm web 静态服务（零依赖）。
 *   node server.js [port]        (默认 8080)
 *
 * 路由职责：把"页面虚拟路径"映射到真实构建产物，重构建后无需拷贝：
 *   /wasm/csimple_lang_game.{js,wasm} -> csimple_lang/build/Wasm/bin/
 *       （game wasm 目标产物；直接服务构建树，重链接即生效）
 *   /mod/<Name>.module.{json,slb}     -> SlangAllInOne/out/export/<Name>/
 *       （4 个 GameTestWeb 主模块 + 7 个依赖模块，均取自 SL 编译导出树）
 *   /gt-assets/...                    -> GameTest/assets/（SceneDemo 场景/包/贴图）
 *   其余                              -> 本目录静态文件（index.html/app.js）
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_DIR = __dirname;
// web -> GameTest -> samples -> SLangCore -> SlangAllInOne
const AIO_ROOT = path.join(WEB_DIR, '..', '..', '..', '..');
const LANG_ROOT = path.join(AIO_ROOT, '..');                  // → 仓库根
const VM_BIN = path.join(LANG_ROOT, 'csimple_lang', 'build', 'Wasm', 'bin');
const EXPORT_ROOT = path.join(AIO_ROOT, 'out', 'export');
const GT_ASSETS = path.join(WEB_DIR, '..', 'assets');

const PORT = Number(process.argv[2]) || 8080;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.json': 'application/json; charset=utf-8',
  '.slb': 'application/octet-stream',
  '.css': 'text/css; charset=utf-8',
  '.wav': 'audio/wav',
  '.mp3': 'audio/mpeg',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.xml': 'application/xml',
  '.fui': 'application/octet-stream'
};

// 依赖模块白名单（与 app.js DEMOS[*].depMods 保持一致）
const DEP_MODS = ['Core', 'Std', 'Math', 'SLangImage', 'SLangRender', 'SLangAudio', 'SimGameEngine'];
// GameTest 4 个 wasm 主模块（与 app.js DEMOS[*].rootModuleName 一致）
const ROOT_MODULES = ['SceneDemoWeb', 'RExamplesWeb', 'StatsGalleryWeb', 'RDataGalleryWeb'];

function resolve(urlPath) {
  if (urlPath === '/' || urlPath === '/index.html') {
    return path.join(WEB_DIR, 'index.html');
  }
  if (urlPath === '/app.js') {
    return path.join(WEB_DIR, 'app.js');
  }
  // wasm 产物：直接服务构建树（重链接无需拷贝）
  if (urlPath.indexOf('/wasm/csimple_lang_game.') === 0) {
    return path.join(VM_BIN, path.basename(urlPath));
  }
  // 主模块 + 依赖模块：映射到 SL 导出树
  const modMatch = urlPath.match(/^\/mod\/(\w+)\.module\.(json|slb)$/);
  if (modMatch) {
    const name = modMatch[1];
    if (ROOT_MODULES.indexOf(name) >= 0 || DEP_MODS.indexOf(name) >= 0) {
      return path.join(EXPORT_ROOT, name, name + '.module.' + modMatch[2]);
    }
  }
  // GameTest 工程资源（场景 JSON / FairyGUI 包 / 贴图）
  const assetMatch = urlPath.match(/^\/gt-assets\/(.+)$/);
  if (assetMatch) {
    return path.join(GT_ASSETS, assetMatch[1]);
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
  console.log('GameTest wasm web: http://127.0.0.1:' + PORT + '/');
  console.log('wasm bin : ' + VM_BIN);
  console.log('export   : ' + EXPORT_ROOT);
  console.log('assets   : ' + GT_ASSETS);
});
