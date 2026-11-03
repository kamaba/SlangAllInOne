#!/usr/bin/env node
/**
 * docs-web — Markdown 文档转静态网页 + API 索引生成器（自包含，零 npm 依赖）
 *
 * 用途（对应 md/project/docs-web.md）：
 *   1. 扫描 `md/lib`（可 --src 换源）下全部 .md，逐篇转成带样式/锚点/目录的网页；
 *   2. 解析「## class `X`」分节与「| 类型 | 签名 | 说明 |」成员表，抽取 类/枚举 × 字段/构造/方法/属性
 *      构建 API 索引：api/index.html（可搜索网页版）+ api/index.json（机器可读索引文件，
 *      官网/后管平台按此文件自动挂接 API 入口与页面）；
 *   3. 产出整站静态文件到 out/docs_web（可整体发布到任意静态服务器/官网目录）。
 *
 * 用法：
 *   node tools/docs-web/build-docs-web.js                     # 默认 md/lib → out/docs_web
 *   node tools/docs-web/build-docs-web.js --src md/lib --out out/docs_web
 *
 * 后管平台集成：定时/触发式调用本脚本 → 读取 api/index.json（分组/文档/类/成员结构化数据）
 *   → 在后管页面挂接「API 文档」入口，或直接静态托管 out/docs_web 目录。
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { scanVersions } = require('./version-scan.js');

/* ---------------------------------------------------------------- CLI */
function parseArgs(argv) {
  const args = { src: null, out: null, siteName: 'SLang 标准库文档', clean: true };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--src') args.src = next();
    else if (a === '--out') args.out = next();
    else if (a === '--site-name') args.siteName = next();
    else if (a === '--no-clean') args.clean = false;
    else if (a === '--help' || a === '-h') {
      console.log('用法: node build-docs-web.js [--src <md目录>] [--out <输出目录>] [--site-name <站点名>] [--no-clean]');
      process.exit(0);
    }
  }
  return args;
}

const ARGS = parseArgs(process.argv);
const HERE = __dirname;
const SRC_ROOT = path.resolve(ARGS.src || path.join(HERE, '..', '..', 'md', 'lib'));
const OUT_ROOT = path.resolve(ARGS.out || path.join(HERE, '..', '..', 'out', 'docs_web'));
const SITE_NAME = ARGS.siteName;
const REPO_ROOT = path.resolve(HERE, '..', '..', '..');
const SAMPLES_ROOT = path.join(REPO_ROOT, 'SlangAllInOne', 'SLangCore', 'samples');

/* ---------------------------------------------------------------- site-data（后管平台可编辑） */
/** 极简 jsonc 解析：去 // 与 /* *​/ 注释、尾逗号 */
function parseJsonc(text) {
  let s = String(text).replace(/^\uFEFF/, '');
  s = s.replace(/\/\*[\s\S]*?\*\//g, '');
  s = s.replace(/(^|[^:"'])\/\/[^\n]*/g, '$1');
  s = s.replace(/,(\s*[}\]])/g, '$1');
  return JSON.parse(s);
}

const SITE_DATA_DEFAULTS = {
  site: { name: SITE_NAME },
  // 自举说明：按用户要求先以 HTML 注释形态嵌入首页（不上屏；需要启用时改为字符串插值即可）
  bootstrapNote: '本站为 SLang 自举项目：门户 / 前端 / 后管均由 SLang 生态技术栈构建。',
  friendLinks: [
    { name: 'simple_language', url: 'https://github.com/kamaba/simple_language', desc: 'FrontEnd 编译器仓库（词法/语义/IR/SLIR）' },
    { name: 'SlangAllInOne', url: 'https://github.com/kamaba/SlangAllInOne', desc: '一体化工具链总仓库（本站文档真源）' },
    { name: 'Releases 下载', url: 'https://github.com/kamaba/SlangAllInOne/releases', desc: '双平台发布包（零依赖 Native AOT）' },
    { name: 'Visual Studio Code', url: 'https://code.visualstudio.com/', desc: 'SLang 语言支持插件的宿主编辑器' },
  ],
  community: {
    intro: 'SLang 是一门从零构建的静态类型语言：编译器前端（C#/.NET 8）把 .sl 源码编译为 SLIR 模块包，C99 虚拟机负责执行。社区围绕语言语法、标准库、虚拟机与工具链展开，欢迎通过代码仓库的 Issues / Discussions 参与共建。',
    repos: [
      { name: 'SlangAllInOne（总仓库）', url: 'https://github.com/kamaba/SlangAllInOne', stack: 'C#/.NET 8 + C99', desc: '统合宿主 slang + 标准库源码 + 测试用例集 + 用户文档 + 构建/发布脚本' },
      { name: 'simple_language（FrontEnd）', url: 'https://github.com/kamaba/simple_language', stack: 'C#/.NET 8', desc: '词法/结构解析、语义与类型系统、IR 生成、SLIR 导出、CLI' },
    ],
    copyright: '本项目源码以 Apache License 2.0 发布（仓库根 LICENSE 文件）。标准库中的 SLang.Mysql 模块静态链接 GPL-2.0 的 MySQL Connector/C，该模块不随官方发布包分发，使用时请自行遵循 GPL-2.0。',
    proposal: '功能 / 语法 / 标准库提案请走 GitHub Issues 提交 RFC：需包含「动机（解决什么问题）· 方案（语法/接口草案）· 兼容性影响 · 备选方案」四要素；重大语法变更会先经社区讨论再进入实施排期。',
    minutes: '版本节点与发布记要：正式发布见 GitHub Releases（每版双平台同发，附更新说明）；仓库内 `SlangAllInOne/PROJECTS.md` §7 保留逐次演进记录（含每版改动摘要），问题复盘见 `md/ai/troubleshooting/` 分片。',
    sponsor: '欢迎赞助支持项目的构建农场 / 测试设备 / 文档站点托管。赞助方式与赞助者名录（待补充）：请通过代码仓库 Issues 联系维护者。',
  },
};

function loadSiteData() {
  const file = path.join(HERE, 'site-data.jsonc');
  try {
    const data = parseJsonc(fs.readFileSync(file, 'utf8'));
    return {
      ...SITE_DATA_DEFAULTS,
      ...data,
      site: { ...SITE_DATA_DEFAULTS.site, ...(data.site || {}) },
      community: { ...SITE_DATA_DEFAULTS.community, ...(data.community || {}) },
      friendLinks: Array.isArray(data.friendLinks) ? data.friendLinks : SITE_DATA_DEFAULTS.friendLinks,
    };
  } catch (e) {
    console.warn('[docs-web] site-data.jsonc 读取失败，使用内置默认：' + e.message);
    return SITE_DATA_DEFAULTS;
  }
}

const SITE_DATA = loadSiteData();
let FOOTER_VERSIONS = ''; // main() 中由版本扫描填充（本体/VSCode 分行展示）
let ADMIN_VERSION_GROUPS = []; // main() 中填充（admin.html 静态只读回退）

/* ---------------------------------------------------------------- utils */
const toPosix = (p) => p.replace(/\\/g, '/');

function walkMd(dir, base) {
  base = base || dir;
  const out = [];
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return out; }
  for (const ent of entries) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) out.push(...walkMd(full, base));
    else if (ent.isFile() && /\.md$/i.test(ent.name)) out.push(toPosix(path.relative(base, full)));
  }
  return out.sort();
}

function readText(file) {
  let s = fs.readFileSync(file, 'utf8');
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1); // strip BOM
  return s;
}

