#!/usr/bin/env node
/**
 * admin-server.js — docs-web 后管平台服务（零依赖）
 *
 * 能力：
 *   1. 静态托管文档站（out/docs_web），/admin 为后管控制台；
 *   2. 版本管理（分组件：本体 / VSCode / 插件 / 包）——扫描真实锚点展示，支持逐组件改写：
 *      POST /api/version/set { key, value } → 写回对应锚点文件（version-scan.js）并记历史；
 *   3. 站点数据管理：GET/POST /api/site-data（site-data.jsonc 读取与保存）；
 *   4. 一键重建：POST /api/rebuild → 执行 build-docs-web.js 并回传日志尾。
 *
 * 用法：node tools/docs-web/admin-server.js [port]    # 默认 8932，仅监听本机
 * 官网部署时可仅托管静态产物；版本管理/重建 API 属本机后管能力。
 */
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { scanVersions, writeVersion } = require('./version-scan.js');

const PORT = parseInt(process.argv[2], 10) || 8932;
const HERE = __dirname;
const OUT_ROOT = path.resolve(HERE, '..', '..', 'out', 'docs_web');
const SITE_DATA = path.join(HERE, 'site-data.jsonc');
const HISTORY = path.join(HERE, 'version-history.json');
const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.jsonc': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}

/** jsonc 去注释（不伤 URL 中的 ://，也不伤字符串内的 //） */
function stripJsonc(s) {
  s = String(s).replace(/^﻿/, '');
  s = s.replace(/\/\*[\s\S]*?\*\//g, '');
  s = s.replace(/(^|[^:"'])\/\/[^\\\n]*/g, '$1');
  s = s.replace(/,(\s*[\]}])/g, '$1');
  return s;
}

function readBody(req, cap) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => { size += c.length; if (size > (cap || 2 * 1024 * 1024)) { reject(new Error('body too large')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function loadHistory() {
  try { return JSON.parse(fs.readFileSync(HISTORY, 'utf8')); } catch (e) { return []; }
}
function appendHistory(entry) {
  const list = loadHistory();
  list.unshift(entry);
  fs.writeFileSync(HISTORY, JSON.stringify(list.slice(0, 200), null, 1), 'utf8');
}

const server = http.createServer(async (req, res) => {
  const url = (req.url || '/').split('?')[0];
  try {
    if (url === '/api/versions' && req.method === 'GET') {
      return sendJson(res, 200, { ok: true, ...scanVersions(), history: loadHistory() });
    }
    if (url === '/api/version/set' && req.method === 'POST') {
      const body = JSON.parse(await readBody(req));
      const prev = scanVersions().groups.flatMap((g) => g.items).find((x) => x.key === body.key);
      const result = writeVersion(String(body.key || ''), String(body.value || ''));
      appendHistory({ at: new Date().toISOString(), key: result.key, from: prev ? prev.version : null, to: result.version, file: result.file });
      return sendJson(res, 200, { ok: true, ...result });
    }
    if (url === '/api/site-data' && req.method === 'GET') {
      return sendJson(res, 200, { ok: true, content: fs.readFileSync(SITE_DATA, 'utf8') });
    }
    if (url === '/api/site-data' && req.method === 'POST') {
      const content = await readBody(req, 512 * 1024);
      JSON.parse(stripJsonc(content)); // 保存前先校验（容忍 // 注释与尾逗号，且不伤 URL 的 ://）
      fs.writeFileSync(SITE_DATA, content, 'utf8');
      return sendJson(res, 200, { ok: true });
    }
    if (url === '/api/rebuild' && req.method === 'POST') {
      const r = spawnSync(process.execPath, [path.join(HERE, 'build-docs-web.js')], { encoding: 'utf8', timeout: 120000 });
      const tail = ((r.stdout || '') + (r.stderr || '')).split('\n').filter(Boolean).slice(-8).join('\n');
      return sendJson(res, 200, { ok: r.status === 0, tail });
    }
    if (url.startsWith('/api/')) return sendJson(res, 404, { ok: false, error: 'unknown api' });

    // 静态文件（/admin → admin.html）
    let urlPath = url === '/admin' ? '/admin.html' : url;
    if (urlPath.endsWith('/')) urlPath += 'index.html';
    urlPath = decodeURIComponent(urlPath);
    const file = path.normalize(path.join(OUT_ROOT, urlPath));
    if (!file.startsWith(OUT_ROOT)) { res.writeHead(403); res.end('forbidden'); return; }
    fs.readFile(file, (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end('<meta charset="utf-8"><body style="font-family:sans-serif;padding:40px"><h2>404</h2><p>' + urlPath + '</p><p><a href="/">返回文档首页</a> · <a href="/admin">后管控制台</a></p></body>');
        return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream' });
      res.end(data);
    });
  } catch (e) {
    sendJson(res, 400, { ok: false, error: String(e.message || e) });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('[docs-web admin] 控制台 http://127.0.0.1:' + PORT + '/admin  （站点同端口根路径，Ctrl+C 停止）');
});
