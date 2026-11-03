// 临时脚本：生成 SLangFeatures.jsonc（231 文件整库编译清单），用后即删
'use strict';
const fs = require('fs');
const path = require('path');
const dir = 'd:/project/lang/SlangAllInOne/SLangCore/samples/SLang';
const srcRoot = path.join(dir, 'source');

function walk(d) {
  let out = [];
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = path.join(d, e.name);
    if (e.isDirectory()) out = out.concat(walk(f));
    else if (e.name.endsWith('.sl')) out.push('source/' + path.relative(srcRoot, f).replace(/\\/g, '/'));
  }
  return out;
}

const files = walk(srcRoot).sort();
const body = files.map((f) =>
  '      { "path": "' + f + '", "group": "core", "tag": "base", "ignore": false, "priority": 0 }').join(',\n');

const json = `{
  "project": { "name": "SLangFeatures", "desc": "SLang 自举实验树整库编译工程（231 文件）", "mainVersion": 0, "subVersion": 0, "buildVersion": 1, "buildSubVersion": 0 },
  "source": { "root": "." },
  "compile": { "optimize": false, "target": "x64", "debug": true, "isUseForceSemiColonInLineEnd": false, "isForceUseClassKey": false, "isSupportDoublePlus": false, "requireSameNumericTypes": false },
  "compileFiles": {
    "files": [
${body}
    ]
  },
  "global": { "imports": [], "data": {} },
  "references": [
    { "path": "../../../out/export/Core/Core.module.slb" },
    { "path": "../../../out/export/Std/Std.module.slb" }
  ]
}
`;

fs.writeFileSync(path.join(dir, 'SLangFeatures.jsonc'), json, 'utf8');
JSON.parse(json.replace(/,(\s*[}\]])/g, '$1'));
console.log('entries:', files.length);