/** HTML 转义；保留源文本中已有的 HTML 实体（lib 文档签名常含 &lt; &gt; 等） */
function esc(text) {
  return String(text)
    .replace(/&(?!(?:amp|lt|gt|quot|apos|nbsp|#\d+|#x[0-9a-fA-F]+);)/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
function unesc(text) {
  return String(text).replace(/&(amp|lt|gt|quot|apos|nbsp|#\d+|#x[0-9a-fA-F]+);/g, (m, n) => {
    if (n[0] === '#') {
      const code = n[1] === 'x' || n[1] === 'X' ? parseInt(n.slice(2), 16) : parseInt(n.slice(1), 10);
      return isNaN(code) ? m : String.fromCodePoint(code);
    }
    return ENTITIES[n] !== undefined ? ENTITIES[n] : m;
  });
}

/** 去除 inline markdown 标记 → 纯文本（供索引 JSON 用） */
function plainOf(text) {
  let s = String(text);
  s = s.replace(/`([^`]*)`/g, '$1');
  s = s.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1');
  s = s.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
  s = s.replace(/\*\*([^*]+)\*\*/g, '$1');
  s = s.replace(/\*([^*]+)\*/g, '$1');
  s = s.replace(/~~([^~]+)~~/g, '$1');
  s = unesc(s).replace(/\s+/g, ' ').trim();
  return s;
}

function trunc(s, n) {
  s = s || '';
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

function slugify(text) {
  const s = String(text).trim()
    .replace(/[\u0000-\u002f\u003a-\u0040\u005b-\u0060\u007b-\u007f]+/g, '-') // ascii 标点→-
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
  return s || 'sec';
}

function hrefFor(relFromPageRoot) { // relFromPageRoot: 相对站点根的 posix 路径
  return encodeURI(relFromPageRoot);
}

function copyFile(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

/* ---------------------------------------------------------------- markdown 块解析 */
/** 解析为块数组：h/code/table/quote/ul/ol/p/hr */
function parseBlocks(src) {
  const lines = src.replace(/\r\n?/g, '\n').split('\n');
  const blocks = [];
  let i = 0;
  const isBlank = (l) => !l || !l.trim();
  const isTableSep = (l) => /^\s*\|?\s*:?-{2,}[-\s:|]*\|?\s*$/.test(l || '') && (l || '').includes('-') && (l || '').includes('|');
  const hasPipe = (l) => (l || '').includes('|');

  while (i < lines.length) {
    const line = lines[i];
    if (isBlank(line)) { i++; continue; }

    // fenced code
    const fence = line.match(/^\s*(`{3,}|~{3,})\s*([\w+#.-]*)\s*$/);
    if (fence) {
      const marker = fence[1][0];
      const lang = fence[2] || '';
      i++;
      const buf = [];
      while (i < lines.length && !new RegExp('^\\s*' + marker + '{3,}\\s*$').test(lines[i])) buf.push(lines[i++]);
      i++; // skip closing
      blocks.push({ t: 'code', lang, code: buf.join('\n') });
      continue;
    }

    // heading
    const h = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/);
    if (h) { blocks.push({ t: 'h', lvl: h[1].length, text: h[2] }); i++; continue; }

    // hr
    if (/^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/.test(line)) { blocks.push({ t: 'hr' }); i++; continue; }

    // table
    if (hasPipe(line) && i + 1 < lines.length && isTableSep(lines[i + 1])) {
      const header = splitRow(line);
      i += 2;
      const rows = [];
      while (i < lines.length && hasPipe(lines[i]) && !isBlank(lines[i])) { rows.push(splitRow(lines[i])); i++; }
      blocks.push({ t: 'table', header, rows });
      continue;
    }

    // blockquote
    if (/^\s*>/.test(line)) {
      const buf = [];
      while (i < lines.length && (/^\s*>/.test(lines[i]) || (!isBlank(lines[i]) && buf.length && !isSpecialStart(lines[i])))) {
        buf.push(lines[i].replace(/^\s*>\s?/, ''));
        i++;
      }
      blocks.push({ t: 'quote', blocks: parseBlocks(buf.join('\n')) });
      continue;
    }

    // lists
    const li = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
    if (li) {
      const ordered = /\d/.test(li[2][0]);
      const items = [];
      let lastIndent = null;
      while (i < lines.length) {
        const m = lines[i].match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
        if (m) {
          const depth = Math.floor(m[1].replace(/\t/g, '  ').length / 2);
          items.push({ depth, text: m[3] });
          lastIndent = m[1].length;
          i++;
        } else if (!isBlank(lines[i]) && lastIndent !== null && /^\s{1,}\S/.test(lines[i]) && !isSpecialStart(lines[i])) {
          items[items.length - 1].text += ' ' + lines[i].trim();
          i++;
        } else break;
      }
      blocks.push({ t: ordered ? 'ol' : 'ul', items });
      continue;
    }

    // paragraph
    const buf = [line];
    i++;
    while (i < lines.length && !isBlank(lines[i]) && !isSpecialStart(lines[i])) buf.push(lines[i++]);
    blocks.push({ t: 'p', text: buf.join(' ') });
  }
  return blocks;
}

function isSpecialStart(line) {
  return /^\s*(?:#{1,6}\s|>|`{3,}|~{3,}|(?:[-*+]|\d+[.)])\s)/.test(line) ||
    (/^\s*\|/.test(line) && line.includes('|'));
}

function splitRow(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|') && !s.endsWith('\\|')) s = s.slice(0, -1);
  return s.split(/(?<!\\)\|/g).map((c) => c.replace(/\\\|/g, '|').trim());
}

/* ---------------------------------------------------------------- inline 渲染 */
/**
 * ctx: {
 *   srcRel    当前 md 相对 src 根（posix），用于解析相对链接
 *   docMap    { 'lib/Core/String.md' → outRel 'lib/Core/String.html' }
 *   relRoot   当前页到站点根前缀（'../'…）
 * }
 */
function renderInline(text, ctx) {
  let out = '';
  let plain = '';
  let i = 0;
  const flush = () => { if (plain) { out += esc(plain); plain = ''; } };
  const n = text.length;

  while (i < n) {
    const ch = text[i];

    // inline code
    if (ch === '`') {
      const end = text.indexOf('`', i + 1);
      if (end > i) {
        flush();
        out += '<code>' + esc(text.slice(i + 1, end)) + '</code>';
        i = end + 1;
        continue;
      }
    }

    // image ![alt](src) → alt 链接占位
    if (ch === '!' && text[i + 1] === '[') {
      const m = /^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/.exec(text.slice(i));
      if (m) {
        flush();
        out += '<span class="img-alt">🖼 ' + esc(m[1] || 'image') + '</span>';
        i += m[0].length;
        continue;
      }
    }

    // link [text](href)
    if (ch === '[') {
      const m = /^\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/.exec(text.slice(i));
      if (m) {
        flush();
        const link = resolveLink(m[2], ctx);
        out += '<a href="' + esc(link.href) + '"' + (link.cls ? ' class="' + link.cls + '"' : '') +
          (link.external ? ' target="_blank" rel="noopener"' : '') + '>' +
          renderInline(m[1], ctx) + '</a>';
        i += m[0].length;
        continue;
      }
    }

    // bold
    if (text.startsWith('**', i)) {
      const end = text.indexOf('**', i + 2);
      if (end > 0) {
        flush();
        out += '<strong>' + renderInline(text.slice(i + 2, end), ctx) + '</strong>';
        i = end + 2;
        continue;
      }
    }

    // italic（避免吞掉 ** 与 CJK 下划线场景：仅单星前后非空白）
    if (ch === '*' && text[i + 1] !== '*' && /\S/.test(text[i + 1] || '')) {
      const end = text.indexOf('*', i + 1);
      if (end > i) {
        flush();
        out += '<em>' + renderInline(text.slice(i + 1, end), ctx) + '</em>';
        i = end + 1;
        continue;
      }
    }

    // strikethrough
    if (text.startsWith('~~', i)) {
      const end = text.indexOf('~~', i + 2);
      if (end > 0) {
        flush();
        out += '<del>' + renderInline(text.slice(i + 2, end), ctx) + '</del>';
        i = end + 2;
        continue;
      }
    }

    plain += ch;
    i++;
  }
  flush();
  return out;
}

function resolveLink(href, ctx) {
  const h = href.trim();
  if (/^(https?:)?\/\//i.test(h)) return { href: h, external: true };
  if (h.startsWith('#')) return { href: h };
  if (/\.md$/i.test(h) || /\.md#/i.test(h)) {
    const hashIdx = h.indexOf('#');
    const file = h.slice(0, hashIdx >= 0 ? hashIdx : undefined);
    const hash = hashIdx >= 0 ? h.slice(hashIdx) : '';
    const target = toPosix(path.posix.normalize(path.posix.join(path.posix.dirname(ctx.srcRel), file)));
    const outRel = ctx.docMap[target];
    if (outRel) return { href: encodeURI(ctx.relRoot + outRel) + hash };
    return { href: encodeURI(h), cls: 'md-missing', external: false }; // 站外 md：保留原样
  }
  return { href: h };
}

/* ---------------------------------------------------------------- 代码高亮（轻量） */
const KW_C = new Set(('if else for while do return ret new class function import await spawn global const enum interface ' +
  'extend template this base try catch throw true false null static get set public private protected override yield next ' +
  'in as ref out params abstract sealed virtual event namespace using var bool string int long short byte char double float ' +
  'void object decimal switch case break continue goto label lock readonly const let is typeof sizeof').split(/\s+/));
const KW_SL = new Set(('Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64 Float8 Float8_E5M2 Float16 Float16_Brain Float32 ' +
  'Float64 Num Bool String Object ByteBuffer Task Coroutine Map List HasSet Queue Stack Tree Table LinkedList Tuple Range ' +
  'Result Data Action Func Predicate').split(/\s+/));

function hlSegments(code, re, classify) {
  let out = '';
  let last = 0;
  let m;
  re.lastIndex = 0;
  while ((m = re.exec(code)) !== null) {
    if (m.index > last) out += esc(code.slice(last, m.index));
    const cls = classify(m);
    out += cls ? '<span class="' + cls + '">' + esc(m[0]) + '</span>' : esc(m[0]);
    last = m.index + m[0].length;
    if (m[0].length === 0) re.lastIndex++;
  }
  if (last < code.length) out += esc(code.slice(last));
  return out;
}

function highlightCode(code, lang) {
  const l = (lang || '').toLowerCase();
  if (l === 'json' || l === 'jsonc') {
    const re = /(\/\/[^\n]*|\/\*[\s\S]*?\*\/)|("(?:[^"\\\n]|\\.)*")(\s*:)?|\b(true|false|null)\b|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/g;
    return hlSegments(code, re, (m) => {
      if (m[1]) return 'tok-com';
      if (m[2]) return m[3] ? 'tok-key' : 'tok-str';
      if (m[4]) return 'tok-kw';
      return 'tok-num';
    });
  }
  if (['bash', 'sh', 'shell', 'powershell', 'ps1', 'cmd', 'bat'].includes(l)) {
    return hlSegments(code, /(^|\s)(#[^\n]*)|("(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')|(\$[A-Za-z_]\w*|-{1,2}[A-Za-z][\w-]*)/gm, (m) => {
      if (m[2]) return 'tok-com';
      if (m[3]) return 'tok-str';
      return 'tok-kw';
    });
  }
  // c-like 默认（sl / csharp / c / cpp / java / 无语言）
  const re = /(\/\*[\s\S]*?\*\/|\/\/[^\n]*|#[^\n]*)|("(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')|\b(\d+(?:\.\d+)?[fFdDmM]?)\b|\b([A-Za-z_]\w*)\b/g;
  return hlSegments(code, re, (m) => {
    if (m[1]) return 'tok-com';
    if (m[2]) return 'tok-str';
    if (m[3]) return 'tok-num';
    const w = m[4];
    if (KW_C.has(w)) return 'tok-kw';
    if (KW_SL.has(w)) return 'tok-type';
    if (/^[A-Z]/.test(w)) return 'tok-type';
    return null;
  });
}

/* ---------------------------------------------------------------- 文档模型 */
const KIND_STYLE = { '字段': 'k-field', '构造': 'k-ctor', '方法': 'k-method', '属性': 'k-prop' };
const CLS_KIND_RE = /^(class|enum|struct|interface)\s+(.+)$/;

function buildDoc(srcRel, docMap) {
  const full = path.join(SRC_ROOT, srcRel.replace(/\//g, path.sep));
  const blocks = parseBlocks(readText(full));
  const doc = {
    srcRel,
    outRel: srcRel.replace(/\.md$/i, '.html'),
    group: path.posix.dirname(srcRel) === '.' ? '' : path.posix.dirname(srcRel).split('/')[0],
    subPath: path.posix.dirname(srcRel) === '.' ? '' : path.posix.dirname(srcRel),
    title: '',
    type: 'guide',
    classes: [],
    headings: [],
  };

  const slugCount = {};
  const uniqueSlug = (base) => {
    const c = (slugCount[base] = (slugCount[base] || 0) + 1);
    return c === 1 ? base : base + '-' + c;
  };

  // H1 → 标题；后续降级
  const body = [];
  let h1Seen = false;
  let curClass = null;

  for (const b of blocks) {
    if (b.t === 'h' && b.lvl === 1 && !h1Seen) {
      h1Seen = true;
      doc.title = plainOf(b.text);
      continue;
    }
    body.push(b);

    if (b.t === 'h') {
      const lvl = Math.min(b.lvl, h1Seen && b.lvl === 1 ? 2 : b.lvl);
      const cm = CLS_KIND_RE.exec(plainOf(b.text));
      let anchor, isClass = false;
      let text = b.text;
      if (lvl === 2 && cm) {
        isClass = true;
        const name = cm[2].replace(/`/g, '').trim().split(/\s+/)[0];
        anchor = 'cls-' + name;
        text = cm[1] + ' <code>' + name + '</code>';
        curClass = {
          name,
          kind: cm[1],
          group: doc.group,
          module: doc.title || path.posix.basename(srcRel, '.md'),
          file: 'md/lib/' + srcRel,
          page: doc.outRel,
          anchor,
          summary: '',
          members: [],
        };
        doc.classes.push(curClass);
      } else {
        anchor = uniqueSlug(slugify(plainOf(b.text)));
        curClass = null;
      }
      b._render = { lvl, text, anchor, isClass };
      doc.headings.push({ lvl, text: isClass ? curClass.name : plainOf(b.text), anchor, isClass });
    } else if (b.t === 'table' && curClass) {
      const hh = b.header.map(plainOf);
      if (hh[0] === '类型' && hh[1] === '签名') {
        b._apiTable = true;
        for (const row of b.rows) {
          const kind = plainOf(row[0] || '');
          const sigRaw = row[1] || '';
          const descRaw = row[2] || '';
          if (!kind || !sigRaw) continue;
          const sig = plainOf(sigRaw);
          curClass.members.push({
            kind,
            name: memberNameOf(kind, sig),
            signature: sig,
            desc: trunc(unesc(plainOf(descRaw)), 300),
          });
        }
      }
    } else if (curClass && !curClass.summary && (b.t === 'ul' || b.t === 'p')) {
      if (b.t === 'ul') {
        for (const it of b.items) {
          const m = /^\*\*说明\*\*[：:]\s*(.*)$/.exec(it.text);
          if (m) { curClass.summary = trunc(plainOf(m[1]), 300); it._consumed = true; break; }
        }
      } else if (b.t === 'p') {
        curClass.summary = trunc(plainOf(b.text), 300);
        b._consumed = true;
      }
    }
  }

  doc.blocks = body;
  doc.type = doc.classes.length ? 'api' : (doc.title.includes('索引') ? 'index' : 'guide');
  return doc;
}

function memberNameOf(kind, sig) {
  const paren = sig.indexOf('(');
  if (kind === '字段') {
    let lhs = (paren >= 0 ? sig.slice(0, paren) : sig.split('=')[0]).trim();
    lhs = lhs.replace(/^(public|private|protected|internal|static|const|readonly)\s+/g, '');
    const toks = lhs.split(/\s+/).filter(Boolean);
    return toks.length ? toks[toks.length - 1] : sig;
  }
  if (paren < 0) return sig.trim();
  let head = sig.slice(0, paren).trim();
  if (kind === '属性') head = head.replace(/^(get|set)\s+/i, '');
  const toks = head.split(/\s+/).filter(Boolean);
  return toks.length ? toks[toks.length - 1] : head;
}

/* ---------------------------------------------------------------- HTML 组装 */
function pageShell(o) {
  return '<!DOCTYPE html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
    '<title>' + esc(o.title) + ' · ' + esc(SITE_NAME) + '</title>\n' +
    '<link rel="stylesheet" href="' + o.relRoot + 'assets/style.css">\n' +
    '</head>\n<body>\n' +
    '<header class="topbar"><div class="wrap topbar-in">' +
    '<a class="brand" href="' + o.relRoot + 'index.html"><span class="brand-dot"></span>' + esc(SITE_NAME) + '</a>' +
    '<nav class="topnav">' +
    '<a href="' + o.relRoot + 'index.html">首页</a>' +
    '<a href="' + o.relRoot + 'getting-started.html">入门</a>' +
    '<a href="' + o.relRoot + 'examples.html">示例</a>' +
    '<a href="' + o.relRoot + 'api/index.html" class="nav-api">API 索引</a>' +
    '<a href="' + o.relRoot + 'index.html#groups">库目录</a>' +
    '<a href="' + o.relRoot + 'about.html">关于</a>' +
    '<a href="' + o.relRoot + 'admin.html">后管</a>' +
    '</nav>' +
    '<span class="gen-at">' + esc(o.genAt || '') + '</span>' +
    '</div></header>\n' + o.body + '\n' +
    '<footer class="footer"><div class="wrap">由 <code>tools/docs-web</code> 自动生成 · 源：' +
    '<code>' + esc(o.sourcePath || 'md/lib') + '</code> · ' + esc(FOOTER_VERSIONS) + ' · ' + esc(o.genAt || '') + '</div></footer>\n' +
    '</body>\n</html>\n';
}

function breadcrumb(doc, relRoot) {
  const parts = ['<a href="' + relRoot + 'index.html">首页</a>'];
  if (doc.group) parts.push('<a href="' + relRoot + 'index.html#groups">' + esc(doc.group) + '</a>');
  parts.push('<span>' + esc(doc.title) + '</span>');
  return '<nav class="crumb wrap">' + parts.join(' <span class="sep">›</span> ') + '</nav>';
}

function renderDocPage(doc) {
  const ctx = { srcRel: doc.srcRel, docMap: DOC_MAP, relRoot: '../'.repeat(doc.outRel.split('/').length - 1) };
  const html = [];
  html.push(breadcrumb(doc, ctx.relRoot));
  html.push('<main class="wrap layout">');
  html.push('<article class="doc">');
  html.push('<h1 class="doc-title">' + esc(doc.title) + '</h1>');
  html.push('<div class="doc-meta"><span class="chip chip-group">' + esc(doc.group || '根目录') + '</span>' +
    '<code class="chip-src">md/lib/' + esc(doc.srcRel) + '</code></div>');
  if (doc.classes.length) {
    html.push('<div class="api-entry"><span class="api-entry-label">API</span>' +
      doc.classes.map((c) => '<a class="cls-chip k-' + esc(c.kind) + '" href="#' + esc(c.anchor) + '">' +
        esc(c.name) + '<em>' + c.members.length + '</em></a>').join('') + '</div>');
  }

  // TOC
  const toc = doc.headings.filter((h) => h.lvl <= 3);
  let tocHtml = '';
  if (toc.length) {
    tocHtml = '<aside class="toc"><div class="toc-title">本页目录</div><ul>' +
      toc.map((h) => '<li class="lv' + h.lvl + (h.isClass ? ' is-cls' : '') + '"><a href="#' + esc(h.anchor) + '">' +
        esc(h.text) + '</a></li>').join('') + '</ul></aside>';
  }

  // 正文块
  for (const b of doc.blocks) html.push(renderBlock(b, ctx));

  html.push('</article>');
  html.push(tocHtml);
  html.push('</main>');
  return pageShell({ title: doc.title, relRoot: ctx.relRoot, body: html.join('\n'), genAt: GEN_AT, sourcePath: 'md/lib/' + doc.srcRel });
}

function renderBlock(b, ctx) {
  switch (b.t) {
    case 'h': {
      const r = b._render || { lvl: b.lvl, text: esc(b.text), anchor: slugify(plainOf(b.text)), isClass: false };
      if (r.isClass) {
        const cls = DOC_CLASSES_BY_ANCHOR[ctx.srcRel + '#' + r.anchor];
        return '<h' + r.lvl + ' id="' + esc(r.anchor) + '" class="cls-heading">' +
          '<span class="cls-kind">' + esc(cls ? cls.kind : '') + '</span><code class="cls-name">' + esc(cls ? cls.name : plainOf(b.text)) + '</code>' +
          '<a class="anchor-link" href="#' + esc(r.anchor) + '">#</a></h' + r.lvl + '>' +
          (cls && cls.summary ? '<p class="cls-summary">' + esc(cls.summary) + '</p>' : '');
      }
      return '<h' + r.lvl + ' id="' + esc(r.anchor) + '">' + renderInline(b.text, ctx) +
        '<a class="anchor-link" href="#' + esc(r.anchor) + '">#</a></h' + r.lvl + '>';
    }
    case 'code':
      return '<figure class="code"><figcaption>' + esc(b.lang || 'text') + '</figcaption><pre><code>' +
        highlightCode(b.code, b.lang) + '</code></pre></figure>';
    case 'table': {
      const isApi = b._apiTable;
      let s = '<div class="table-scroll"><table class="' + (isApi ? 'api-table' : 'md-table') + '">';
      s += '<thead><tr>' + b.header.map((c) => '<th>' + renderInline(c, ctx) + '</th>').join('') + '</tr></thead><tbody>';
      for (const row of b.rows) {
        s += '<tr>';
        for (let ci = 0; ci < b.header.length; ci++) {
          const cell = row[ci] || '';
          if (isApi && ci === 0) {
            const k = plainOf(cell);
            s += '<td><span class="kind-badge ' + (KIND_STYLE[k] || '') + '">' + esc(k) + '</span></td>';
          } else s += '<td>' + renderInline(cell, ctx) + '</td>';
        }
        s += '</tr>';
      }
      return s + '</tbody></table></div>';
    }
    case 'quote':
      return '<blockquote>' + b.blocks.map((x) => renderBlock(x, ctx)).join('') + '</blockquote>';
    case 'ul':
    case 'ol': {
      if (b.items && b.items.length && b.items.every((it) => it._consumed)) return '';
      const tag = b.t === 'ul' ? 'ul' : 'ol';
      let s = '<' + tag + ' class="md-list">';
      let curDepth = 0;
      for (const it of b.items) {
        if (it._consumed) continue;
        if (it.depth > curDepth) s += '<' + tag + '>';
        else if (it.depth < curDepth) s += '</' + tag + '></li>';
        else if (s !== '<' + tag + ' class="md-list">') s += '</li>';
        curDepth = it.depth;
        s += '<li>' + renderInline(it.text, ctx);
      }
      s += '</li></' + tag + '>';
      for (let d = curDepth; d > 0; d--) s += '</' + tag + '></li>';
      return s;
    }
    case 'hr':
      return '<hr>';
    default:
      return '<p>' + renderInline(b.text, ctx) + '</p>';
  }
}

/* ---------------------------------------------------------------- 索引 JSON */
function buildIndexJson(groups, docs) {
  const classes = [];
  for (const d of docs) for (const c of d.classes) classes.push(c);
  classes.sort((a, b) => a.group.localeCompare(b.group) || a.module.localeCompare(b.module) || a.name.localeCompare(b.name));
  const members = classes.reduce((n, c) => n + c.members.length, 0);
  return {
    generator: 'docs-web',
    generatorVersion: '1.0.0',
    generatedAt: GEN_AT_ISO,
    source: toPosix(path.relative(path.join(HERE, '..', '..'), SRC_ROOT)),
    site: { name: SITE_NAME, entry: 'index.html', apiIndex: 'api/index.html', indexFile: 'api/index.json' },
    stats: { docs: docs.length, groups: groups.length, classes: classes.length, members },
    groups,
    docs: docs.map((d) => ({
      file: 'md/lib/' + d.srcRel,
      page: d.outRel,
      group: d.group,
      title: d.title,
      type: d.type,
      classes: d.classes.map((c) => c.name),
      headings: d.headings.map((h) => ({ lvl: h.lvl, text: h.text, anchor: h.anchor })),
    })),
    classes: classes.map((c) => ({
      name: c.name,
      kind: c.kind,
      group: c.group,
      module: c.module,
      file: c.file,
      page: c.page,
      anchor: c.anchor,
      summary: c.summary,
      members: c.members,
    })),
  };
}

/* ---------------------------------------------------------------- 首页 */
function renderHome(groups, docs, stats) {
  const groupOf = (d) => d.group;
  const cards = [];
  for (const g of groups) {
    const gdocs = docs.filter((d) => groupOf(d) === g.name);
    const readme = gdocs.find((d) => /(^|\/)README\.md$/i.test(d.srcRel));
    const apiDocs = gdocs.filter((d) => d.type === 'api').length;
    const items = gdocs.map((d) => {
      const clsN = d.classes.length;
      return '<li><a href="' + hrefFor(d.outRel) + '">' + esc(d.title) + '</a>' +
        (clsN ? '<span class="mini-chip">' + clsN + ' 类</span>' : '') + '</li>';
    }).join('');
    cards.push('<section class="group-card" id="g-' + esc(g.name || 'root') + '">' +
      '<header><h3><a href="' + (readme ? hrefFor(readme.outRel) : '#groups') + '">' + esc(g.label) + '</a></h3>' +
      '<span class="g-stats">' + gdocs.length + ' 篇 · ' + apiDocs + ' API</span></header>' +
      '<ul class="doc-list">' + items + '</ul></section>');
  }

  const body = '<main class="wrap">' +
    '<section class="hero">' +
    '<!-- ' + esc(SITE_DATA.bootstrapNote) + ' -->' +
    '<h1>' + esc(SITE_NAME) + '</h1>' +
    '<p class="hero-sub">由 <code>md/lib</code> 自动生成的在线文档 · 类与方法 API 索引 · 所有代码示例均可编译运行</p>' +
    '<div class="stat-row">' +
    '<div class="stat"><b>' + stats.docs + '</b><span>文档</span></div>' +
    '<div class="stat"><b>' + stats.classes + '</b><span>类 / 枚举</span></div>' +
    '<div class="stat"><b>' + stats.members + '</b><span>成员（字段·构造·方法·属性）</span></div>' +
    '</div>' +
    '<div class="cta-row">' +
    '<a class="btn btn-primary" href="' + hrefFor('getting-started.html') + '">🚀 入门</a>' +
    '<a class="btn" href="' + hrefFor('examples.html') + '">📦 示例库（10 例实测）</a>' +
    '<a class="btn" href="' + hrefFor('api/index.html') + '">🔍 API 索引（按类浏览 / 搜索）</a>' +
    '<a class="btn" href="' + hrefFor('about.html') + '">关于 · 社区资讯</a>' +
    '<a class="btn" href="' + hrefFor('api/index.json') + '">索引文件 index.json（后管平台消费）</a>' +
    '</div></section>' +
    '<section id="groups"><h2 class="sec-title">库目录</h2><div class="group-grid">' + cards.join('') + '</div></section>' +
    '<section class="note-card"><h3>后管平台自动生成</h3>' +
    '<p>后管平台定时/触发执行 <code>node tools/docs-web/build-docs-web.js</code> 即可全量重建本站；' +
    '结构化索引写入 <code>api/index.json</code>（分组 → 文档 → 类 → 成员），后管按该索引文件挂接 API 入口后即可在官网查看具体类与方法。</p></section>' +
    '</main>';
  return pageShell({ title: '首页', relRoot: '', body, genAt: GEN_AT, sourcePath: 'md/lib' });
}

/* ---------------------------------------------------------------- API 索引页 */
function renderApiPage(groups, classes) {
  const payload = {
    groups: groups.map((g) => ({ name: g.name, label: g.label })),
    classes: classes.map((c) => ({
      n: c.name, k: c.kind, g: c.group, m: c.module,
      p: c.page, a: c.anchor, s: trunc(c.summary, 160), mc: c.members.length,
      ms: c.members.map((x) => [x.kind, x.name, trunc(x.signature, 140), trunc(x.desc, 100)]),
    })),
  };
  const groupChips = groups.map((g) =>
    '<button class="g-chip" data-g="' + esc(g.name) + '">' + esc(g.label) + ' <em>' + g.clsCount + '</em></button>').join('');

  const body = '<main class="wrap api-page">' +
    '<h1 class="doc-title">API 索引</h1>' +
    '<p class="hero-sub">全部 ' + classes.length + ' 个类 / 枚举 · 点击类名跳转详情页 · 数据同源 <code>api/index.json</code></p>' +
    '<div class="api-toolbar">' +
    '<input id="api-q" type="search" placeholder="搜索类名 / 方法 / 签名 / 说明…" autofocus>' +
    '<select id="api-g"><option value="">全部分组</option>' +
    groups.map((g) => '<option value="' + esc(g.name) + '">' + esc(g.label) + '</option>').join('') +
    '</select></div>' +
    '<div class="api-kinds" id="api-kinds">' +
    ['字段', '构造', '方法', '属性'].map((k) =>
      '<label class="kind-toggle"><input type="checkbox" checked value="' + k + '"><span class="kind-badge ' + KIND_STYLE[k] + '">' + k + '</span></label>').join('') +
    '<span id="api-stat" class="api-stat"></span></div>' +
    '<div class="g-chips">' + groupChips + '</div>' +
    '<div id="api-results" class="api-results"></div>' +
    '</main>' +
    '<script>window.__API_INDEX__=' + JSON.stringify(payload).replace(/</g, '\\u003c') + ';</script>' +
    '<script>' + API_PAGE_JS + '</script>';
  return pageShell({ title: 'API 索引', relRoot: '', body, genAt: GEN_AT, sourcePath: 'md/lib' });
}

const API_PAGE_JS = `
(function(){
  var DATA = window.__API_INDEX__ || { classes: [] };
  var q = document.getElementById('api-q');
  var gsel = document.getElementById('api-g');
  var kindsBox = document.getElementById('api-kinds');
  var stat = document.getElementById('api-stat');
  var box = document.getElementById('api-results');
  var MAX_CARDS = 80, MAX_ROWS = 240;

  function kinds() {
    return Array.prototype.map.call(kindsBox.querySelectorAll('input:checked'), function(i){ return i.value; });
  }
  function esc(s){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
  function badge(k){ return '<span class="kind-badge k-'+({ '字段':'field','构造':'ctor','方法':'method','属性':'prop' }[k]||'')+'">'+esc(k)+'</span>'; }

  function render() {
    var kw = (q.value||'').trim().toLowerCase();
    var g = gsel.value;
    var ks = kinds();
    var rows = 0, cards = 0;
    var html = '';
    for (var i=0;i<DATA.classes.length && cards<MAX_CARDS && rows<MAX_ROWS;i++) {
      var c = DATA.classes[i];
      if (g && c.g !== g) continue;
      var cHit = !kw || (c.n+' '+c.m+' '+c.s).toLowerCase().indexOf(kw) >= 0;
      var mrows = '';
      if (kw) {
        for (var j=0;j<c.ms.length && rows<MAX_ROWS;j++) {
          var m = c.ms[j];
          if (ks.indexOf(m[0]) < 0) continue;
          if ((m[1]+' '+m[2]+' '+m[3]).toLowerCase().indexOf(kw) >= 0 || cHit) {
            mrows += '<tr><td>'+badge(m[0])+'</td><td><code>'+esc(m[2])+'</code></td><td class="d">'+esc(m[3])+'</td></tr>';
            rows++;
          }
        }
        if (!mrows && !cHit) continue;
      }
      cards++;
      html += '<section class="api-card">' +
        '<header><a class="cls-link" href="'+encodeURI(c.p)+'#'+encodeURIComponent(c.a)+'"><code class="cls-name">'+esc(c.n)+'</code></a>' +
        '<span class="kind-badge k-'+({ 'class':'field','enum':'prop' }[c.k]||'')+'">'+esc(c.k)+'</span>' +
        '<span class="mini-chip">'+esc(c.g)+'</span><code class="chip-src">'+esc(c.m)+'</code></header>' +
        (c.s ? '<p class="cls-summary">'+esc(c.s)+'</p>' : '') +
        (mrows ? '<div class="table-scroll"><table class="api-table"><thead><tr><th>种类</th><th>签名</th><th>说明</th></tr></thead><tbody>'+mrows+'</tbody></table></div>'
               : '<p class="m-count">'+c.mc+' 个成员 · <a href="'+encodeURI(c.p)+'#'+encodeURIComponent(c.a)+'">查看详情 →</a></p>') +
        '</section>';
    }
    box.innerHTML = html || '<p class="empty">无匹配结果</p>';
    var total = DATA.classes.length;
    stat.textContent = '类 ' + cards + (cards<total?' / '+total:'') + (kw?' · 成员行 '+rows:'');
  }
  q.addEventListener('input', render);
  gsel.addEventListener('change', render);
  kindsBox.addEventListener('change', render);
  Array.prototype.forEach.call(document.querySelectorAll('.g-chip'), function(btn){
    btn.addEventListener('click', function(){
      gsel.value = (gsel.value === btn.getAttribute('data-g')) ? '' : btn.getAttribute('data-g');
      render();
    });
  });
  render();
})();
`;

/* ---------------------------------------------------------------- CSS */
const CSS = `
:root{
  --bg:#f6f7fb; --bg-card:#ffffff; --bg-code:#0f172a; --bg-chip:#eef2ff;
  --fg:#1e293b; --fg-dim:#64748b; --line:#e2e8f0;
  --accent:#4f46e5; --accent-soft:#eef2ff; --link:#4338ca;
  --kw:#c084fc; --str:#86efac; --com:#94a3b8; --num:#fbbf24; --key:#7dd3fc; --type:#5eead4;
  --ok:#10b981; --warn:#f59e0b;
  --radius:10px; --shadow:0 1px 2px rgba(15,23,42,.06),0 8px 24px -12px rgba(15,23,42,.12);
}
@media (prefers-color-scheme: dark){
  :root{ --bg:#0b1120; --bg-card:#111a2e; --bg-code:#020617; --bg-chip:#1e2a4a;
    --fg:#e2e8f0; --fg-dim:#94a3b8; --line:#23304d; --accent:#818cf8; --accent-soft:#1e2a4a; --link:#a5b4fc;
    --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -12px rgba(0,0,0,.5); }
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--fg);
  font:15px/1.75 "Segoe UI","PingFang SC","Microsoft YaHei","Noto Sans CJK SC",system-ui,sans-serif;}
a{color:var(--link);text-decoration:none}
a:hover{text-decoration:underline}
code,pre,kbd{font-family:"Cascadia Code",Consolas,"JetBrains Mono",Menlo,monospace}
.wrap{max-width:1200px;margin:0 auto;padding:0 20px}
.topbar{position:sticky;top:0;z-index:50;background:color-mix(in srgb,var(--bg-card) 88%,transparent);
  backdrop-filter:blur(8px);border-bottom:1px solid var(--line)}
.topbar-in{display:flex;align-items:center;gap:22px;height:52px}
.brand{font-weight:700;color:var(--fg);display:flex;align-items:center;gap:8px;font-size:15px}
.brand:hover{text-decoration:none}
.brand-dot{width:10px;height:10px;border-radius:3px;background:linear-gradient(135deg,var(--accent),#22d3ee);display:inline-block}
.topnav{display:flex;gap:4px;flex:1}
.topnav a{padding:4px 12px;border-radius:8px;color:var(--fg-dim);font-weight:500}
.topnav a:hover{background:var(--accent-soft);color:var(--accent);text-decoration:none}
.topnav .nav-api{color:var(--accent)}
.gen-at{color:var(--fg-dim);font-size:12px}
.footer{border-top:1px solid var(--line);margin-top:48px;padding:20px 0;color:var(--fg-dim);font-size:13px;text-align:center}
.footer code{background:var(--bg-chip);padding:1px 6px;border-radius:6px}

/* hero / home */
.hero{text-align:center;padding:56px 0 30px}
.hero h1{font-size:34px;margin:0 0 10px;letter-spacing:.5px}
.hero-sub{color:var(--fg-dim);margin:0 0 26px}
.hero-sub code{background:var(--bg-chip);padding:1px 7px;border-radius:6px}
.stat-row{display:flex;gap:14px;justify-content:center;margin-bottom:26px;flex-wrap:wrap}
.stat{background:var(--bg-card);border:1px solid var(--line);border-radius:var(--radius);padding:14px 26px;box-shadow:var(--shadow);min-width:130px}
.stat b{display:block;font-size:26px;color:var(--accent)}
.stat span{color:var(--fg-dim);font-size:13px}
.cta-row{display:flex;gap:12px;justify-content:center;flex-wrap:wrap}
.btn{display:inline-block;padding:10px 20px;border-radius:10px;border:1px solid var(--line);
  background:var(--bg-card);color:var(--fg);font-weight:600;box-shadow:var(--shadow)}
.btn:hover{text-decoration:none;transform:translateY(-1px)}
.btn-primary{background:linear-gradient(135deg,var(--accent),#6366f1);border-color:transparent;color:#fff}
.btn-primary:hover{color:#fff}
.sec-title{margin:34px 0 16px;font-size:22px}
.group-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:16px;margin-bottom:30px}
.group-card{background:var(--bg-card);border:1px solid var(--line);border-radius:var(--radius);padding:16px 18px;box-shadow:var(--shadow)}
.group-card header{display:flex;justify-content:space-between;align-items:baseline;border-bottom:1px dashed var(--line);padding-bottom:8px;margin-bottom:10px}
.group-card h3{margin:0;font-size:17px}
.g-stats{color:var(--fg-dim);font-size:12px}
.doc-list{margin:0;padding:0;list-style:none;columns:2;column-gap:18px}
.doc-list li{break-inside:avoid;display:flex;align-items:center;gap:8px;padding:2px 0;font-size:13.5px}
.mini-chip{background:var(--bg-chip);color:var(--accent);border-radius:999px;font-size:11px;padding:0 8px;white-space:nowrap}
.note-card{background:var(--bg-card);border:1px solid var(--line);border-left:4px solid var(--accent);border-radius:var(--radius);padding:16px 20px;margin-bottom:30px}
.note-card h3{margin-top:0}

/* doc 页 */
.crumb{padding:14px 20px 0;color:var(--fg-dim);font-size:13px}
.crumb .sep{margin:0 6px;opacity:.6}
.crumb a{color:var(--fg-dim)} .crumb a:hover{color:var(--accent)}
.layout{display:grid;grid-template-columns:minmax(0,1fr) 230px;gap:28px;padding-top:8px}
.doc{background:var(--bg-card);border:1px solid var(--line);border-radius:var(--radius);padding:26px 30px 30px;box-shadow:var(--shadow)}
.doc-title{margin:0 0 6px;font-size:26px}
.doc-meta{display:flex;align-items:center;gap:10px;margin-bottom:14px;flex-wrap:wrap}
.chip{background:var(--accent-soft);color:var(--accent);border-radius:999px;padding:1px 12px;font-size:12px;font-weight:600}
.chip-src{color:var(--fg-dim);font-size:12px;background:var(--bg-chip);border-radius:6px;padding:1px 8px}
.api-entry{display:flex;align-items:center;gap:8px;flex-wrap:wrap;background:var(--bg-chip);
  border-radius:var(--radius);padding:10px 14px;margin:0 0 18px}
.api-entry-label{font-weight:700;color:var(--accent);font-size:12px;letter-spacing:1px}
.cls-chip{background:var(--bg-card);border:1px solid var(--line);border-radius:999px;padding:2px 12px;font-size:12.5px;
  font-family:Consolas,Menlo,monospace;color:var(--fg)}
.cls-chip em{font-style:normal;color:var(--fg-dim);margin-left:5px;font-size:11px}
.cls-chip:hover{border-color:var(--accent);text-decoration:none}
.toc{position:sticky;top:68px;align-self:start;max-height:calc(100vh - 90px);overflow:auto;font-size:13px;
  background:var(--bg-card);border:1px solid var(--line);border-radius:var(--radius);padding:12px 0}
.toc-title{font-weight:700;padding:0 14px 6px;color:var(--fg-dim);font-size:12px;letter-spacing:1px}
.toc ul{list-style:none;margin:0;padding:0}
.toc li a{display:block;padding:2px 14px;color:var(--fg-dim);border-left:2px solid transparent}
.toc li a:hover{color:var(--accent);text-decoration:none;border-left-color:var(--accent)}
.toc li.lv3 a{padding-left:28px;font-size:12.5px}
.toc li.is-cls a{color:var(--accent);font-family:Consolas,Menlo,monospace}
h2[id],h3[id],h4[id]{scroll-margin-top:66px}
.doc h2{font-size:20px;margin:30px 0 10px;padding-bottom:6px;border-bottom:1px solid var(--line)}
.doc h3{font-size:16.5px;margin:22px 0 8px}
.cls-heading{display:flex;align-items:center;gap:10px}
.cls-kind{background:var(--bg-chip);color:var(--accent);font-size:11px;font-weight:700;border-radius:6px;padding:2px 8px;letter-spacing:1px}
.cls-name{font-size:18px;font-weight:700;color:var(--fg)}
.anchor-link{opacity:0;margin-left:8px;font-weight:400;color:var(--fg-dim)}
h2:hover .anchor-link,h3:hover .anchor-link{opacity:.7;text-decoration:none}
.cls-summary{color:var(--fg-dim);font-size:13.5px;background:var(--bg-chip);border-radius:8px;padding:8px 12px}
blockquote{margin:14px 0;padding:10px 16px;border-left:4px solid var(--accent);background:var(--bg-chip);border-radius:0 8px 8px 0;color:var(--fg-dim)}
blockquote p{margin:6px 0}
.md-list{padding-left:24px}
.md-list li{margin:4px 0}
.doc code{background:var(--bg-chip);border-radius:6px;padding:1px 6px;font-size:.92em}
.doc p code,.doc li code,.doc td code{word-break:break-all}
.table-scroll{overflow-x:auto;margin:14px 0}
table{border-collapse:collapse;width:100%;font-size:13.5px}
.md-table th,.api-table th{background:var(--bg-chip);text-align:left;font-weight:700}
.md-table th,.md-table td,.api-table th,.api-table td{border:1px solid var(--line);padding:7px 12px;vertical-align:top}
.api-table tbody tr:nth-child(odd){background:color-mix(in srgb,var(--bg-chip) 40%,transparent)}
.kind-badge{display:inline-block;border-radius:6px;font-size:11px;font-weight:700;padding:1px 8px;white-space:nowrap}
.k-field{background:#f1f5f9;color:#475569}
.k-ctor{background:#f3e8ff;color:#7e22ce}
.k-method{background:#dbeafe;color:#1d4ed8}
.k-prop{background:#d1fae5;color:#047857}
@media (prefers-color-scheme: dark){
  .k-field{background:#23304d;color:#94a3b8}.k-ctor{background:#3b1d5e;color:#d8b4fe}
  .k-method{background:#172a54;color:#93c5fd}.k-prop{background:#0c3a2e;color:#6ee7b7}
}
figure.code{margin:14px 0;border-radius:var(--radius);overflow:hidden;box-shadow:var(--shadow)}
figure.code figcaption{background:#1e293b;color:#94a3b8;font-size:11px;padding:5px 14px;letter-spacing:1px;text-transform:uppercase}
figure.code pre{margin:0;background:var(--bg-code);padding:14px 16px;overflow-x:auto}
figure.code code{background:none;padding:0;color:#e2e8f0;font-size:13px;line-height:1.6}
.tok-kw{color:var(--kw)} .tok-str{color:var(--str)} .tok-com{color:var(--com);font-style:italic}
.tok-num{color:var(--num)} .tok-key{color:var(--key)} .tok-type{color:var(--type)}
a.md-missing{opacity:.65;border-bottom:1px dashed var(--fg-dim)}
.img-alt{color:var(--fg-dim);font-size:13px}
.empty{color:var(--fg-dim);text-align:center;padding:30px 0}

/* API 索引页 */
.api-page h1{margin-bottom:4px}
.api-toolbar{display:flex;gap:10px;margin:18px 0 10px}
.api-toolbar input{flex:1;padding:10px 16px;border-radius:10px;border:1px solid var(--line);
  background:var(--bg-card);color:var(--fg);font-size:14px;outline:none}
.api-toolbar input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-soft)}
.api-toolbar select{padding:10px 12px;border-radius:10px;border:1px solid var(--line);background:var(--bg-card);color:var(--fg)}
.api-kinds{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:12px}
.kind-toggle{cursor:pointer}
.kind-toggle input{position:absolute;opacity:0}
.kind-toggle input:not(:checked)+.kind-badge{opacity:.28}
.api-stat{color:var(--fg-dim);font-size:12.5px;margin-left:auto}
.g-chips{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px}
.g-chip{cursor:pointer;border:1px solid var(--line);background:var(--bg-card);color:var(--fg-dim);
  border-radius:999px;padding:4px 14px;font-size:12.5px}
.g-chip em{font-style:normal;color:var(--accent);margin-left:4px}
.g-chip:hover{border-color:var(--accent);color:var(--accent)}
.api-results{display:grid;grid-template-columns:repeat(auto-fill,minmax(480px,1fr));gap:14px}
@media (max-width:1100px){.api-results{grid-template-columns:1fr}}
.api-card{background:var(--bg-card);border:1px solid var(--line);border-radius:var(--radius);padding:14px 16px;box-shadow:var(--shadow)}
.api-card header{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:6px}
.api-card .cls-link{font-size:16px}
.api-card .cls-link code{font-weight:700;color:var(--accent);background:none;padding:0;font-size:16px}
.api-card .m-count{color:var(--fg-dim);font-size:12.5px;margin:4px 0 0}
.api-card .api-table{font-size:12.5px}
.api-card .api-table td.d{color:var(--fg-dim)}

/* 入门 / 关于页 */
.run-note{background:var(--bg-chip);border:1px solid var(--line);border-left:4px solid var(--ok);
  border-radius:var(--radius);padding:12px 18px;margin:0 0 10px}
.link-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px;margin:14px 0}
.friend-card{display:flex;flex-direction:column;gap:4px;background:var(--bg-card);border:1px solid var(--line);
  border-radius:var(--radius);padding:14px 16px;box-shadow:var(--shadow);color:var(--fg)}
.friend-card:hover{text-decoration:none;border-color:var(--accent);transform:translateY(-1px)}
.friend-card b{color:var(--accent)}
.friend-card span{color:var(--fg-dim);font-size:12.5px}
.missing{color:var(--warn);font-size:13px}
.dim{color:var(--fg-dim);font-size:13px}

/* 示例库页 */
.ex-grid{display:grid;grid-template-columns:1fr;gap:14px}
@media (min-width:1400px){.ex-grid{grid-template-columns:repeat(auto-fill,minmax(700px,1fr))}}
.ex-card .ex-title{color:var(--accent);font-size:15px}
.run-badge{background:#d1fae5;color:#047857;border-radius:999px;font-size:11px;font-weight:700;padding:1px 10px;white-space:nowrap}
@media (prefers-color-scheme: dark){.run-badge{background:#0c3a2e;color:#6ee7b7}}
.tree-dir{background:var(--bg-card);border:1px solid var(--line);border-radius:var(--radius);padding:8px 14px;margin:8px 0}
.tree-dir summary{cursor:pointer;font-weight:600;color:var(--fg)}
.tree-dir summary em{color:var(--fg-dim);font-style:normal;font-size:12px;margin-left:6px}
.tree-list{list-style:none;margin:8px 0 2px;padding:0;columns:3;column-gap:18px;font-size:12px}
.tree-list li{break-inside:avoid;padding:1px 0}
.tree-list code{background:none;padding:0;color:var(--fg-dim)}
@media (max-width:960px){
  .layout{grid-template-columns:1fr}
  .toc{display:none}
  .doc-list{columns:1}
  .gen-at{display:none}
}
@media print{.topbar,.toc,.footer,.cta-row{display:none}.doc{border:none;box-shadow:none}}
`;

/* ---------------------------------------------------------------- 入门页（使用示例） */
/** 读 samples 下示例源码 → 代码块（源码直读磁盘，与仓库保持同步） */
function sampleFigure(relPath, lang, label) {
  const full = path.join(SAMPLES_ROOT, relPath.replace(/\//g, path.sep));
  let code;
  try { code = readText(full); } catch (e) {
    return '<p class="missing">示例缺失：<code>' + esc(relPath) + '</code></p>';
  }
  return '<h3>' + esc(label) + ' <code class="chip-src">SLangCore/samples/' + esc(relPath) + '</code></h3>' +
    '<figure class="code"><figcaption>' + esc(lang) + '</figcaption><pre><code>' +
    highlightCode(code, lang) + '</code></pre></figure>';
}

function renderGettingStarted() {
  const gh = 'https://github.com/kamaba/';
  const html = [];
  html.push('<main class="wrap">');
  html.push('<h1 class="doc-title">入门</h1>');
  html.push('<p class="hero-sub">从安装到第一个程序，再到常用语法使用示例</p>');
  html.push('<div class="run-note">✓ <b>本站展示的所有代码示例均可编译运行</b>' +
    ' —— 10 例已全部在本仓库工具链实测（Front 编译 → C VM 执行 → 输出逐字核对；' +
    '<code>Console.println</code> 自带换行），完整列表与实测输出见 <a href="examples.html">示例库 →</a></div>');

  // 快速开始
  html.push('<h2 id="quickstart">快速开始</h2>');
  html.push('<h3>方式一：Release 下载（目标机零依赖）</h3>');
  html.push('<p>从 <a href="' + gh + 'SlangAllInOne/releases" target="_blank" rel="noopener">GitHub Releases</a> ' +
    '下载最新版并解压（每版双平台同发）：<code>slang_release_&lt;v&gt;_win-x64.zip</code> / ' +
    '<code>slang_release_&lt;v&gt;_linux-x64.tar.gz</code>。<code>slang</code> 主程序为 Native AOT 自包含原生二进制，' +
    '无需安装 .NET 运行时；包内含 C VM 运行时与系统标准库。</p>');
  html.push('<h3>方式二：从源码构建</h3>');
  html.push('<p>需本机安装 .NET 8 SDK；两个仓库需放在同一父目录下平级摆放（工程引用为跨仓库相对路径）：</p>');
  html.push('<figure class="code"><figcaption>bash</figcaption><pre><code>' +
    highlightCode('git clone https://github.com/kamaba/simple_language.git\ngit clone https://github.com/kamaba/SlangAllInOne.git\ncd SlangAllInOne\ndotnet build SlangAllInOne.sln', 'bash') +
    '</code></pre></figure>');

  // 第一个程序
  html.push('<h2 id="first-program">第一个程序（实测通过 ✓）</h2>');
  html.push('<p>最小可运行工程由三件套组成：源码 <code>.sl</code> + 入口 <code>.sp</code> + 工程配置 <code>.jsonc</code>。</p>');
  html.push(sampleFigure('HelloWorld/HelloWorld.sl', 'csharp', '源码'));
  html.push(sampleFigure('HelloWorld/HelloWorld.sp', 'csharp', '入口工程'));
  html.push(sampleFigure('HelloWorld/HelloWorld.jsonc', 'jsonc', '工程配置（引用标准库 Core / Std）'));
  html.push('<h3>编译运行</h3>');
  html.push('<figure class="code"><figcaption>bash</figcaption><pre><code>' +
    highlightCode('# 发布包 slang（Native AOT，零依赖）\nslang SLangCore/samples/HelloWorld/HelloWorld.sp\n' +
      '# 源码开发（.NET 8 SDK）\ndotnet run --project SlangAllInOne -- SlangAllInOne/SLangCore/samples/HelloWorld/HelloWorld.sp --no-banner', 'bash') +
    '</code></pre></figure>');
  html.push('<h3>实测输出</h3>');
  html.push('<figure class="code"><figcaption>output</figcaption><pre><code>Hello, Slang!</code></pre></figure>');

  // 语法示例
  html.push('<h2 id="syntax-examples">语法示例（文档示例源码）</h2>');
  html.push('<p><code>SLangCore/samples/MDExample/</code> 是 <code>md/syntax</code> 文档示例的<b>可运行源码</b>落地位置。' +
    '已合并为一键工程 <code>MDExamples.sp</code>（5 例一次跑通，<a href="examples.html#mdex">实测输出 →</a>）；' +
    '旧「并入 Core.jsonc」方式仍可用（见 <code>MDExample/README.md</code>）。</p>');
  html.push('<h3>示例 1 · 字符串插值（对应 <a href="syntax/string.html">md/syntax/string.md</a>）</h3>');
  html.push(sampleFigure('MDExample/02_StringInterpolation/Doc02_StringInterpolation.sl', 'csharp', ''));
  html.push('<p>要点：<code>$变量</code> 与 <code>$对象.成员</code> 两种插值形态；示例打印使用 <code>global.println</code>' +
    '（并入 Core 工程调试时与 <code>Console.print</code> 等价）。</p>');
  html.push('<h3>示例 2 · Range 区间遍历（对应 <a href="syntax/range.html">md/syntax/range.md</a>）</h3>');
  html.push(sampleFigure('MDExample/04_RangeFor/Doc04_RangeFor.sl', 'csharp', ''));
  html.push('<h3>运行方式（并入标准库 Core 工程，三步）</h3>');
  html.push('<ol class="md-list">' +
    '<li>把示例子目录内 <code>CORE_JSONC_COMPILE_FILES_APPEND.txt</code> 的条目追加进 <code>SLangCore/Lib/Core/Core.jsonc</code> 的 <code>compileFiles.files</code>；</li>' +
    '<li>在 <code>Core.sp</code> 的 <code>_main_()</code> 中调用对应示例入口（如 <code>MdEx02StringInterpolation.Run()</code>）；</li>' +
    '<li>按「第一个程序」的方式编译运行，查看输出。</li></ol>');

  // 示例索引
  html.push('<h2 id="sample-index">示例源码索引（全部 <a href="examples.html">示例库 →</a>）</h2>');
  html.push('<div class="table-scroll"><table class="md-table"><thead><tr><th>位置</th><th>内容</th><th>状态</th></tr></thead><tbody>' +
    '<tr><td><code>samples/HelloWorld/</code></td><td>第一个程序（.sl + .sp + .jsonc 三件套）</td><td>✓ 实测：输出 <code>Hello, Slang!</code>（println 带换行）</td></tr>' +
    '<tr><td><code>samples/</code> 根级</td><td>脚本示例：斐波那契数列 / 九九乘法表 / 延时打印 / 全并字母（各配独立工程对）</td><td>✓ 实测：4/4 通过</td></tr>' +
    '<tr><td><code>samples/MDExample/</code></td><td>语法示例 5 主题（一键工程 <code>MDExamples.sp</code>）</td><td>✓ 实测：5/5 通过</td></tr>' +
    '<tr><td><code>samples/SLang/source/</code></td><td>自举实验树（231 个 .sl，C# 风格历史手稿）</td><td>历史参考 · 未接入编译验证</td></tr>' +
    '</tbody></table></div>');
  html.push('</main>');
  return pageShell({ title: '入门', relRoot: '', body: html.join('\n'), genAt: GEN_AT, sourcePath: 'SLangCore/samples + README' });
}

/* ---------------------------------------------------------------- 示例库页（使用示例全量展示） */
/** 已实测示例清单（output 为工具链实测逐字输出；code 运行时直读磁盘保持同步） */
const VERIFIED_EXAMPLES = {
  hello: {
    title: 'HelloWorld · 第一个程序',
    file: 'HelloWorld/HelloWorld.sl',
    project: 'HelloWorld/HelloWorld.sp',
    output: 'Hello, Slang!',
    desc: '最小可运行工程（.sl + .sp + .jsonc 三件套）· Console.println 自带换行',
  },
  scripts: [
    { title: '斐波那契数列', file: '斐波那契数列.sl', project: 'Fibonacci.sp', desc: '循环 + 字符串插值，输出前 10 项',
      output: '11235813213455' },
    { title: '九九乘法表', file: '九九乘法表.sl', project: 'NineTable.sp', desc: '双重循环 + 插值拼接',
      output: '1x 1= 1  \n1x 2= 2  2x 2= 4  \n1x 3= 3  2x 3= 6  3x 3= 9  \n1x 4= 4  2x 4= 8  3x 4= 12  4x 4= 16  \n1x 5= 5  2x 5= 10  3x 5= 15  4x 5= 20  5x 5= 25  \n1x 6= 6  2x 6= 12  3x 6= 18  4x 6= 24  5x 6= 30  6x 6= 36  \n1x 7= 7  2x 7= 14  3x 7= 21  4x 7= 28  5x 7= 35  6x 7= 42  7x 7= 49  \n1x 8= 8  2x 8= 16  3x 8= 24  4x 8= 32  5x 8= 40  6x 8= 48  7x 8= 56  8x 8= 64  \n1x 9= 9  2x 9= 18  3x 9= 27  4x 9= 36  5x 9= 45  6x 9= 54  7x 9= 63  8x 9= 72  9x 9= 81  ' },
    { title: '延时打印', file: '延时打印.sl', project: 'DelayPrint.sp', desc: 'await 挂起 200ms（协程最小示例，不阻塞调度）',
      output: 'wait 200ms ...delay done, cost=204ms' },
    { title: '全并字母', file: '全并字母.sl', project: 'MergeLetters.sp', desc: '小写容器糖 list()、for-in 遍历、元素合并',
      output: 'merged: acebd' },
  ],
  mdex: [
    { title: '基础类与字段', file: 'MDExample/01_BaseRectangle/Doc01_BaseRectangle.sl', doc: 'syntax/introduction.html', desc: '类 / 字段 / 方法 / toString / ${} 插值' },
    { title: '字符串插值', file: 'MDExample/02_StringInterpolation/Doc02_StringInterpolation.sl', doc: 'syntax/string.html', desc: '$变量 与 $对象.成员 两种插值形态' },
    { title: 'global 与 jsonc 数据注入', file: 'MDExample/03_GlobalJsonc/Doc03_GlobalJsonc.sl', doc: 'syntax/global.html', desc: 'jsonc global.data 注入 global.var1（本工程注入 42）' },
    { title: 'Range 区间遍历', file: 'MDExample/04_RangeFor/Doc04_RangeFor.sl', doc: 'syntax/range.html', desc: 'Range<int> + for v in r' },
    { title: 'switch 值匹配', file: 'MDExample/05_SwitchValue/Doc05_SwitchValue.sl', doc: 'syntax/switch.html', desc: 'switch day / case / default' },
  ],
  mdexOutput: 'Rectangle(10 x 4)\nprint a=10\nprint c1.a1=22\nvalue=1\nvalue=2\nvalue=3\nvalue=4\nvalue=5\nWed\nfrom jsonc var1=42',
};

function exampleCard(ex, opts) {
  const code = (() => {
    try { return readText(path.join(SAMPLES_ROOT, ex.file.replace(/\//g, path.sep))); } catch (e) { return null; }
  })();
  let html = '<section class="api-card ex-card" data-kw="' + esc((ex.title + ' ' + (ex.desc || '') + ' ' + ex.file).toLowerCase()) + '">' +
    '<header><b class="ex-title">' + esc(ex.title) + '</b>' +
    '<span class="run-badge">✓ 已实测编译运行</span>' +
    '<code class="chip-src">samples/' + esc(ex.file) + '</code></header>' +
    (ex.desc ? '<p class="cls-summary">' + esc(ex.desc) + '</p>' : '');
  html += code !== null
    ? '<figure class="code"><figcaption>sl</figcaption><pre><code>' + highlightCode(code, 'csharp') + '</code></pre></figure>'
    : '<p class="missing">示例源码缺失：samples/' + esc(ex.file) + '</p>';
  if (opts.withProject && ex.project) {
    html += '<p class="dim">工程：<code>samples/' + esc(ex.project) + '</code> · 运行：<code>slang SLangCore/samples/' + esc(ex.project) + '</code></p>';
  }
  if (opts.withOutput && ex.output !== undefined) {
    html += '<figure class="code"><figcaption>output · 实测</figcaption><pre><code>' + esc(ex.output) + '</code></pre></figure>';
  }
  return html + '</section>';
}

function renderExamples() {
  const bootCode = (() => { try { return readText(path.join(SAMPLES_ROOT, 'HelloWorld', 'HelloWorld.sp')); } catch (e) { return ''; } })();
  const bootJson = (() => { try { return readText(path.join(SAMPLES_ROOT, 'HelloWorld', 'HelloWorld.jsonc')); } catch (e) { return ''; } })();
  const bootMd = (() => { try { return readText(path.join(SAMPLES_ROOT, 'HelloWorld', 'HelloWorld.sl')); } catch (e) { return ''; } })();

  const treeDirs = {};
  try {
    const srcDir = path.join(SAMPLES_ROOT, 'SLang', 'source');
    for (const f of walkMd(srcDir)) {
      const top = f.split('/')[0];
      (treeDirs[top] = treeDirs[top] || []).push(f);
    }
  } catch (e) { /* 目录缺失忽略 */ }
  const treeHtml = Object.keys(treeDirs).sort().map((d) =>
    '<details class="tree-dir"><summary>' + esc(d) + '/ <em>' + treeDirs[d].length + ' 个 .sl</em></summary><ul class="tree-list">' +
    treeDirs[d].map((f) => '<li><code>' + esc(f) + '</code></li>').join('') + '</ul></details>').join('');
  const treeCount = Object.values(treeDirs).reduce((n, a) => n + a.length, 0);

  const html = [];
  html.push('<main class="wrap">');
  html.push('<h1 class="doc-title">示例库</h1>');
  html.push('<p class="hero-sub">SLang 使用示例全量展示 · 打 ✓ 的示例均已在本仓库工具链实测（编译 → C VM 执行 → 输出逐字核对）</p>');
  html.push('<div class="run-note">✓ <b>本页所有标注「已实测」的示例均可编译运行</b>' +
    '（当前 ' + (1 + VERIFIED_EXAMPLES.scripts.length + VERIFIED_EXAMPLES.mdex.length) + ' 例全部通过）；' +
    '「自举实验树」为历史手稿，单独标注说明，不在可运行声明范围内。</div>');
  html.push('<div class="api-toolbar"><input id="ex-q" type="search" placeholder="搜索示例标题 / 说明 / 文件名…"></div>');

  html.push('<h2 id="hello" class="sec-title">入门示例</h2>');
  const hello = VERIFIED_EXAMPLES.hello;
  html.push('<section class="api-card ex-card" data-kw="helloworld hello 入门 第一个程序">');
  html.push('<header><b class="ex-title">' + esc(hello.title) + '</b><span class="run-badge">✓ 已实测编译运行</span>' +
    '<code class="chip-src">samples/' + esc(hello.file) + '</code></header>');
  html.push('<p class="cls-summary">' + esc(hello.desc) + ' —— 源码 / 入口 / 配置三件：</p>');
  html.push('<figure class="code"><figcaption>sl · 源码</figcaption><pre><code>' + highlightCode(bootMd, 'csharp') + '</code></pre></figure>');
  html.push('<figure class="code"><figcaption>sp · 入口</figcaption><pre><code>' + highlightCode(bootCode, 'csharp') + '</code></pre></figure>');
  html.push('<figure class="code"><figcaption>jsonc · 工程配置</figcaption><pre><code>' + highlightCode(bootJson, 'jsonc') + '</code></pre></figure>');
  html.push('<p class="dim">运行：<code>slang SLangCore/samples/HelloWorld/HelloWorld.sp</code>（发布包）或 ' +
    '<code>dotnet run --project SlangAllInOne -- SlangAllInOne/SLangCore/samples/HelloWorld/HelloWorld.sp</code>（源码）</p>');
  html.push('<figure class="code"><figcaption>output · 实测</figcaption><pre><code>' + esc(hello.output) + '</code></pre></figure>');
  html.push('</section>');

  html.push('<h2 id="scripts" class="sec-title">脚本示例（samples 根级）</h2>');
  html.push('<div class="ex-grid">' + VERIFIED_EXAMPLES.scripts.map((ex) => exampleCard(ex, { withProject: true, withOutput: true })).join('') + '</div>');

  html.push('<h2 id="mdex" class="sec-title">语法示例（md/syntax 文档示例源码 · 一键工程）</h2>');
  html.push('<p>对应 <code>md/syntax</code> 各章的可运行源码；已合并为一键工程 ' +
    '<code>samples/MDExample/MDExamples.sp</code>（jsonc 注入 <code>global.var1</code>），5 例一次跑通：</p>');
  html.push('<div class="ex-grid">' + VERIFIED_EXAMPLES.mdex.map((ex) => exampleCard(ex, { withProject: false, withOutput: false })).join('') + '</div>');
  html.push('<p class="dim">运行：<code>dotnet run --project SlangAllInOne -- SlangAllInOne/SLangCore/samples/MDExample/MDExamples.sp</code>' +
    '（旧「并入 Core.jsonc」方式仍可用，见 <code>MDExample/README.md</code>）</p>');
  html.push('<figure class="code"><figcaption>output · 实测（5 例合并）</figcaption><pre><code>' + esc(VERIFIED_EXAMPLES.mdexOutput) + '</code></pre></figure>');

  html.push('<h2 id="tree" class="sec-title">自举实验树（历史手稿 · 未接入编译验证）</h2>');
  html.push('<p class="dim"><code>samples/SLang/source/</code> 为早期以 SL 手写的编译器分层实验稿（' + treeCount +
    ' 个 .sl，C# 风格旧语法 <code>using</code>/<code>return</code>），仅作历史参考——<b>不在</b>「可编译运行」声明范围内。</p>');
  html.push(treeHtml);

  html.push('</main>');
  html.push('<script>' +
    '(function(){var q=document.getElementById("ex-q");if(!q)return;' +
    'var cards=document.querySelectorAll(".ex-card");' +
    'q.addEventListener("input",function(){var k=q.value.trim().toLowerCase();' +
    'cards.forEach(function(c){c.style.display=(!k||(c.getAttribute("data-kw")||"").indexOf(k)>=0)?"":"none";});});})();</script>');
  return pageShell({ title: '示例库', relRoot: '', body: html.join('\n'), genAt: GEN_AT, sourcePath: 'SLangCore/samples（源码直读）' });
}

/* ---------------------------------------------------------------- 关于页（社区资讯） */
function mdInline(text) {
  return esc(String(text)).replace(/`([^`]+)`/g, '<code>$1</code>');
}

function renderAbout() {
  const c = SITE_DATA.community;
  const html = [];
  html.push('<main class="wrap about-page">');
  html.push('<h1 class="doc-title">关于</h1>');
  html.push('<p class="hero-sub">社区资讯 · 友情链接</p>');

  html.push('<h2 id="intro">社区介绍</h2>');
  html.push('<p>' + mdInline(c.intro) + '</p>');
  html.push('<p>语言特性与标准库全貌见<a href="index.html#groups">库目录</a>与 <a href="getting-started.html">入门</a>；' +
    '语法细节以 <a href="syntax/introduction.html">md/syntax</a> 各章为准。</p>');

  html.push('<h2 id="repos">代码仓库</h2>');
  html.push('<div class="table-scroll"><table class="md-table"><thead><tr><th>仓库</th><th>定位</th><th>技术栈</th></tr></thead><tbody>');
  for (const r of c.repos) {
    html.push('<tr><td><a href="' + esc(r.url) + '" target="_blank" rel="noopener"><code>' + esc(r.name) + '</code></a></td>' +
      '<td>' + esc(r.desc) + '</td><td>' + esc(r.stack || '') + '</td></tr>');
  }
  html.push('<tr><td><a href="https://github.com/kamaba/SlangAllInOne/releases" target="_blank" rel="noopener"><code>Releases</code></a></td>' +
    '<td>版本发布（双平台同发，附更新说明）</td><td>Native AOT</td></tr>');
  html.push('</tbody></table></div>');

  html.push('<h2 id="copyright">版权信息</h2>');
  html.push('<p>' + mdInline(c.copyright) + '</p>');

  html.push('<h2 id="proposal">提案（RFC）</h2>');
  html.push('<p>' + mdInline(c.proposal) + '</p>');
  html.push('<p><a href="https://github.com/kamaba/SlangAllInOne/issues" target="_blank" rel="noopener">GitHub Issues · 提交提案 →</a></p>');

  html.push('<h2 id="minutes">节点记要</h2>');
  html.push('<p>' + mdInline(c.minutes) + '</p>');

  html.push('<h2 id="sponsor">赞助</h2>');
  html.push('<p>' + mdInline(c.sponsor) + '</p>');

  html.push('<h2 id="friend-links">友情链接</h2>');
  html.push('<div class="link-grid">');
  for (const l of SITE_DATA.friendLinks) {
    html.push('<a class="friend-card" href="' + esc(l.url) + '" target="_blank" rel="noopener">' +
      '<b>' + esc(l.name) + '</b><span>' + esc(l.desc || '') + '</span></a>');
  }
  html.push('</div>');
  html.push('<p class="dim">申请收录友情链接：请到 <a href="https://github.com/kamaba/SlangAllInOne/issues" target="_blank" rel="noopener">GitHub Issues</a> 提交（站点名 / 地址 / 简介与 SLang 或脚本语言生态的相关性说明）。</p>');
  html.push('</main>');
  return pageShell({ title: '关于', relRoot: '', body: html.join('\n'), genAt: GEN_AT, sourcePath: 'site-data.jsonc + README + LICENSE' });
}

/* ---------------------------------------------------------------- 后管控制台页 */
function renderAdmin() {
  const body = '<main class="wrap admin-page">' +
    '<h1 class="doc-title">后管控制台</h1>' +
    '<p class="hero-sub">版本管理（本体 / VSCode / 插件 / 包 分组件）· 站点数据 · 一键重建</p>' +
    '<div class="run-note" id="admin-hint">ⓘ 后管能力需经本机服务启用：<code>node tools/docs-web/admin-server.js 8932</code>，' +
    '然后访问 <code>http://127.0.0.1:8932/admin</code>。当前为静态预览模式（只读）。</div>' +

    '<h2 id="versions">版本管理</h2>' +
    '<p class="dim">各组版本<b>分开管理、独立演进</b>（2026-11-03 用户改版，废止旧「四端同步 +1」）；' +
    '「扫描值」实时读自仓库锚点文件，保存即写回锚点并记录历史。</p>' +
    '<div id="ver-tables"></div>' +
    '<h3 id="ver-history">版本变更历史</h3><div id="ver-history-body" class="dim">（载入中…）</div>' +

    '<h2 id="site-data">站点数据（site-data.jsonc）</h2>' +
    '<p class="dim">友情链接 / 社区资讯六大分类 / 自举句均在此文件；保存后请点「重建站点」生效。</p>' +
    '<textarea id="sd-editor" spellcheck="false"></textarea>' +
    '<div class="cta-row" style="justify-content:flex-start;margin:10px 0">' +
    '<button class="btn btn-primary" id="sd-save">保存 site-data.jsonc</button>' +
    '<button class="btn" id="sd-reload">重新载入</button>' +
    '<button class="btn" id="rb-btn">🔄 重建站点</button></div>' +
    '<pre id="rb-out" class="rb-out" style="display:none"></pre>' +
    '</main>' +
    '<style>.ver-table{width:100%;margin:10px 0 22px}.ver-table td,.ver-table th{padding:6px 10px}' +
    '#sd-editor{width:100%;min-height:320px;border-radius:10px;border:1px solid var(--line);background:var(--bg-card);' +
    'color:var(--fg);font-family:Consolas,Menlo,monospace;font-size:12.5px;padding:12px}' +
    '.rb-out{background:var(--bg-code);color:#e2e8f0;border-radius:10px;padding:12px 16px;overflow:auto;font-size:12px}' +
    '.ver-in{width:110px;padding:4px 8px;border-radius:6px;border:1px solid var(--line);background:var(--bg-card);color:var(--fg)}' +
    '.ver-save{cursor:pointer;border:1px solid var(--accent);background:var(--accent-soft);color:var(--accent);border-radius:6px;padding:3px 10px}' +
    '.hint-ok{color:var(--ok)}.hint-info{border-left-color:var(--accent)!important}' +
    '.hint-error{background:#fff1f0;border-color:#ffccc7;border-left-color:#ff4d4f!important;color:#a8071a}' +
    '</style>' +
    '<script>window.__ADMIN_FALLBACK__=' + JSON.stringify({ groups: ADMIN_VERSION_GROUPS, history: [] }).replace(/</g, '\\u003c') + ';</script>' +
    '<script>' + ADMIN_PAGE_JS + '</script>';
  return pageShell({ title: '后管控制台', relRoot: '', body, genAt: GEN_AT, sourcePath: 'admin-server API' });
}

const ADMIN_PAGE_JS = `
(function(){
  var $ = function(id){ return document.getElementById(id); };
  var LIVE = false;

  function renderTables(data) {
    var wrap = $('ver-tables');
    wrap.innerHTML = '';
    data.groups.forEach(function(g){
      var rows = g.items.map(function(it){
        return '<tr><td><b>'+esc(it.label)+'</b><div class="dim">'+esc(it.key)+'</div></td>' +
          '<td><code>'+esc(it.version||'?')+'</code></td>' +
          '<td class="dim" style="font-size:11px">'+esc(it.source)+'</td>' +
          '<td><input class="ver-in" id="in-'+esc(it.key)+'" placeholder="'+esc(it.version||'')+'">' +
          '<button class="ver-save" data-key="'+esc(it.key)+'">保存</button></td></tr>';
      }).join('');
      wrap.innerHTML += '<table class="md-table ver-table"><thead><tr><th>'+esc(g.label)+'</th><th>当前版本</th><th>锚点文件</th><th>改为</th></tr></thead><tbody>'+rows+'</tbody></table>';
    });
    wrap.querySelectorAll('.ver-save').forEach(function(btn){
      btn.addEventListener('click', function(){
        var key = btn.getAttribute('data-key');
        var val = $('in-'+key).value.trim();
        if (!val) return alert('请输入版本号（主.发布.小版本）');
        if (!LIVE) return alert('静态预览模式不可写：请以 admin-server 启动后操作。');
        api('/api/version/set', { key: key, value: val }).then(function(){ load(); }).catch(function(e){ alert(e.message); });
      });
    });
    var h = data.history || [];
    $('ver-history-body').innerHTML = h.length
      ? '<ul class="md-list">' + h.slice(0,20).map(function(x){ return '<li>'+esc(x.at.replace('T',' ').slice(0,19))+' · <code>'+esc(x.key)+'</code> '+esc(x.from||'—')+' → <b>'+esc(x.to)+'</b></li>'; }).join('') + '</ul>'
      : '暂无变更记录（后管内保存版本后自动记录）';
  }

  function esc(s){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
  function api(url, body) {
    return fetch(url, body ? { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body) } : undefined)
      .then(function(r){ return r.json().then(function(j){ if (!j.ok) throw new Error(j.error||'请求失败'); return j; }); });
  }
  function showHint(kind, html){
    var el = $('admin-hint');
    el.innerHTML = html;
    el.className = 'run-note' + (kind === 'ok' ? ' hint-ok' : kind === 'error' ? ' hint-error' : kind === 'info' ? ' hint-info' : '');
  }

  function load() {
    fetch('/api/versions')
      .then(function(r){ if (!r.ok) throw { api:true, msg:'HTTP ' + r.status }; return r.json(); })
      .then(function(data){
        if (!data.ok) throw { api:true, msg: data.error || '加载失败' };
        LIVE = true;
        showHint('ok', '✓ 后管服务已连接（本机 <code>admin-server</code>）。改动即时写回仓库锚点文件，历史留痕于 <code>tools/docs-web/version-history.json</code>。');
        renderTables(data);
        return api('/api/site-data');
      })
      .then(function(d){ if (d && d.content != null) $('sd-editor').value = d.content; })
      .catch(function(e){
        if (e && e.api) {
          showHint('error', '✗ 后管接口返回错误：' + e.msg + '。下方为生成期只读快照。');
        } else {
          showHint('info', 'ℹ 当前为<b>只读预览</b>：版本写回需经本机后管服务（<code>node tools/docs-web/admin-server.js 8932</code>，再访问 <code>/admin</code>）。下方为生成期快照，写入按钮不可用。');
        }
        renderTables(window.__ADMIN_FALLBACK__ || { groups: [], history: [] });
      });
  }

  $('sd-save').addEventListener('click', function(){
    if (!LIVE) return alert('静态预览模式不可写：请以 admin-server 启动后操作。');
    fetch('/api/site-data', { method:'POST', headers:{'Content-Type':'text/plain'}, body: $('sd-editor').value })
      .then(function(r){ return r.json(); })
      .then(function(j){ alert(j.ok ? '已保存 site-data.jsonc，记得点「重建站点」' : ('保存失败：' + j.error)); });
  });
  $('sd-reload').addEventListener('click', function(){
    fetch('/api/site-data').then(function(r){ return r.json(); }).then(function(d){ if (d.ok) $('sd-editor').value = d.content; });
  });
  $('rb-btn').addEventListener('click', function(){
    if (!LIVE) return alert('静态预览模式不可重建：请以 admin-server 启动后操作。');
    $('rb-btn').disabled = true; $('rb-out').style.display = ''; $('rb-out').textContent = '重建中…';
    api('/api/rebuild').then(function(j){
      $('rb-out').textContent = (j.ok ? '✓ 重建完成\\n' : '✗ 重建失败\\n') + (j.tail||'');
    }).catch(function(e){ $('rb-out').textContent = '✗ ' + e.message; })
      .finally(function(){ $('rb-btn').disabled = false; });
  });

  renderTables(window.__ADMIN_FALLBACK__ || { groups: [], history: [] });
  load();
})();
`;

/* ---------------------------------------------------------------- main */
const GEN_AT_ISO = new Date().toISOString();
const GEN_AT = GEN_AT_ISO.slice(0, 10);
let DOC_MAP = {};
let DOC_CLASSES_BY_ANCHOR = {};

function main() {
  if (!fs.existsSync(SRC_ROOT)) {
    console.error('[docs-web] 源目录不存在: ' + SRC_ROOT);
    process.exit(1);
  }
  console.log('[docs-web] src = ' + SRC_ROOT);
  console.log('[docs-web] out = ' + OUT_ROOT);

  if (ARGS.clean && fs.existsSync(OUT_ROOT)) fs.rmSync(OUT_ROOT, { recursive: true, force: true });
  fs.mkdirSync(OUT_ROOT, { recursive: true });

  // 1. 解析全部 md
  const srcFiles = walkMd(SRC_ROOT);
  const docs = srcFiles.map((rel) => buildDoc(rel, DOC_MAP));
  DOC_MAP = {};
  for (const d of docs) DOC_MAP[d.srcRel] = d.outRel;
  // 二次填充（链接解析需要 docMap；doc._render 需 class 表）
  DOC_CLASSES_BY_ANCHOR = {};
  for (const d of docs) for (const c of d.classes) DOC_CLASSES_BY_ANCHOR[d.srcRel + '#' + c.anchor] = c;
  const reParsed = srcFiles.map((rel) => buildDoc(rel, DOC_MAP));
  reParsed.forEach((d, i) => { d.outRel = docs[i].outRel; });

  // 版本扫描（分开管理：本体 / VSCode / 插件 / 包）
  const versions = scanVersions();
  const coreVer = (versions.groups[0].items.find((x) => x.key === 'front') || {}).version || '?';
  const vscodeGrp = versions.groups.find((g) => g.key === 'vscode');
  const vscodeVer = vscodeGrp && vscodeGrp.items[0] ? vscodeGrp.items[0].version : '?';
  FOOTER_VERSIONS = '本体 v' + coreVer + ' · VSCode v' + vscodeVer;
  ADMIN_VERSION_GROUPS = versions.groups;

  // 2. 分组
  const PREFERRED = ['Core', 'HttpServer', 'Math', 'Std', 'WebUI'];
  const groupNames = [...new Set(reParsed.map((d) => d.group))];
  groupNames.sort((a, b) => {
    const ia = PREFERRED.indexOf(a), ib = PREFERRED.indexOf(b);
    if (ia >= 0 && ib >= 0) return ia - ib;
    if (ia >= 0) return -1;
    if (ib >= 0) return 1;
    if (a === '') return 1;
    if (b === '') return -1;
    return a.localeCompare(b);
  });
  const groups = groupNames.map((name) => {
    const gdocs = reParsed.filter((d) => d.group === name);
    const readme = gdocs.find((d) => /(^|\/)README\.md$/i.test(d.srcRel));
    return {
      name,
      label: name || '根目录',
      path: name ? 'md/lib/' + name : 'md/lib',
      readme: readme ? readme.outRel : null,
      docs: gdocs.length,
      clsCount: gdocs.reduce((n, d) => n + d.classes.length, 0),
    };
  });

  // 3. 输出文档页
  for (const d of reParsed) {
    const file = path.join(OUT_ROOT, d.outRel.replace(/\//g, path.sep));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, renderDocPage(d), 'utf8');
  }

  // 4. 索引 JSON + API 页 + 首页 + CSS
  const indexJson = buildIndexJson(groups, reParsed);
  indexJson.versions = versions; // 分组件版本（本体/VSCode/插件/包），后管与官网消费
  writeUtf8(path.join(OUT_ROOT, 'api', 'index.json'), JSON.stringify(indexJson, null, 1));
  const classes = indexJson.classes.map((c) => {
    c.group = c.group;
    return c;
  });
  const clsWithMembers = reParsed.flatMap((d) => d.classes).sort((a, b) =>
    a.group.localeCompare(b.group) || a.module.localeCompare(b.module) || a.name.localeCompare(b.name));
  writeUtf8(path.join(OUT_ROOT, 'api', 'index.html'), renderApiPage(groups, clsWithMembers));
  writeUtf8(path.join(OUT_ROOT, 'index.html'), renderHome(groups, reParsed, indexJson.stats));
  writeUtf8(path.join(OUT_ROOT, 'getting-started.html'), renderGettingStarted());
  writeUtf8(path.join(OUT_ROOT, 'examples.html'), renderExamples());
  writeUtf8(path.join(OUT_ROOT, 'about.html'), renderAbout());
  writeUtf8(path.join(OUT_ROOT, 'admin.html'), renderAdmin());
  writeUtf8(path.join(OUT_ROOT, 'assets', 'style.css'), CSS);

  console.log('[docs-web] 完成：' + indexJson.stats.docs + ' 篇文档 · ' + indexJson.stats.groups +
    ' 个分组 · ' + indexJson.stats.classes + ' 个类/枚举 · ' + indexJson.stats.members + ' 个成员');
  console.log('[docs-web] 站点入口 ' + toPosix(path.join(OUT_ROOT, 'index.html')));
  console.log('[docs-web] 入门页   ' + toPosix(path.join(OUT_ROOT, 'getting-started.html')));
  console.log('[docs-web] 示例库   ' + toPosix(path.join(OUT_ROOT, 'examples.html')));
  console.log('[docs-web] 关于页   ' + toPosix(path.join(OUT_ROOT, 'about.html')));
  console.log('[docs-web] 后管     ' + toPosix(path.join(OUT_ROOT, 'admin.html')) + '（可写模式：node tools/docs-web/admin-server.js 8932）');
  console.log('[docs-web] API 索引 ' + toPosix(path.join(OUT_ROOT, 'api', 'index.html')));
  console.log('[docs-web] 索引文件 ' + toPosix(path.join(OUT_ROOT, 'api', 'index.json')));
}

function writeUtf8(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content, 'utf8');
}

main();
