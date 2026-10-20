/* SLDP smoke: D-P2 core (step/scopes/variables/var/evaluate/threads/stack)
 * + D-P4a v1.1 (children object/array tree + expression evaluator + handle
 * epoch invalidation + statics identifier + enhanced object summary)
 * + deep-callchain stack view (add/deepC 5+ frames) + scalar full set.
 *
 * Usage (from repo root d:\project\lang):
 *   1. dotnet run --project simple_language\source\SimpleLanguageFront.csproj -- compile -p SlangAllInOne\SLangCore\test\Other\DebugSmoke\DebugSmoke.sp -e ir --format binary+json
 *   2. node SlangAllInOne\SLangCore\test\Other\DebugSmoke\smoke.js
 * Exit code 0 = all checks passed. (DEBUG_PROTOCOL_DESIGN.md §8.2/§8.4)
 *
 * Source layout (DebugSmoke.sl, v1.1 walk-through edition):
 *   63..85: fixtures (a/b/c/pi/flag/msg/pt/arr/pts/box/m/deep)
 *   48: deepC r = add(...)          <- bp #1: stack deepC<-deepB<-deepA<-run (5 frames)
 *   86: int sum = pts[0].x + arr[1] <- bp #2: all locals live (sum null, line-head)
 *   54: coroBody lv = v * 2         <- bp #3: coroutine threadId=3 (AutoInline host)
 *   89: counter = ...               <- bp #4: r=42 counter=10 (store pending)
 *   90: println                     <- bp #5: counter=241 (after store; epoch check)
 * Values: c=triple(7)=21; deep=deepA(5)->deepB(6)->deepC(7)->add(7,100)=107;
 *         sum=41+20=61; r=await coroBody(21)=42; counter=10+21+42+61+107=241
 */
'use strict';

const net = require('net');
const path = require('path');
const { spawn } = require('child_process');

const EXE = 'D:\\project\\lang\\csimple_lang\\build\\Debug\\bin\\csimple_lang.exe';
const BASE = 'D:\\project\\lang\\SlangAllInOne\\SLangCore\\test\\Other\\DebugSmoke';
const MODULE = path.join(BASE, '..', '..', 'out', 'export', 'DebugSmoke',
  'DebugSmoke.module.json');
const SRC = path.join(BASE, 'DebugSmoke.sl');
const PORT = 18110;

let vmStderr = '';
let failed = false;

function fail(msg) {
  console.error('FAIL: ' + msg);
  console.error('--- vm stderr tail ---\n' + vmStderr.split('\n').slice(-15).join('\n'));
  failed = true;
  throw new Error(msg);
}

function ok(msg) { console.log('  ok - ' + msg); }
function assert(cond, msg) { if (!cond) fail(msg); }
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

function connectRetry(port, tries, delayMs) {
  return new Promise((resolve, reject) => {
    const attempt = (n) => {
      const sock = net.connect({ host: '127.0.0.1', port });
      sock.once('connect', () => resolve(sock));
      sock.once('error', () => {
        sock.destroy();
        if (n <= 0) reject(new Error('connect failed after retries; vm stderr:\n' + vmStderr));
        else setTimeout(() => attempt(n - 1), delayMs);
      });
    };
    attempt(tries);
  });
}

class SldpClient {
  constructor(sock) {
    this.sock = sock;
    this.buf = '';
    this.nextId = 1;
    this.pending = new Map();
    this.eventWaiters = [];
    this.closed = false;
    sock.setEncoding('utf8');
    sock.on('data', (d) => this._onData(d));
    sock.on('close', () => { this.closed = true; });
    sock.on('error', () => { this.closed = true; });
  }
  _onData(d) {
    this.buf += d;
    let i;
    while ((i = this.buf.indexOf('\n')) >= 0) {
      let line = this.buf.slice(0, i);
      this.buf = this.buf.slice(i + 1);
      if (line.endsWith('\r')) line = line.slice(0, -1);
      if (!line) continue;
      let msg;
      try { msg = JSON.parse(line); } catch (e) { fail('bad JSON line from vm: ' + line); }
      this._dispatch(msg);
    }
  }
  _dispatch(msg) {
    if (msg && typeof msg.id === 'number' && msg.ok !== undefined) {
      const p = this.pending.get(msg.id);
      if (p) { this.pending.delete(msg.id); p.resolve(msg); }
      else console.log('  (orphan response) ' + JSON.stringify(msg));
      return;
    }
    if (msg && msg.event) {
      for (let k = 0; k < this.eventWaiters.length; ++k) {
        const w = this.eventWaiters[k];
        if (w.name === msg.event && (!w.pred || w.pred(msg.data))) {
          this.eventWaiters.splice(k, 1);
          w.resolve(msg);
          return;
        }
      }
      console.log('  (event) ' + JSON.stringify(msg));
      return;
    }
    console.log('  (other) ' + JSON.stringify(msg));
  }
  send(cmd, args) {
    const id = this.nextId++;
    const obj = { id: id, cmd: cmd };
    if (args !== undefined) obj.args = args;
    this.sock.write(JSON.stringify(obj) + '\n');
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve: resolve });
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error('timeout waiting response for ' + cmd));
        }
      }, 15000);
    });
  }
  expectEvent(name, pred, timeoutMs) {
    return new Promise((resolve, reject) => {
      const w = { name: name, pred: pred, resolve: resolve };
      this.eventWaiters.push(w);
      setTimeout(() => {
        const k = this.eventWaiters.indexOf(w);
        if (k >= 0) { this.eventWaiters.splice(k, 1); reject(new Error('timeout waiting event ' + name)); }
      }, timeoutMs || 20000);
    });
  }
}

