// Verifies app/assets/rive/zaghlol.riv with the official Rive WASM runtime
// (@rive-app/canvas-advanced) in headless Chrome. Usage: node check.mjs <riv>
// Compares every state against expectations.json (derived from the Motion Lab by lab_expect.py).
// Exit code 0 = every check passed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { withBrowser } from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const riv = process.argv[2];
const meta = JSON.parse(fs.readFileSync(path.join(here, '../moods.json'), 'utf8'));
const exp = JSON.parse(fs.readFileSync(path.join(here, 'expectations.json'), 'utf8'));
const size = fs.statSync(riv).size;

const report = await withBrowser(riv, (page) => page.evaluate((meta, exp) => {
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
  const COMPS = ['x', 'y', 'rotation', 'scaleX', 'scaleY'];
  const REST = { x: null, y: null, rotation: 0, scaleX: 1, scaleY: 1 };
  const restOf = (n, c) => (c === 'x' || c === 'y') ? exp.rest[n][c] : REST[c];
  const watched = Object.keys(exp.rest);
  function session() {
    const ab = window.file.artboardByName('Zaghlol');
    const sm = new R.StateMachineInstance(ab.stateMachineByName('ZaghlolAvatar'), ab);
    const inp = {};
    for (let i = 0; i < sm.inputCount(); i++) inp[sm.input(i).name] = sm.input(i);
    const nodes = {};
    for (const n of watched) if (n !== 'stage' && n !== 'fx') nodes[n] = ab.node(n);
    const s = {
      ab, sm, names: [], ext: {},
      set(n, v) { (typeof v === 'boolean' ? inp[n].asBool() : inp[n].asNumber()).value = v; },
      run(sec) {
        for (let t = 0; t < sec - 1e-9; t += DT) {
          sm.advanceAndApply(DT);
          for (let i = 0; i < sm.stateChangedCount(); i++) s.names.push(sm.stateChangedNameByIndex(i));
          for (const n in nodes) {
            for (const c of COMPS) {
              const k = n + '.' + c;
              const v = nodes[n][c];
              const e = s.ext[k] || (s.ext[k] = { min: v, max: v, last: v });
              if (v < e.min) e.min = v;
              if (v > e.max) e.max = v;
              e.last = v;
            }
          }
        }
      },
      val(n, c) { return nodes[n][c]; },
      resetExt() { s.ext = {}; s.names = []; },
      done() { sm.delete(); ab.delete(); },
    };
    return s;
  }
  const tolFor = (c, range) => 0.03 * range + (c === 'x' || c === 'y' ? 0.6 : c === 'rotation' ? 0.01 : 0.005);

  // Compare observed sweeps with the Lab's (rest is always visited: the mood mixes in and out).
  function compare(s, ranges, label) {
    const bad = [];
    for (const [n, comps] of Object.entries(ranges)) {
      for (const c of COMPS) {
        const [lo0, hi0] = comps[c];
        const r = restOf(n, c);
        const lo = Math.min(lo0, r), hi = Math.max(hi0, r);
        const e = s.ext[n + '.' + c];
        if (!e) { bad.push(`${n}.${c} not observed`); continue; }
        const tol = tolFor(c, hi - lo);
        if (Math.abs(e.min - lo) > tol || Math.abs(e.max - hi) > tol) {
          bad.push(`${n}.${c} want [${lo.toFixed(3)},${hi.toFixed(3)}] got [${e.min.toFixed(3)},${e.max.toFixed(3)}]`);
        }
      }
    }
    return bad;
  }

  const states = Object.entries(exp.states).map(([k, v]) => ({ state: +k, ...v }));
  const animName = (st) => `mood${String(st.state).padStart(2, '0')}_${st.name}`;
  const fxName = (st) => `fx${String(st.state).padStart(2, '0')}_${st.name}`;
  const bodyNodes = ['bird', 'head', 'wingL', 'brows', 'pupilsL', 'pupilsR', 'eyeL', 'eyeR', 'wingL'];

  // 1. Every state from a fresh start: its animations play and every part sweeps the Lab's range.
  for (const st of states) {
    const s = session();
    s.run(0.05);
    s.set('state', st.state);
    s.resetExt();
    const horizon = Math.max(st.D, st.fxD || 0) + (st.kind === 'oneShot' ? 1.0 : 0.2);
    s.run(horizon);
    const ranges = { ...st.nodes, ...st.fx };
    const bad = compare(s, ranges, st.lab);
    const hasAnim = s.names.includes(animName(st)) && (st.fxD === null || s.names.includes(fxName(st)));
    check(`state=${st.state} ${st.lab}: plays ${animName(st)}${st.fxD ? ' + props' : ''}`, hasAnim, s.names.join(','));
    check(`state=${st.state} ${st.lab}: every part sweeps the Lab's range (${Object.keys(ranges).length} nodes)`,
      bad.length === 0, bad.slice(0, 6).join('; '));
    if (st.kind === 'oneShot') {
      let settled = true;
      for (const n of bodyNodes) {
        for (const c of COMPS) {
          const r = restOf(n, c);
          if (Math.abs(s.val(n, c) - r) > tolFor(c, 1) * 3) settled = false;
        }
      }
      check(`state=${st.state} ${st.lab}: one-off returns to idle and stays there`,
        settled && s.names.lastIndexOf('idle') > s.names.lastIndexOf(animName(st)), s.names.join(','));
    } else if (st.kind === 'loop') {
      s.resetExt();
      s.run(st.D * 1.5);
      const moving = Object.keys(st.nodes).concat(Object.keys(st.fx)).some((n) => {
        const e = s.ext[n + '.y'], x = s.ext[n + '.x'], r = s.ext[n + '.rotation'], q = s.ext[n + '.scaleY'];
        return [e, x, r, q].some((v) => v && v.max - v.min > 1e-4);
      });
      check(`state=${st.state} ${st.lab}: loops while the input stays`, moving && !s.names.includes('idle'),
        s.names.join(','));
    } else {
      const before = s.val('head', 'y');
      s.run(3);
      check(`state=${st.state} ${st.lab}: holds still after its two breaths`,
        Math.abs(s.val('head', 'y') - before) < 0.01 && !s.names.slice(1).includes('idle'), s.names.join(','));
    }
    s.done();
  }

  // 2. Every ordered pair a -> b switches to b (interrupts one-offs/loops, replays after another value).
  const moods = states.map((s) => s.state);
  let pairFails = [];
  for (const a of moods) {
    for (const b of moods) {
      if (a === b) continue;
      const s = session();
      s.set('state', a); s.run(0.4);
      s.set('state', b); s.resetExt(); s.run(0.6);
      if (!s.names.includes(animName(states[b]))) pairFails.push(`${a}->${b}`);
      s.done();
    }
  }
  check('all 210 ordered state switches reach the target mood', pairFails.length === 0, pairFails.join(' '));

  // 3. Replay: 2 -> 5 -> 2 enters mood02 a second time.
  {
    const s = session();
    s.set('state', 2); s.run(1.5); s.set('state', 5); s.run(0.4); s.set('state', 2); s.run(0.4);
    check('replay: state 2, then 5, then 2 plays mood02 again',
      s.names.filter((n) => n === animName(states[2])).length === 2, s.names.join(','));
    s.done();
  }
  // 4. Negative state returns to idle (preview default), props too.
  {
    const s = session();
    s.set('state', 6); s.run(0.6); s.set('state', -1); s.resetExt(); s.run(1.0);
    check('state<0 returns a loop mood to idle (body and props)', s.names.includes('idle') && s.names.includes('idleFx'),
      s.names.join(','));
    s.done();
  }
  // 5. ambient layers (breathe, wag, blink) run in idle with the Lab's amplitudes.
  {
    const s = session();
    s.run(9.0);
    const bad = [];
    const a = exp.ambient;
    const want = [['breath.scaleX', a.breath.scaleX], ['breath.scaleY', a.breath.scaleY], ['tail.rotation', a.tail.rotation],
      ['blinkL.scaleY', a.blinkScaleY], ['blinkR.scaleY', a.blinkScaleY],
      ['blinkHappyL.scaleY', a.blinkScaleY], ['blinkHappyR.scaleY', a.blinkScaleY]];
    for (const [k, [lo, hi]] of want) {
      const e = s.ext[k];
      if (!e || Math.abs(e.min - lo) > 0.01 || Math.abs(e.max - hi) > 0.01) bad.push(`${k} want [${lo},${hi}] got ${e ? e.min.toFixed(3) + ',' + e.max.toFixed(3) : 'n/a'}`);
    }
    check('idle breathes, wags and blinks with the Lab amplitudes', bad.length === 0, bad.join('; '));
    s.done();
  }
  // 6. talk true/false (jaw -8 degrees at .34 s, over any mood).
  {
    const s = session();
    s.run(0.3);
    check('talk=false leaves the jaw closed', Math.abs(s.val('jaw', 'rotation')) < 1e-3);
    s.set('talk', true); s.resetExt(); s.run(1.2);
    const j = s.ext['jaw.rotation'];
    check('talk=true opens the jaw to the Lab angle', s.names.includes('talkOn') && Math.abs(j.min - exp.ambient.jaw.rotation[0]) < 0.01,
      JSON.stringify({ names: s.names, j }));
    s.set('talk', false); s.run(0.8);
    check('talk=false closes the jaw again', Math.abs(s.val('jaw', 'rotation')) < 0.01, `jaw=${s.val('jaw', 'rotation')}`);
    s.set('state', 9); s.set('talk', true); s.resetExt(); s.run(0.8);
    check('talk and a mood play together', s.names.includes(animName(states[9])) && s.ext['jaw.rotation'].min < -0.1);
    s.done();
  }
  // 7. reduceMotion holds the rest pose.
  {
    const s = session();
    s.set('reduceMotion', true); s.set('state', 2); s.resetExt(); s.run(1.2);
    const rest = exp.rest.bird.y;
    const dev = Math.max(Math.abs(s.ext['bird.y'].min - rest), Math.abs(s.ext['bird.y'].max - rest));
    const dx = Math.max(Math.abs(s.ext['bird.x'].min - exp.rest.bird.x), Math.abs(s.ext['bird.x'].max - exp.rest.bird.x));
    s.done();
    check('reduceMotion=true freezes the pose (shake and hop suppressed)', dev < 1.5 && dx < 1.5,
      `dev y=${dev.toFixed(2)} x=${dx.toFixed(2)}`);
  }
  return results;
}, meta, exp));

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
