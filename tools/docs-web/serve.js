#!/usr/bin/env node
/**
 * serve.js — docs-web 产物静态预览服务器（零依赖）
 * 用法：node tools/docs-web/serve.js [port] [root]
 *   默认 port 8931，root = <repo>/SlangAllInOne/out/docs_web
 * 仅监听本机回环地址，供本地预览 / 后管平台部署前自查；官网直接托管 out/docs_web 目录即可。
 */
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.argv[2], 10) || 8931;
const ROOT = path.resolve(process.argv[3] || path.join(__dirname, '..', '..', 'out', 'docs_web'));
const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8', '.txt': 'text/plain; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  if (urlPath.endsWith('/')) urlPath += 'index.html';
  const file = path.normalize(path.join(ROOT, urlPath));
  if (!file.startsWith(ROOT)) { res.writeHead(403); res.end('forbidden'); return; }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end('<meta charset="utf-8"><body style="font-family:sans-serif;padding:40px"><h2>404</h2><p>' +
        urlPath + '</p><p><a href="/">返回文档首页</a></p></body>');
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(PORT, '127.0.0.1', () => {
  console.log('[docs-web preview] http://127.0.0.1:' + PORT + '/  (root=' + ROOT + ', Ctrl+C 停止)');
});
