// Shared harness: serves the repo files + the Rive WASM runtime and runs code in headless Chrome.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const rt = path.join(here, 'node_modules/@rive-app/canvas-advanced');

export async function withBrowser(rivPath, fn) {
  const riv = fs.readFileSync(rivPath);
  const server = http.createServer((req, res) => {
    const u = req.url.split('?')[0];
    const send = (buf, type) => { res.writeHead(200, { 'content-type': type }); res.end(buf); };
    if (u === '/') return send('<html><body><canvas id="c" width="512" height="512"></canvas></body></html>', 'text/html');
    if (u === '/file.riv') return send(riv, 'application/octet-stream');
    if (u === '/canvas_advanced.mjs') return send(fs.readFileSync(path.join(rt, 'canvas_advanced.mjs')), 'text/javascript');
    if (u === '/rive.wasm') return send(fs.readFileSync(path.join(rt, 'rive.wasm')), 'application/wasm');
    res.writeHead(404); res.end();
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const browser = await puppeteer.launch({
    executablePath: process.env.CHROME || '/usr/bin/google-chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--use-gl=swiftshader', '--enable-unsafe-swiftshader'],
  });
  try {
    const page = await browser.newPage();
    page.on('console', (m) => process.stderr.write(`[page] ${m.text()}\n`));
    page.on('pageerror', (e) => process.stderr.write(`[pageerror] ${e.message}\n`));
    await page.goto(`http://127.0.0.1:${port}/`);
    await page.evaluate(async () => {
      const mod = await import('/canvas_advanced.mjs');
      window.rive = await mod.default({ locateFile: () => '/rive.wasm' });
      const buf = new Uint8Array(await (await fetch('/file.riv')).arrayBuffer());
      window.file = await window.rive.load(buf);
    });
    return await fn(page);
  } finally {
    await browser.close();
    server.close();
  }
}
