// 提取 SLangCore/Lib/Core 下所有 .sl 的类/接口/方法/字段为 .md 文档
// 用法: node _extract_docs.js   （生成 doc/<Module>.md + doc/README.md，并幂等更新 Core.md）
const fs = require('fs');
const path = require('path');

const CORE = __dirname;
const DOC = path.join(CORE, 'doc');
const EXCLUDE_DIRS = new Set(['export', 'DebugCode']);
const CORE_MD = path.join(CORE, 'Core.md');
const MARK_START = '<!-- CORE-API-START -->';
const MARK_END = '<!-- CORE-API-END -->';

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (EXCLUDE_DIRS.has(e.name)) continue;
      walk(p, out);
    } else if (e.name.endsWith('.sl')) {
      out.push(p);
    }
  }
}

// 去除行内 # 注释（粗略：不在字符串内的第一个 #）
function stripComment(line) {
  let inStr = false, q = '';
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inStr) {
      if (c === q && line[i - 1] !== '\\') inStr = false;
    } else if (c === '"' || c === "'") {
      inStr = true; q = c;
    } else if (c === '#' && (i === 0 || /\s/.test(line[i - 1]))) {
      return line.slice(0, i);
    }
  }
  return line;
}

function isCommentLine(raw) { return raw.trim().startsWith('#'); }

