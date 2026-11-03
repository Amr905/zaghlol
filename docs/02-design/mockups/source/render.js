const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const dir = path.join(__dirname, 'out');
  const only = process.argv.slice(2);
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.html') && (!only.length || only.some(o => f.startsWith(o))));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: parseInt(process.env.VW||'520'), height: 1000 } });
  for (const f of files) {
    await page.goto('file://' + path.join(dir, f));
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    const el = await page.$('.stage');
    await el.screenshot({ path: path.join(dir, f.replace('.html', '.png')) });
    console.log('ok', f);
  }
  await browser.close();
})();
