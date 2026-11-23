// Screenshots the approved Motion Lab (headless Chrome) at the times in shots.json, paused with
// currentTime so every CSS animation (bird and props) is at exactly t.  The Lab's Math.random is
// replaced by mulberry32(SEED), the generator uses the same one.
// Usage: node lab_capture.mjs <outDir>  ->  <outDir>/<mood>_<ms>.png (760x800, the live stage)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const lab = path.resolve(here, '../../../docs/02-design/motion/zaghlol-motion.html');
const outDir = process.argv[2];
fs.mkdirSync(outDir, { recursive: true });
const shotsDef = JSON.parse(fs.readFileSync(path.join(here, 'shots.json'), 'utf8'));
const SEED = 20261123;
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME || '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1200, height: 900, deviceScaleFactor: 2 });
await page.evaluateOnNewDocument(() => { window.setInterval = () => 0; });
await page.goto('file://' + lab);
await page.addStyleTag({ content: `
  .stage{background:#D4F4E4 !important} .say,.hint{display:none !important}
  .zg .jaw{animation:none !important}` });
const live = await page.$('#live');
for (const [mood, times] of Object.entries(shotsDef)) {
  for (const t of times) {
    await page.evaluate((mood, SEED) => {
      let a = SEED;
      Math.random = () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
      const stage = document.querySelector('#live');
      const svg = stage.querySelector('svg.zg');
      if (mood === 'idle') {
        svg.setAttribute('class', 'zg'); stage.querySelector('.fx').innerHTML = '';
      } else {
        choose(M.find((m) => m.id === mood));
      }
    }, mood, SEED);
    await page.evaluate((t) => {
      void document.body.getBoundingClientRect();
      for (const an of document.querySelector('#live').getAnimations({ subtree: true })) {
        an.pause(); an.currentTime = t * 1000;
      }
    }, t);
    await live.screenshot({ path: path.join(outDir, `${mood}_${Math.round(t * 1000)}.png`) });
  }
}
await browser.close();
console.log('captured', outDir);
