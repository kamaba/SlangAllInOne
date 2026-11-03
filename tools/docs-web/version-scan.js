/**
 * version-scan.js — 仓库版本锚点扫描 / 写回（共享模块）
 *
 * 版本分开管理（2026-11-03 用户改版，废止旧「四端同步 +1」）：
 *   本体（Front / C VM / 统合宿主）、VSCode 插件、插件（plugin.jsonc）、包（标准库模块 jsonc）
 *   各自独立版本。本模块供 build-docs-web.js（只读展示）与 admin-server.js（读写管理）共用。
 */
'use strict';
const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');

function read(p) { return fs.readFileSync(p, 'utf8'); }
function exists(p) { return fs.existsSync(p); }

function firstMatch(text, re) {
  const m = re.exec(text);
  return m ? m[1] : null;
}

/** 主扫描：返回分组版本表 */
function scanVersions() {
  const groups = [];

  // ── 本体（语言工具链）──
  const coreItems = [];
  const frontFile = path.join(REPO_ROOT, 'simple_language', 'source', 'CLI', 'CommandExecutor.cs');
  if (exists(frontFile)) {
    coreItems.push({ key: 'front', label: 'Front 编译器', version: firstMatch(read(frontFile), /VersionString\s*=\s*"([^"]+)"/), source: 'simple_language/source/CLI/CommandExecutor.cs' });
  }
  const cvmFile = path.join(REPO_ROOT, 'csimple_lang', 'src', 'cli', 'cli_version.h');
  if (exists(cvmFile)) {
    coreItems.push({ key: 'cvm', label: 'C 虚拟机（csimple_lang）', version: firstMatch(read(cvmFile), /SLVM_VERSION_STRING\s+"([^"]+)"/), source: 'csimple_lang/src/cli/cli_version.h' });
  }
  const hostFile = path.join(REPO_ROOT, 'SlangAllInOne', 'SlangAllInOne.csproj');
  if (exists(hostFile)) {
    coreItems.push({ key: 'host', label: '统合宿主（slang）', version: firstMatch(read(hostFile), /<Version>([^<]+)<\/Version>/), source: 'SlangAllInOne/SlangAllInOne.csproj' });
  }
  groups.push({ key: 'core', label: '本体（语言工具链）', items: coreItems });

  // ── VSCode ──
  const vscodeFile = path.join(REPO_ROOT, 'slang_vscode_plugin', 'package.json');
  const vscodeItems = [];
  if (exists(vscodeFile)) {
    vscodeItems.push({ key: 'vscode', label: 'slang-vscode 插件', version: firstMatch(read(vscodeFile), /"version"\s*:\s*"([^"]+)"/), source: 'slang_vscode_plugin/package.json' });
  }
  groups.push({ key: 'vscode', label: 'VSCode', items: vscodeItems });

  // ── 插件（plugin/*/plugin.jsonc → plugin.version）──
  const pluginItems = [];
  const pluginRoot = path.join(REPO_ROOT, 'plugin');
  if (exists(pluginRoot)) {
    for (const dir of fs.readdirSync(pluginRoot, { withFileTypes: true })) {
      if (!dir.isDirectory()) continue;
      const manifest = path.join(pluginRoot, dir.name, 'plugin.jsonc');
      if (!exists(manifest)) continue;
      const text = read(manifest);
      const ver = firstMatch(text, /"version"\s*:\s*"([^"]+)"/);
      const name = firstMatch(text, /"name"\s*:\s*"([^"]+)"/);
      pluginItems.push({ key: 'plugin:' + dir.name, label: dir.name + (name && name !== dir.name ? '（' + name + '）' : ''), version: ver, source: 'plugin/' + dir.name + '/plugin.jsonc' });
    }
    pluginItems.sort((a, b) => a.key.localeCompare(b.key));
  }
  groups.push({ key: 'plugins', label: '插件', items: pluginItems });

  // ── 包（标准库模块 jsonc → project.main.sub.build）──
  const packageItems = [];
  const libRoot = path.join(REPO_ROOT, 'SlangAllInOne', 'SLangCore', 'Lib');
  const walkJsonc = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const f = path.join(d, e.name);
      if (e.isDirectory()) walkJsonc(f);
      else if (e.name.endsWith('.jsonc')) {
        const text = read(f);
        const name = firstMatch(text, /"project"\s*:\s*\{\s*"name"\s*:\s*"([^"]+)"/s);
        const main = firstMatch(text, /"mainVersion"\s*:\s*(\d+)/);
        const sub = firstMatch(text, /"subVersion"\s*:\s*(\d+)/);
        const build = firstMatch(text, /"buildVersion"\s*:\s*(\d+)/);
        if (name && main !== null) {
          packageItems.push({ key: 'package:' + name, label: name + '（' + path.basename(f, '.jsonc') + '）', version: main + '.' + sub + '.' + build, source: 'SlangAllInOne/SLangCore/Lib/' + path.relative(libRoot, f).replace(/\\/g, '/') });
        }
      }
    }
  };
  if (exists(libRoot)) { walkJsonc(libRoot); packageItems.sort((a, b) => a.key.localeCompare(b.key)); }
  groups.push({ key: 'packages', label: '包（标准库模块）', items: packageItems });

  return { scannedAt: new Date().toISOString(), root: REPO_ROOT, groups };
}