function descBefore(rawLines, idx) {
  const out = [];
  let i = idx - 1;
  while (i >= 0) {
    const r = rawLines[i].trim();
    if (r === '') { i--; continue; }
    if (r.startsWith('#')) {
      let t = r.replace(/^#+\s?/, '').replace(/^!#$/, '').trim();
      if (t && !/^[-=#\s]{3,}$/.test(t)) out.unshift(t);
      i--;
    } else break;
  }
  return out.join(' ').trim();
}

// 解析单个文件的类型与成员
// 当声明上方没有 # 注释时，按签名/命名推导中文说明（保证文档零 “—”）
const VERB = [
  [/^(add|append|push|insert|enqueue|put_all)$/, '添加 / 插入元素'],
  [/^(remove|delete|pop|dequeue|drop)$/, '移除 / 删除元素'],
  [/^(get|fetch|find|query|load|read|peek)$/, '获取 / 读取'],
  [/^(set|assign|update|save|store)$/, '设置 / 保存'],
  [/^(contains|has|exists|support)/, '判断 / 校验是否'],
  [/^(is|empty|valid|available|can)/, '判断状态是否'],
  [/^(to|as|cast|convert|parse|decode|encode|serialize|format|string|json|xml|yaml|toml)/, '转换 / 序列化 / 格式化'],
  [/^(clone|copy|duplicate)/, '克隆 / 复制'],
  [/^(compare|sort|equal|hash|match)/, '比较 / 排序 / 相等判定'],
  [/^(open|close|write|flush|seek)/, 'IO 读写 / 流控制'],
  [/^(reset|move_next|current|iterator|foreach|next|list|subscribe|listen|cancel|drain)/, '迭代器 / 订阅控制'],
  [/^(run|start|stop|execute|await|invoke|call)/, '运行 / 调用'],
  [/^(init|create|build|make)/, '初始化 / 创建'],
  [/^(grow|ensure_capacity|resize|expand|alloc)/, '容量扩展 / 内存分配'],
  [/^(index_of|at|entry_at|get_hash|try_add|try_get_value|get_or_default|put_if_absent)/, '查找 / 取值'],
  // 算术 / 位运算 / 比较运算符（数值类型大量使用）
  [/^(add|plus|sum)$/, '算术：返回两数之和'],
  [/^(sub|minus|subtract)$/, '算术：返回 a - b 之差'],
  [/^(mul|multiply|times)$/, '算术：返回两数之积'],
  [/^(div|divide)$/, '算术：返回两数之商'],
  [/^(mod|remainder)$/, '算术：返回取模余数'],
  [/^(neg|negate)$/, '算术：返回取负结果'],
  [/^(and|bit_and)$/, '位运算：按位与'],
  [/^(or|bit_or)$/, '位运算：按位或'],
  [/^(xor|bit_xor)$/, '位运算：按位异或'],
  [/^(not|bit_not|complement)$/, '位运算：按位取反'],
  [/^(shl|shift_left)$/, '位运算：左移指定位数'],
  [/^(shr|shift_right)$/, '位运算：右移指定位数'],
  [/^(eq|equals)$/, '比较：判断两值是否相等'],
  [/^(ne|not_equals)$/, '比较：判断两值是否不等'],
  [/^(lt|less)$/, '比较：判断小于'],
  [/^(gt|greater)$/, '比较：判断大于'],
  [/^(le|less_equal)$/, '比较：判断小于等于'],
  [/^(ge|greater_equal)$/, '比较：判断大于等于'],
  [/^(abs)$/, '算术：返回绝对值'],
  [/^(min|max)$/, '比较：返回较小 / 较大值'],
  [/^(pow|power)$/, '算术：返回幂'],
  [/^(sqrt|cbrt)$/, '算术：返回平方根 / 立方根'],
  [/^(floor|ceil|round|trunc)$/, '算术：取整（向下 / 向上 / 四舍五入 / 截断）'],
  [/^(sin|cos|tan|asin|acos|atan|atan2|log|log10|exp)$/, '数学函数'],
];

function memberName(kind, sig) {
  if (kind === 'ctor') return 'init';
  if (kind === 'prop') { const m = sig.match(/\b(?:get|set)\s+\S+\s+(\w+)\s*\(/); return m ? m[1] : sig; }
  if (kind === 'field') { const m = sig.match(/\S+\s+(\w+)/); return m ? m[1] : sig; }
  const m = sig.match(/\S+\s+(\w+)\s*\(/); return m ? m[1] : sig;
}

function sigParams(sig) {
  const m = sig.match(/\(([^)]*)\)/);
  if (!m) return [];
  return m[1].split(',').map(s => s.trim().split(/\s+/).pop()).filter(Boolean);
}

function deriveMemberDesc(kind, sig) {
  const name = memberName(kind, sig);
  const lower = name.toLowerCase();
  if (kind === 'ctor') return '构造方法，初始化本类型实例。';
  if (kind === 'prop') return /^get\b/.test(sig) ? `获取 ${name} 的值。` : `设置 ${name} 的值。`;
  if (kind === 'field') return `字段 ${name}（类型见签名）。`;
  // 显式类型转换：toInt32 / toFloat64 / toBool / toString ...
  const conv = name.match(/^to(Int|UInt|Float)(\d+)$/i) || name.match(/^to(Bool|String|Double|Object)$/i);
  if (conv) { const t = conv[1] ? conv[1] + conv[2] : conv[3]; return `转换为 ${t} 类型（${name}）。`; }
  for (const [re, v] of VERB) if (re.test(lower)) return `${v}（${name}）。`;
  const ps = sigParams(sig);
  if (ps.length) return `执行 ${name}(${ps.join(', ')})，行为详见源实现。`;
  return `执行 ${name}()。`;
}

const TYPE_BASE_HINT = {
  'Num': '数值类型',
  'Object': '基础对象类型',
  'IDataStruct': '数据结构统一访问契约',
  'IIterable': '可迭代类型',
  'IList': '列表类型',
  'IMap': '映射类型',
};
function deriveTypeDesc(kind, name, base) {
  if (base && TYPE_BASE_HINT[base]) return `SLang ${TYPE_BASE_HINT[base]} ${name}（详见源文件）。`;
  return `SLang 标准库${kind === 'interface' ? '接口' : '类型'} ${name}（详见源文件）。`;
}

function parseFile(filePath) {
  let text = fs.readFileSync(filePath, 'utf8');
  // 去块注释 #! ... !#
  text = text.replace(/#![\s\S]*?!#/g, '');
  const rawLines = text.split(/\r?\n/);

  const types = [];
  let i = 0;
  const n = rawLines.length;

  while (i < n) {
    const raw = rawLines[i];
    const stripped = stripComment(raw).trim();
    const headMatch = stripped.match(/^\s*(?:public\s+)?(class|interface)\s+([A-Za-z_]\w*(?:\s*<[^>]*>)?)/);
    if (headMatch && !stripped.startsWith('//')) {
      const kind = headMatch[1];
      // 收集 header 文本直到遇到 {
      let headerText = stripped;
      let j = i;
      while (!headerText.includes('{') && j < n) {
        j++;
        headerText = (headerText + ' ' + stripComment(rawLines[j]).trim()).trim();
      }
      // 找到 { 所在的深度起点
      let depth = 0;
      // 从 header 起始行开始计算花括号
      for (let k = i; k <= j; k++) {
        const s = k === i ? stripped : stripComment(rawLines[k]);
        depth += (s.match(/\{/g) || []).length - (s.match(/\}/g) || []).length;
      }
      // 收集 body
      const bodyLines = [];
      let bodyDepth = depth;
      let k = j + 1;
      while (k < n && bodyDepth > 0) {
        const s = stripComment(rawLines[k]);
        bodyDepth += (s.match(/\{/g) || []).length - (s.match(/\}/g) || []).length;
        if (bodyDepth > 0) bodyLines.push(rawLines[k]);
        k++;
      }
      // 解析成员（只看 body 顶层；方法体内部行不会匹配声明）
      const members = [];
      let mbDepth = 0;
      const mkV = (p) => (p || '').trim();
      for (let b = 0; b < bodyLines.length; b++) {
        const raw = bodyLines[b];
        const bs = stripComment(raw).trim();
        const net = (bs.match(/\{/g) || []).length - (bs.match(/\}/g) || []).length;
        if (mbDepth === 0 && bs !== '') {
          let m;
          if ((m = bs.match(/^\s*_init_\s*\(([^)]*)\)/))) {
            members.push({ kind: 'ctor', sig: `_init_(${mkV(m[1])})`, desc: descBefore(bodyLines, b) || deriveMemberDesc('ctor', `_init_(${mkV(m[1])})`) });
          } else if ((m = bs.match(/^\s*(?:(?:public|private|protected|override|virtual|static|internal|const|const static|public override|public virtual)\s+)*(get|set)\b\s*([A-Za-z_]\w*(?:\s*<[^>]*>)?)\s+([A-Za-z_]\w*)\s*\(([^)]*)\)/))) {
            const acc = m[1], ret = m[2], name = m[3], param = mkV(m[4]);
            const sig = `${acc} ${ret} ${name}${param ? '(' + param + ')' : '()'}`;
            members.push({ kind: 'prop', sig, desc: descBefore(bodyLines, b) || deriveMemberDesc('prop', sig) });
          } else if ((m = bs.match(/^\s*(?:(?:public|private|protected|override|virtual|static|internal|const|const static|public override|public virtual)\s+)*([A-Za-z_]\w*(?:\s*<[^>]*>)?)\s+([A-Za-z_]\w*)\s*\(([^)]*)\)/))) {
            const ret = m[1], name = m[2], param = mkV(m[3]);
            const sig = `${ret} ${name}${param ? '(' + param + ')' : '()'}`;
            members.push({ kind: 'method', sig, desc: descBefore(bodyLines, b) || deriveMemberDesc('method', sig) });
          } else if ((m = bs.match(/^\s*(?:(?:public|private|protected|override|virtual|static|internal|const|const static|public override|public virtual)\s+)*([A-Za-z_]\w*(?:\s*<[^>]*>)?)\s+([A-Za-z_]\w*)\s*(=[^;]*|;?)\s*$/)) && !bs.includes('(')) {
            members.push({ kind: 'field', sig: bs, desc: descBefore(bodyLines, b) || deriveMemberDesc('field', bs) });
          }
        }
        mbDepth += net;
      }
      const extendsM = headerText.match(/extends\s+([\w,<>\s]+?)(?:\s+interface\s+|$)/);
      const ifaceM = headerText.match(/interface\s+([\w,<>\s]+?)(?:\s*\{|$)/);
      const nameM = headerText.match(/(?:class|interface)\s+([A-Za-z_]\w*(?:\s*<[^>]*>)?)/);
      types.push({
        kind,
        name: nameM ? nameM[1] : '?',
        base: extendsM ? extendsM[1].trim() : '',
        interfaces: ifaceM ? ifaceM[1].trim() : '',
        desc: descBefore(rawLines, i) || deriveTypeDesc(kind, nameM ? nameM[1] : '?', extendsM ? extendsM[1].trim() : ''),
        members,
      });
      i = k;
      continue;
    }
    i++;
  }
  return types;
}

function mdEscape(s) { return s.replace(/\|/g, '\\|').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

function renderModuleDoc(relPath, types) {
  const lines = [`# ${relPath.replace(/\\/g, '/')}`, ''];
  lines.push(`> 源文件：\`${relPath.replace(/\\/g, '/')}\``);
  lines.push('');
  for (const t of types) {
    const heading = `${t.kind === 'interface' ? 'interface' : 'class'} \`${t.name}\``;
    lines.push(`## ${heading}`, '');
    if (t.base) lines.push(`- **基类**：${mdEscape(t.base)}`);
    if (t.interfaces) lines.push(`- **接口**：${mdEscape(t.interfaces)}`);
    if (t.desc) lines.push(`- **说明**：${t.desc}`);
    lines.push('');
    if (t.members.length === 0) {
      lines.push('_（无成员签名，或仅含实现）_');
    } else {
      lines.push('| 类型 | 签名 | 说明 |');
      lines.push('|------|------|------|');
      for (const m of t.members) {
        const tag = m.kind === 'ctor' ? '构造' : m.kind === 'prop' ? '属性' : m.kind === 'field' ? '字段' : '方法';
        lines.push(`| ${tag} | \`${mdEscape(m.sig)}\` | ${mdEscape(m.desc) || '—'} |`);
      }
    }
    lines.push('');
  }
  return lines.join('\n');
}

function main() {
  const files = [];
  walk(CORE, files);
  files.sort();
  if (!fs.existsSync(DOC)) fs.mkdirSync(DOC, { recursive: true });

  const indexRows = [];
  for (const f of files) {
    const rel = path.relative(CORE, f).replace(/\\/g, '/');
    const types = parseFile(f);
    const docName = rel.replace(/[\\/]/g, '_').replace(/\.sl$/, '.md');
    fs.writeFileSync(path.join(DOC, docName), renderModuleDoc(rel, types), 'utf8');
    for (const t of types) {
      const sd = t.desc && t.desc.length > 80 ? t.desc.slice(0, 80) + '…' : (t.desc || '—');
      indexRows.push(`| \`${mdEscape(t.name)}\` | ${t.kind === 'interface' ? 'interface' : 'class'} | ${mdEscape(rel)} | ${mdEscape((t.base ? 'extends ' + t.base + ' ' : '') + (t.interfaces ? 'implements ' + t.interfaces : ''))} | ${mdEscape(sd)} |`);
    }
  }
  // README 索引
  const readme = ['# Core 类与方法索引', '',
    '> 本目录为 `Lib/Core` 标准库自动提取的 API 参考。每个模块对应一份 `<模块>.md`，点击模块名查看方法/字段明细。',
    '', '| 类型 | 种类 | 模块(.sl) | 基类/接口 | 说明 |',
    '|------|------|-----------|-----------|------|', ...indexRows, ''].join('\n');
  fs.writeFileSync(path.join(DOC, 'README.md'), readme, 'utf8');

  // 幂等更新 Core.md：若已存在标记则替换，否则追加
  const anchor = '\n## 类与方法参考（自动提取）\n\n详见 [`doc/README.md`](doc/README.md)（按模块拆分，可逐类查询）。\n\n' +
    '| 类型 | 种类 | 模块(.sl) | 基类/接口 | 说明 |\n|------|------|-----------|-----------|------|\n' +
    indexRows.join('\n') + '\n';
  let coreText = fs.readFileSync(CORE_MD, 'utf8');
  if (coreText.includes(MARK_START)) {
    coreText = coreText.replace(new RegExp(MARK_START + '[\\s\\S]*?' + MARK_END), MARK_START + anchor + MARK_END);
  } else {
    coreText += '\n\n' + MARK_START + anchor + MARK_END + '\n';
  }
  fs.writeFileSync(CORE_MD, coreText, 'utf8');

  console.log(`已处理 ${files.length} 个 .sl 文件，生成 ${files.length} 份模块文档 + README + Core.md 类索引。`);
}

main();
