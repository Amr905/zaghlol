// Verifies app/assets/rive/zaghlol.riv with the official Rive WASM runtime
// (@rive-app/canvas-advanced) in headless Chrome. Usage: node check.mjs <riv>
// Exit code 0 = every check passed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { withBrowser } from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const riv = process.argv[2];
const meta = JSON.parse(fs.readFileSync(process.env.MOODS_JSON || path.join(here, '../moods.json'), 'utf8'));
const size = fs.statSync(riv).size;

const report = await withBrowser(riv, (page) => page.evaluate((meta) => {
  const R = window.rive;
  const results = [];
  const check = (name, ok, detail = '') => results.push({ name, ok: !!ok, detail });
  const ab0 = window.file.artboardByName('Zaghlol');
  check('artboard "Zaghlol" exists', ab0 != null);
  check('artboard is square', ab0.bounds.maxX - ab0.bounds.minX === ab0.bounds.maxY - ab0.bounds.minY,
    JSON.stringify(ab0.bounds));
  check('one state machine named ZaghlolAvatar', ab0.stateMachineCount() === 1 &&
    ab0.stateMachineByIndex(0).name === 'ZaghlolAvatar');
  {
    const sm = new R.StateMachineInstance(ab0.stateMachineByName('ZaghlolAvatar'), ab0);
    const ins = {};
    for (let i = 0; i < sm.inputCount(); i++) ins[sm.input(i).name] = sm.input(i).type;
    check('inputs state/talk/reduceMotion with exact types',
      sm.inputCount() === 3 && ins.state === R.SMIInput.number && ins.talk === R.SMIInput.bool &&
      ins.reduceMotion === R.SMIInput.bool, JSON.stringify(ins));
    sm.delete();
  }
  ab0.delete();

  const DT = 1 / 120;
  const NODEPROPS = ['x', 'y', 'rotation', 'scaleX', 'scaleY'];
  function session() {
    const ab = window.file.artboardByName('Zaghlol');
    const sm = new R.StateMachineInstance(ab.stateMachineByName('ZaghlolAvatar'), ab);
    const inp = {};
    for (let i = 0; i < sm.inputCount(); i++) inp[sm.input(i).name] = sm.input(i);
    const s = {
      ab, sm, names: [], ext: {},
      set(n, v) { (typeof v === 'boolean' ? inp[n].asBool() : inp[n].asNumber()).value = v; },
      run(sec) {
        for (let t = 0; t < sec - 1e-9; t += DT) {
          sm.advanceAndApply(DT);
          for (let i = 0; i < sm.stateChangedCount(); i++) s.names.push(sm.stateChangedNameByIndex(i));
          for (const nodeName of Object.keys(meta.rest)) {
            const nd = ab.node(nodeName);
            for (const p of Object.keys(meta.rest[nodeName])) {
              const k = nodeName + '.' + p;
              const v = nd[p];
              const e = s.ext[k] || (s.ext[k] = { min: v, max: v, last: v });
              e.min = Math.min(e.min, v); e.max = Math.max(e.max, v); e.last = v;
            }
          }
        }
      },
      val(nodeName, p) { return ab.node(nodeName)[p]; },
      resetExt() { s.ext = {}; s.names = []; },
      done() { sm.delete(); ab.delete(); },
    };
    return s;
  }
  const moods = meta.animations.filter((a) => a.state !== undefined);
  const near = (v, target, rest) => Math.abs(v - target) <= 0.1 * Math.abs(target - rest) + 0.02;
  function reached(s, probe) {
    const e = s.ext[probe.node + '.' + probe.prop];
    const rest = meta.rest[probe.node][probe.prop];
    const obs = Math.abs(e.max - rest) > Math.abs(e.min - rest) ? e.max : e.min;
    return { ok: near(obs, probe.extreme, rest), obs, want: probe.extreme };
  }

  // 1. Every state value from a fresh start reaches its animation and keyed pose.
  for (const m of moods) {
    const s = session();
    s.run(0.05);
    s.set('state', m.state);
    s.resetExt();
    s.run(m.duration + 1.0);
    const hasAnim = s.names.includes(m.name);
    const bad = m.probes.map((p) => reached(s, p)).filter((r) => !r.ok);
    check(`state=${m.state} plays ${m.name} and hits its keyed poses`, hasAnim && bad.length === 0,
      `names=${[...new Set(s.names)].join(',')} bad=${JSON.stringify(bad)}`);
    // one-offs (and not the held pull) go back to the idle pose; loops keep looping.
    if (m.loop === 'oneShot') {
      const rest = meta.rest.character;
      const settled = Math.abs(s.val('character', 'y') - rest.y) < 3 && Math.abs(s.val('character', 'x') - rest.x) < 1 &&
        Math.abs(s.val('character', 'rotation')) < 0.03;
      check(`state=${m.state} one-off returns to idle and stays there`, settled && !s.names.slice(
        s.names.lastIndexOf('idle') + 1).includes(m.name), `names=${s.names.join(',')}`);
    } else if (m.loop === 'loop') {
      s.resetExt();
      s.run(m.duration * 1.5);
      const e = s.ext['character.rotation'], f = s.ext['face.x'], y = s.ext['face.y'];
      check(`state=${m.state} loops while the input stays`, (m.probes.some((p) => {
        const x = s.ext[p.node + '.' + p.prop]; return x && Math.abs(x.max - x.min) > 1e-4;
      })), 'still animating after one full cycle');
    } else {
      check(`state=${m.state} holds its pose (pull)`, reached(s, m.probes[0]).ok);
    }
    s.done();
  }

  // 2. Every ordered pair a -> b switches to b (interrupts one-offs/loops, replays after another value).
  let pairFails = [];
  for (const a of moods) {
    for (const b of moods) {
      if (a.state === b.state) continue;
      const s = session();
      s.set('state', a.state); s.run(0.4);
      s.set('state', b.state); s.resetExt(); s.run(0.6);
      if (!s.names.includes(b.name)) pairFails.push(`${a.state}->${b.state}`);
      s.done();
    }
  }
  check('all 210 ordered state switches reach the target mood', pairFails.length === 0, pairFails.join(' '));

  // 3. Replay: 2 -> 5 -> 2 enters mood02 a second time.
  {
    const s = session();
    s.set('state', 2); s.run(1.5); s.set('state', 5); s.run(0.4); s.set('state', 2); s.run(0.4);
    check('replay: state 2, then 5, then 2 plays mood02 again',
      s.names.filter((n) => n === 'mood02_shocked').length === 2, s.names.join(','));
    s.done();
  }
  // 4. Negative state returns to idle (preview default).
  {
    const s = session();
    s.set('state', 5); s.run(0.6); s.set('state', -1); s.resetExt(); s.run(1.0);
    check('state<0 returns a loop mood to idle', s.names.includes('idle'), s.names.join(','));
    s.done();
  }
  // 5. talk true/false.
  {
    const talk = meta.animations.find((a) => a.name === 'talkOn');
    const s = session();
    s.run(0.3);
    check('talk=false leaves the beak at rest', Math.abs(s.val('jaw', 'rotation')) < 1e-3);
    s.set('talk', true); s.resetExt(); s.run(1.2);
    const bad = talk.probes.map((p) => reached(s, p)).filter((r) => !r.ok);
    check('talk=true plays talkOn and moves jaw/beak', s.names.includes('talkOn') && bad.length === 0,
      JSON.stringify({ names: s.names, bad }));
    s.set('talk', false); s.run(0.8);
    check('talk=false closes the beak again', Math.abs(s.val('jaw', 'rotation')) < 0.01 &&
      Math.abs(s.val('beak', 'rotation')) < 0.01, `jaw=${s.val('jaw', 'rotation')}`);
    // talk works together with a mood
    s.set('state', 9); s.set('talk', true); s.resetExt(); s.run(1.0);
    check('talk and a mood play together', s.names.includes('mood09_saved') &&
      Math.abs(s.ext['jaw.rotation'].min) > 0.15, s.names.join(','));
    s.done();
  }
  // 6. reduceMotion holds the rest pose.
  {
    const s = session();
    s.set('reduceMotion', true); s.set('state', 2); s.resetExt(); s.run(1.6);
    const rest = meta.rest.character;
    const dev = Math.max(Math.abs(s.ext['character.y'].min - rest.y), Math.abs(s.ext['character.y'].max - rest.y));
    s.done();
    const t = session();
    t.set('state', 2); t.resetExt(); t.run(1.6);
    const devOn = Math.max(Math.abs(t.ext['character.y'].min - rest.y), Math.abs(t.ext['character.y'].max - rest.y));
    t.done();
    check('reduceMotion=true freezes the pose (shocked jump suppressed)', dev < 1.5 && devOn > 20,
      `dev(reduce)=${dev.toFixed(2)} dev(normal)=${devOn.toFixed(2)}`);
  }
  return results;
}, meta));

let failed = 0;
for (const r of report) {
  if (!r.ok) failed++;
  console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name}${r.ok ? '' : '  -> ' + r.detail}`);
}
const sizeOk = size <= 500 * 1024;
console.log(`${sizeOk ? 'PASS' : 'FAIL'}  file size ${size} bytes <= 512000`);
if (!sizeOk) failed++;
console.log(`\n${report.length + 1 - failed}/${report.length + 1} checks passed`);
process.exit(failed ? 1 : 0);
