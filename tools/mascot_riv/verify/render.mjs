// Renders contact-sheet frames with the official WASM runtime. Usage: node render.mjs <riv> <outDir>
// Writes <outDir>/<name>.png for idle, every mood (at its peak) and talk-open.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { withBrowser } from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const [riv, outDir] = process.argv.slice(2);
const meta = JSON.parse(fs.readFileSync(path.join(here, '../moods.json'), 'utf8'));
fs.mkdirSync(outDir, { recursive: true });

// Capture times (seconds after setting the input) chosen to show each pose clearly.
// Pose to show per mood (seconds); default = time of its biggest keyed pose.
const PEAK = { mood14_tap: 0.35, mood10_payday: 0.25, mood03_detective: 1.0 };
const shots = [
  { name: 'idle', state: -1, t: 0.3 },
  ...meta.animations.filter((a) => a.state !== undefined).map((a) => ({
    name: a.name, state: a.state, t: PEAK[a.name] ?? Math.min(a.probes[0].t, a.duration),
  })),
  { name: 'talk', state: -1, talk: true, t: 0.12 + 0.2 },
  { name: 'reduceMotion', state: 2, reduce: true, t: 0.5 },
];
const size = 600;
const results = await withBrowser(riv, (page) => page.evaluate(async (shots, size) => {
  const out = {};
  const canvas = document.getElementById('c');
  canvas.width = size; canvas.height = size;
  for (const s of shots) {
    const ab = window.file.artboardByName('Zaghlol');
    const sm = new window.rive.StateMachineInstance(ab.stateMachineByName('ZaghlolAvatar'), ab);
    const inp = {};
    for (let i = 0; i < sm.inputCount(); i++) inp[sm.input(i).name] = sm.input(i);
    inp.state.asNumber().value = s.state;
    if (s.talk) inp.talk.asBool().value = true;
    if (s.reduce) inp.reduceMotion.asBool().value = true;
    const dt = 1 / 120;
    sm.advanceAndApply(0.001);
    for (let t = 0; t < s.t; t += dt) sm.advanceAndApply(dt);
    ab.advance(0);
    const renderer = window.rive.makeRenderer(canvas);
    await new Promise((res) => window.rive.requestAnimationFrame(() => {
      renderer.clear();
      renderer.save();
      renderer.align(window.rive.Fit.contain, window.rive.Alignment.center,
        { minX: 0, minY: 0, maxX: size, maxY: size }, ab.bounds);
      ab.draw(renderer);
      renderer.restore();
      res();
    }));
    await new Promise((r) => setTimeout(r, 50));
    out[s.name] = canvas.toDataURL('image/png');
    sm.delete(); ab.delete();
  }
  return out;
}, shots, size));
for (const [name, url] of Object.entries(results)) {
  fs.writeFileSync(path.join(outDir, `${name}.png`), Buffer.from(url.split(',')[1], 'base64'));
}
console.log(`rendered ${Object.keys(results).length} frames to ${outDir}`);