/** 写回单个组件版本（admin-server 调用；key = 组内 item.key） */
function writeVersion(key, newVersion) {
  if (!/^\d+\.\d+\.\d+$/.test(newVersion)) throw new Error('版本号格式须为 主.发布.小版本：' + newVersion);
  const [main, sub, build] = newVersion.split('.');
  const current = scanVersions().groups.flatMap((g) => g.items).find((x) => x.key === key);
  if (current && current.version === newVersion) {
    return { key, version: newVersion, file: current.source, unchanged: true };
  }
  let file;
  if (key === 'front') {
    file = path.join(REPO_ROOT, 'simple_language', 'source', 'CLI', 'CommandExecutor.cs');
    replaceInFile(file, /(VersionString\s*=\s*")([^"]+)(")/, (m, g1, g2, g3) => g1 + newVersion + g3);
  } else if (key === 'cvm') {
    file = path.join(REPO_ROOT, 'csimple_lang', 'src', 'cli', 'cli_version.h');
    replaceInFile(file, /(#define SLVM_VERSION_PATCH\s+)(\d+)/, (m, g1) => g1 + parseInt(build, 10));
    replaceInFile(file, /(#define SLVM_VERSION_STRING\s+")[^"]+(")/, (m, g1, g2) => g1 + newVersion + g2);
  } else if (key === 'host') {
    file = path.join(REPO_ROOT, 'SlangAllInOne', 'SlangAllInOne.csproj');
    replaceInFile(file, /(<Version>)[^<]+(<\/Version>)/, (m, g1, g2) => g1 + newVersion + g2);
  } else if (key === 'vscode') {
    file = path.join(REPO_ROOT, 'slang_vscode_plugin', 'package.json');
    replaceInFile(file, /("version"\s*:\s*")([^"]+)(")/, (m, g1, g2, g3) => g1 + newVersion + g3);
    const lock = path.join(REPO_ROOT, 'slang_vscode_plugin', 'package-lock.json');
    if (exists(lock)) {
      let i = 0;
      replaceInFile(lock, /("version"\s*:\s*")([^"]+)(")/g, (m) => (++i <= 2 ? '"version": "' + newVersion + '"' : m));
    }
  } else if (key.startsWith('plugin:')) {
    const id = key.slice('plugin:'.length);
    file = path.join(REPO_ROOT, 'plugin', id, 'plugin.jsonc');
    replaceInFile(file, /("version"\s*:\s*")([^"]+)(")/, (m, g1, g2, g3) => g1 + newVersion + g3);
  } else if (key.startsWith('package:')) {
    if (!current) throw new Error('未找到包：' + key);
    file = path.join(REPO_ROOT, current.source);
    const text = fs.readFileSync(file, 'utf8');
    const next = text
      .replace(/("mainVersion"\s*:\s*)(\d+)/, (m, g1) => g1 + parseInt(main, 10))
      .replace(/("subVersion"\s*:\s*)(\d+)/, (m, g1) => g1 + parseInt(sub, 10))
      .replace(/("buildVersion"\s*:\s*)(\d+)/, (m, g1) => g1 + parseInt(build, 10));
    if (next === text) throw new Error('版本锚点未命中（文件未变化）：' + file);
    fs.writeFileSync(file, next, 'utf8');
  } else {
    throw new Error('未知版本组件：' + key);
  }
  return { key, version: newVersion, file: path.relative(REPO_ROOT, file).replace(/\\/g, '/') };
}

function replaceInFile(file, re, replacement) {
  const text = fs.readFileSync(file, 'utf8');
  const next = text.replace(re, replacement);
  if (next === text) throw new Error('版本锚点未命中（文件未变化）：' + file);
  fs.writeFileSync(file, next, 'utf8');
}

module.exports = { scanVersions, writeVersion, REPO_ROOT };
