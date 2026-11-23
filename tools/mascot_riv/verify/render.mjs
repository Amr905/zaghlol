// Renders the Lab's 380x400 stage region of every mood at the times in shots.json with the
// official WASM runtime. Usage: node render.mjs <riv> <outDir>  ->  <outDir>/<mood>_<ms>.png (760x800)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { withBrowser } from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const [riv, outDir] = process.argv.slice(2);
const meta = JSON.parse(fs.readFileSync(path.join(here, '../moods.json'), 'utf8'));
const shotsDef = JSON.parse(fs.readFileSync(path.join(here, 'shots.json'), 'utf8'));
fs.mkdirSync(outDir, { recursive: true });
const order = meta.states.map((s) => s.lab);
const shots = [];
for (const [mood, times] of Object.entries(shotsDef)) {
  for (const t of times) {
    shots.push({ name: `${mood}_${Math.round(t * 1000)}`, state: mood === 'idle' ? -1 : order.indexOf(mood), t });
  }
}
const W = 760, H = 800;
const results = await withBrowser(riv, (page) => page.evaluate(async (shots, crop, W, H) => {
  const out = {};
  const canvas = document.getElementById('c');
  canvas.width = W; canvas.height = H;
  for (const s of shots) {
    const ab = window.file.artboardByName('Zaghlol');
    const sm = new window.rive.StateMachineInstance(ab.stateMachineByName('ZaghlolAvatar'), ab);
    const inp = {};
    for (let i = 0; i < sm.inputCount(); i++) inp[sm.input(i).name] = sm.input(i);
    inp.state.asNumber().value = s.state;
    const dt = 1 / 120;
    sm.advanceAndApply(0.0001);
    for (let t = 0; t < s.t - 1e-9; t += dt) sm.advanceAndApply(dt);
    ab.advance(0);
    const renderer = window.rive.makeRenderer(canvas);
    await new Promise((res) => window.rive.requestAnimationFrame(() => {
      renderer.clear();
      renderer.save();
      renderer.align(window.rive.Fit.fill, window.rive.Alignment.center,
        { minX: 0, minY: 0, maxX: W, maxY: H },
        { minX: crop.x, minY: crop.y, maxX: crop.x + crop.w, maxY: crop.y + crop.h });
      ab.draw(renderer);
      renderer.restore();
      res();
    }));
    await new Promise((r) => setTimeout(r, 30));
    out[s.name] = canvas.toDataURL('image/png');
    sm.delete(); ab.delete();
  }
  return out;
}, shots, meta.crop, W, H));
for (const [name, url] of Object.entries(results)) {
  fs.writeFileSync(path.join(outDir, `${name}.png`), Buffer.from(url.split(',')[1], 'base64'));
}
console.log(`rendered ${Object.keys(results).length} frames to ${outDir}`);