async function main() {
  console.log('spawn: ' + EXE + ' run --debug-server=' + PORT + ' --no-banner ' + MODULE);
  const proc = spawn(EXE, ['run', '--debug-server=' + PORT, '--no-banner', MODULE],
    { cwd: path.dirname(MODULE), stdio: ['ignore', 'pipe', 'pipe'] });
  proc.stderr.on('data', (d) => { vmStderr += d.toString('utf8'); });
  proc.stdout.on('data', (d) => { process.stdout.write('[vm-out] ' + d); });
  const exitPromise = new Promise((res) => proc.on('exit', (c) => res(c)));

  await sleep(400);
  const sock = await connectRetry(PORT, 100, 100);
  const cli = new SldpClient(sock);
  console.log('connected');

  /* --- hello + initialize --- */
  await cli.expectEvent('hello');
  ok('hello event');
  let r = await cli.send('initialize', { client: 'smoke' });
  assert(r.ok && r.data.protocol === 1, 'initialize failed: ' + JSON.stringify(r));
  ok('initialize ok (protocol ' + r.data.protocol + ')');

  /* --- breakpoints: 48 (deepC), 86 (sum), 54 (coroBody), 89, 90 --- */
  r = await cli.send('set-breakpoints', { path: SRC, lines: [48, 86, 54, 89, 90] });
  assert(r.ok, 'set-breakpoints failed: ' + JSON.stringify(r));
  const bps = r.data.breakpoints;
  assert(bps.length === 5 && bps.every((b) => b.verified),
    'bps not all verified: ' + JSON.stringify(bps));
  ok('5 breakpoints verified (48/86/54/89/90)');

  /* --- stop #1: deepC:48 (deep call chain) --- */
  let p = cli.expectEvent('stopped');
  r = await cli.send('resume');
  assert(r.ok, 'resume failed');
  let st = await p;
  assert(st.data.reason === 'breakpoint', 'stop1 reason: ' + st.data.reason);
  assert(st.data.line === 48, 'stop1 line: ' + st.data.line + ' (want 48)');
  assert((st.data.method || '').indexOf('deepC') >= 0, 'stop1 method: ' + st.data.method);
  assert(st.data.threadId === 1, 'stop1 threadId: ' + st.data.threadId);
  ok('stop1 deepC:48 breakpoint, threadId=1');

  /* --- stack: deep chain >= 5 frames (deepC<-deepB<-deepA<-run<-entry) --- */
  r = await cli.send('stack');
  const frames1 = r.data.frames;
  assert(frames1.length >= 5, 'deep stack frames >= 5, got ' + frames1.length);
  const names1 = frames1.map((f) => f.method).join('<');
  assert(names1.indexOf('deepC') >= 0 && names1.indexOf('deepB') >= 0
    && names1.indexOf('deepA') >= 0 && names1.indexOf('run') >= 0,
    'deep stack names: ' + names1);
  assert(frames1[0].line === 48, 'deep stack top line: ' + frames1[0].line);
  ok('stack: ' + frames1.length + ' frames (' + names1 + ')');

  /* --- deepC locals/args (n=7 incoming) --- */
  r = await cli.send('variables', { depth: 0, filter: 'args' });
  const dn = r.data.vars.find((v) => v.name === 'n');
  assert(dn && dn.value === '7', 'deepC arg n=7: ' + JSON.stringify(dn));
  ok('deepC args: n=7');

  /* --- step in: deepC -> add (depth grows) --- */
  let depthBefore = frames1.length;
  p = cli.expectEvent('stopped');
  r = await cli.send('step', { kind: 'in' });
  assert(r.ok, 'step in failed');
  st = await p;
  r = await cli.send('stack');
  assert(r.data.frames.length > depthBefore,
    'stepIn frames: ' + r.data.frames.length + ' (from ' + depthBefore + ')');
  assert(r.data.frames[0].method.indexOf('add') >= 0,
    'stepIn should land in add, got ' + r.data.frames[0].method);
  ok('stepIn -> ' + r.data.frames[0].method + ':' + r.data.frames[0].line +
    ' (frames ' + depthBefore + '->' + r.data.frames.length + ')');

  /* --- step out: back into deepC --- */
  p = cli.expectEvent('stopped');
  r = await cli.send('step', { kind: 'out' });
  assert(r.ok, 'step out failed');
  st = await p;
  r = await cli.send('stack');
  assert(r.data.frames.length === depthBefore,
    'stepOut frames: ' + r.data.frames.length + ' (want ' + depthBefore + ')');
  assert(r.data.frames[0].method.indexOf('deepC') >= 0,
    'stepOut back in deepC: ' + r.data.frames[0].method);
  ok('stepOut -> ' + r.data.frames[0].method + ':' + r.data.frames[0].line);

  /* --- step over inside deepC (48 -> 49) --- */
  p = cli.expectEvent('stopped');
  r = await cli.send('step', { kind: 'over' });
  assert(r.ok, 'step over failed');
  st = await p;
  assert(st.data.line === 49, 'stepOver line: ' + st.data.line + ' (want 49)');
  ok('stepOver -> deepC:49');

  /* --- scopes/threads basics --- */
  r = await cli.send('scopes', { depth: 0 });
  assert(r.ok && r.data.scopes.length === 3, 'scopes: ' + JSON.stringify(r.data));
  ok('scopes = Locals/Arguments/Statics');
  r = await cli.send('threads');
  assert(r.ok && r.data.threads.length === 1 && r.data.threads[0].id === 1,
    'threads should be [main]: ' + JSON.stringify(r.data));
  ok('threads = [main]');

  /* --- stop #2: run:86 (all fixtures live; sum null line-head) --- */
  p = cli.expectEvent('stopped');
  r = await cli.send('resume');
  assert(r.ok, 'resume failed');
  st = await p;
  assert(st.data.reason === 'breakpoint' && st.data.line === 86 && st.data.threadId === 1,
    'run:86 stop: ' + JSON.stringify(st.data));
  ok('stop2 at run:86 (fixtures live)');

  /* --- variables: scalar full set + statics --- */
  r = await cli.send('variables', { depth: 0, filter: 'locals' });
  const V = r.data.vars;
  const va = V.find((v) => v.name === 'a');
  const vb = V.find((v) => v.name === 'b');
  const vpi = V.find((v) => v.name === 'pi');
  const vflag = V.find((v) => v.name === 'flag');
  const vmsg = V.find((v) => v.name === 'msg');
  const vdeep = V.find((v) => v.name === 'deep');
  const vsum = V.find((v) => v.name === 'sum');
  assert(va && va.value === '3' && va.type === 'i32', 'local a: ' + JSON.stringify(va));
  assert(vb && vb.value === '4', 'local b: ' + JSON.stringify(vb));
  assert(vpi && vpi.type === 'f64' && vpi.value === '3.14', 'local pi: ' + JSON.stringify(vpi));
  assert(vflag && vflag.value === '1', 'local flag: ' + JSON.stringify(vflag));
  assert(vmsg && (vmsg.text || '').indexOf('"hi"') >= 0, 'local msg: ' + JSON.stringify(vmsg));
  assert(vdeep && vdeep.value === '107', 'local deep=107: ' + JSON.stringify(vdeep));
  assert(vsum && vsum.value === 'null', 'local sum should be null (line 86 not run): ' + JSON.stringify(vsum));
  ok('locals scalars: a=3 b=4 pi=f64:3.14 flag=1 msg="hi" deep=107 sum=null');
  r = await cli.send('variables', { depth: 0, filter: 'statics' });
  const vc = r.data.vars.find((v) => v.name === 'counter');
  const vn = r.data.vars.find((v) => v.name === 'note');
  assert(vc && vc.value === '10', 'static counter: ' + JSON.stringify(r.data.vars));
  /* note（static string）呈现 str:null：静态初始化表达式按
   * static_member_expr_applied 守卫尚未应用（int 字面量 counter
   * 装配期内联故有值）——准确语义，非 bug（D-P2 §6.5 注） */
  assert(vn && vn.type === 'str', 'static note: ' + JSON.stringify(vn));
  ok('statics counter=10 note=str(初始化未应用呈 null)');

  /* --- var / evaluate (expression engine) --- */
  r = await cli.send('var', { depth: 0, name: 'a' });
  assert(r.ok && r.data.found === true && r.data.value === '3' && r.data.type === 'i32',
    'var a: ' + JSON.stringify(r.data));
  ok('var a -> found i32:3');
  r = await cli.send('evaluate', { depth: 0, expr: 'a+b' });
  assert(r.ok === true && r.data.found === true && r.data.value === '7',
    'evaluate a+b: ' + JSON.stringify(r));
  ok('evaluate a+b -> 7 (v1.1 expression engine)');
  r = await cli.send('evaluate', { depth: 0, expr: '1+2*3' });
  assert(r.ok === true && r.data.value === '7', 'evaluate 1+2*3: ' + JSON.stringify(r));
  ok('evaluate 1+2*3 -> 7 (precedence)');
  r = await cli.send('evaluate', { depth: 0, expr: 'pi*2' });
  assert(r.ok === true && r.data.value === '6.28', 'evaluate pi*2: ' + JSON.stringify(r));
  ok('evaluate pi*2 -> 6.28 (f64)');
  r = await cli.send('evaluate', { depth: 0, expr: 'counter' });
  assert(r.ok === true && r.data.value === '10', 'evaluate counter: ' + JSON.stringify(r));
  ok('evaluate counter -> 10 (statics domain)');
  r = await cli.send('evaluate', { depth: 0, expr: 'zzz' });
  assert(r.ok === false && /unknown identifier/.test(r.error || ''),
    'evaluate zzz should fail: ' + JSON.stringify(r));
  ok('evaluate zzz -> error (unknown identifier)');

  /* --- children tree: fixtures --- */
  r = await cli.send('variables', { depth: 0, filter: 'locals' });
  const lpt = V.find((v) => v.name === 'pt');
  const larr = V.find((v) => v.name === 'arr');
  const lpts = V.find((v) => v.name === 'pts');
  const lbox = V.find((v) => v.name === 'box');
  const lm = V.find((v) => v.name === 'm');
  assert(lpt && (lpt.ref || 0) > 0 && (lpt.childCount || 0) === 2,
    'pt should be expandable ref with 2 fields: ' + JSON.stringify(lpt));
  assert(lpt.text.indexOf('Point') >= 0 && lpt.text.indexOf('41') >= 0,
    'pt summary: ' + lpt.text);
  assert(larr && (larr.ref || 0) > 0 && larr.childCount === 3,
    'arr expandable len=3: ' + JSON.stringify(larr));
  assert(lpts && (lpts.ref || 0) > 0 && lpts.childCount === 2, 'pts expandable');
  assert(lbox && (lbox.ref || 0) > 0 && (lbox.childCount || 0) >= 3, 'box expandable');
  assert(lm && (lm.ref || 0) > 0, 'map expandable (class): ' + JSON.stringify(lm));
  ok('fixture locals: refs + summaries (pt/arr/pts/box/m expandable)');

  r = await cli.send('children', { ref: lpt.ref });
  assert(r.ok && r.data.vars.length === 2, 'children pt: ' + JSON.stringify(r.data));
  const px = r.data.vars.find((v) => v.name === 'x');
  const py = r.data.vars.find((v) => v.name === 'y');
  assert(px && px.value === '41' && py && py.value === '43', 'pt fields');
  ok('children(pt) -> x=41 y=43');

  r = await cli.send('children', { ref: larr.ref });
  assert(r.ok && r.data.vars.length === 3, 'children arr: ' + JSON.stringify(r.data));
  assert(r.data.vars[0].name === '[0]' && r.data.vars[0].value === '10', 'arr[0]');
  assert(r.data.vars[1].value === '20' && r.data.vars[2].value === '30', 'arr[1..2]');
  ok('children(arr) -> [0]=10 [1]=20 [2]=30 (leaves)');

  r = await cli.send('children', { ref: lpts.ref });
  const pts0 = r.data.vars[0];
  assert(pts0.name === '[0]' && (pts0.ref || 0) > 0, 'pts[0] expandable Point');
  r = await cli.send('children', { ref: pts0.ref });
  const nx = r.data.vars.find((v) => v.name === 'x');
  assert(nx && nx.value === '41', 'nested pts[0].x: ' + JSON.stringify(r.data));
  ok('children(pts)[0] -> Point -> children -> x=41 (depth 3)');

  r = await cli.send('children', { ref: lbox.ref });
  const bp_ = r.data.vars.find((v) => v.name === 'p');
  const bn = r.data.vars.find((v) => v.name === 'nums');
  const bt = r.data.vars.find((v) => v.name === 'tag');
  assert(bp_ && (bp_.ref || 0) > 0, 'box.p expandable');
  assert(bn && (bn.ref || 0) > 0 && bn.childCount === 4, 'box.nums len=4');
  assert(bt && bt.value === '99', 'box.tag=99');
  ok('children(box) -> p(ref) nums(ref,4) tag=99');

  r = await cli.send('children', { ref: lm.ref });
  const ment = r.data.vars.find((v) => v.name === '_entries');
  const mcount = r.data.vars.find((v) => v.name === '_count');
  assert(ment && (ment.ref || 0) > 0, 'map _entries expandable');
  assert(mcount && mcount.value === '2', 'map _count=2');
  r = await cli.send('children', { ref: ment.ref });
  const ent0 = (r.data.vars || [])[0];
  assert(ent0 && (ent0.ref || 0) > 0, 'map entry expandable');
  r = await cli.send('children', { ref: ent0.ref });
  const mkey = r.data.vars.find((v) => v.name === 'key');
  const mval = r.data.vars.find((v) => v.name === 'value');
  const kv = (mkey.value === '1' && mval.value === '100')
    || (mkey.value === '2' && mval.value === '200');
  assert(mkey && mval && kv, 'map entry key/value: ' + JSON.stringify(r.data.vars));
  ok('children(m) -> _entries -> [entry] -> key/value (container graph)');

  /* --- evaluate chains --- */
  r = await cli.send('evaluate', { depth: 0, expr: 'pt.x' });
  assert(r.ok && r.data.value === '41', 'pt.x: ' + JSON.stringify(r));
  ok('evaluate pt.x -> 41');
  r = await cli.send('evaluate', { depth: 0, expr: 'arr[1]' });
  assert(r.ok && r.data.value === '20', 'arr[1]: ' + JSON.stringify(r));
  ok('evaluate arr[1] -> 20');
  r = await cli.send('evaluate', { depth: 0, expr: 'pts[0].y' });
  assert(r.ok && r.data.value === '43', 'pts[0].y: ' + JSON.stringify(r));
  ok('evaluate pts[0].y -> 43');
  r = await cli.send('evaluate', { depth: 0, expr: 'box.tag' });
  assert(r.ok && r.data.value === '99', 'box.tag: ' + JSON.stringify(r));
  ok('evaluate box.tag -> 99');
  r = await cli.send('evaluate', { depth: 0, expr: 'a < b' });
  assert(r.ok && r.data.value === '1', 'a<b: ' + JSON.stringify(r));
  ok('evaluate a<b -> bool:1');
  r = await cli.send('evaluate', { depth: 0, expr: '!(a == 3)' });
  assert(r.ok && r.data.value === '0', '!(a==3): ' + JSON.stringify(r));
  ok('evaluate !(a==3) -> bool:0 (unary)');
  r = await cli.send('evaluate', { depth: 0, expr: '(a + b) * 2' });
  assert(r.ok && r.data.value === '14', '(a+b)*2: ' + JSON.stringify(r));
  ok('evaluate (a+b)*2 -> 14 (parens)');
  r = await cli.send('evaluate', { depth: 0, expr: 'pt.x + arr[1]' });
  assert(r.ok && r.data.value === '61', 'pt.x+arr[1]: ' + JSON.stringify(r));
  ok('evaluate pt.x + arr[1] -> 61 (mixed chain)');
  r = await cli.send('evaluate', { depth: 0, expr: 'arr[5]' });
  assert(r.ok === false && /out of range/.test(r.error || ''), 'arr[5] should fail');
  ok('evaluate arr[5] -> out of range error');
  r = await cli.send('evaluate', { depth: 0, expr: 'pt.zz' });
  assert(r.ok === false, 'pt.zz should fail');
  ok('evaluate pt.zz -> no member error');

  /* --- evaluate result ref: expression -> expandable tree --- */
  r = await cli.send('evaluate', { depth: 0, expr: 'pts' });
  assert(r.ok && r.data.found === true && (r.data.ref || 0) > 0 && r.data.childCount === 2,
    'evaluate pts: ' + JSON.stringify(r.data));
  r = await cli.send('children', { ref: r.data.ref });
  assert(r.ok && r.data.vars.length === 2, 'children(eval pts)');
  ok('evaluate pts -> ref -> children (watch tree)');

  /* --- stop #3: coroBody:54 inside coroutine (threadId=3) --- */
  p = cli.expectEvent('stopped');
  r = await cli.send('resume');
  assert(r.ok, 'resume failed');
  st = await p;
  assert(st.data.reason === 'breakpoint' && st.data.line === 54,
    'coro stop: ' + JSON.stringify(st.data));
  assert(st.data.threadId === 3, 'coro threadId: ' + st.data.threadId + ' (want 3)');
  ok('stop3 inside coroutine:54 on threadId=3');

  r = await cli.send('threads');
  const th = r.data.threads;
  assert(th.length === 2, 'threads during coro: ' + JSON.stringify(th));
  assert(th.some((t) => t.id === 1) && th.some((t) => t.id === 3), 'thread ids 1+3');
  ok('threads = main + coro');

  r = await cli.send('variables', { depth: 0, filter: 'locals' });
  const lv = r.data.vars.find((v) => v.name === 'lv');
  assert(lv && lv.value === 'null', 'coro local lv: ' + JSON.stringify(r.data.vars));
  ok('coro local lv=null (line-head)');

  r = await cli.send('stack');
  assert(r.data.frames.length === 1, 'coro stack frames: ' + r.data.frames.length);
  ok('coro stack = 1 frame (own chain)');

  /* --- stop #4: run:89 (r=42, counter still 10) --- */
  p = cli.expectEvent('stopped');
  r = await cli.send('resume');
  assert(r.ok, 'resume failed');
  st = await p;
  assert(st.data.reason === 'breakpoint' && st.data.line === 89 && st.data.threadId === 1,
    'run:89 stop: ' + JSON.stringify(st.data));
  ok('stop4 at run:89 back on main');

  r = await cli.send('threads');
  const dead = r.data.threads.find((t) => t.id === 3);
  assert(dead && dead.state === 'dead', 'coro dead');
  ok('coro thread state=dead');

  r = await cli.send('variables', { depth: 0, filter: 'locals' });
  const r42 = r.data.vars.find((v) => v.name === 'r');
  assert(r42 && r42.value === '42', 'r=42: ' + JSON.stringify(r42));
  r = await cli.send('variables', { depth: 0, filter: 'statics' });
  const k10 = r.data.vars.find((v) => v.name === 'counter');
  assert(k10 && k10.value === '10', 'counter=10 (store pending)');
  ok('after await: r=42, counter=10');

  /* --- stop #5: run:90 (counter=241 after store) + epoch invalidation --- */
  const staleRef = lpt.ref;
  p = cli.expectEvent('stopped');
  r = await cli.send('resume');
  assert(r.ok, 'resume failed');
  st = await p;
  assert(st.data.line === 90, 'epoch stop line: ' + st.data.line + ' (want 90)');
  r = await cli.send('children', { ref: staleRef });
  assert(r.ok && Array.isArray(r.data.vars) && r.data.vars.length === 0,
    'stale ref should yield empty vars: ' + JSON.stringify(r.data));
  ok('stale ref after resume -> vars:[] (epoch invalidation)');
  r = await cli.send('variables', { depth: 0, filter: 'statics' });
  const k241 = r.data.vars.find((v) => v.name === 'counter');
  assert(k241 && k241.value === '241', 'counter=241 after store: ' + JSON.stringify(k241));
  ok('counter=241 at run:90');

  /* --- final resume -> terminated exitCode 0 --- */
  p = cli.expectEvent('terminated');
  r = await cli.send('resume');
  assert(r.ok, 'resume failed');
  const term = await p;
  assert(term.data.exitCode === 0, 'exitCode: ' + term.data.exitCode);
  const code = await exitPromise;
  assert(code === 0, 'process exit code: ' + code);
  ok('terminated exitCode=0, process exit 0');

  sock.end();
  console.log('\nALL SMOKE CHECKS PASSED (D-P2 core + D-P4a v1.1 + deep stack)');
}

main().then(
  () => { /* done */ },
  (e) => {
    console.error('SMOKE FAILED: ' + (e && e.message ? e.message : e));
    process.exit(1);
  }
);
