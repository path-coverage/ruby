// Screenshots fixed states of a few demo pages, as drawn after
// side.js runs: on load, a def's number clicked, a loose top-level
// button clicked, and the first fold of the open card opened.
// With MODE=save it writes them to /out/golden; otherwise it
// writes /out/now and prints, for each, same or DIFFERENT, so a
// refactor that changes what is drawn shows. Run by
// bin/check_pixels.sh, which mounts the demo at /site and
// reports/pixels/ at /out.
const fs = require('fs');
const puppeteer = require('puppeteer');

// Waits ms milliseconds, for scripts and layout to settle.
const pause = (ms) => new Promise((done) => setTimeout(done, ms));

// The demo's file pages screenshotted, after its index.
const PAGES = ['shop.rb', 'fee.rb', 'group.rb', 'kata.rb'];

(async () => {
  const mode = process.env.MODE === 'save' ? 'golden' : 'now';
  fs.mkdirSync(`/out/${mode}`, { recursive: true });
  const browser = await puppeteer.launch({ args: ['--no-sandbox'] });
  const index = await browser.newPage();
  index.on('pageerror', (e) => console.log('ERROR index', e.message));
  await index.setViewport({ width: 1400, height: 1000 });
  await index.goto('file:///site/index.html');
  await new Promise((done) => setTimeout(done, 400));
  const indexFile = `/out/${mode}/index-load.png`;
  await index.screenshot({ path: indexFile, fullPage: true });
  if (mode === 'now') {
    const same = fs.readFileSync(indexFile).equals(fs.readFileSync('/out/golden/index-load.png'));
    console.log('index load', same ? 'same' : 'DIFFERENT');
  }
  const header = await index.$('th button');
  if (header) {
    await header.click();
    await new Promise((done) => setTimeout(done, 300));
    const sortedFile = `/out/${mode}/index-sorted.png`;
    await index.screenshot({ path: sortedFile, fullPage: true });
    if (mode === 'now') {
      const same = fs.readFileSync(sortedFile).equals(fs.readFileSync('/out/golden/index-sorted.png'));
      console.log('index sorted', same ? 'same' : 'DIFFERENT');
    }
  }
  await index.close();
  for (const name of PAGES) {
    const page = await browser.newPage();
    page.on('pageerror', (e) => console.log('ERROR', name, e.message));
    await page.setViewport({ width: 1400, height: 1000 });
    await page.goto(`file:///site/files/source/${name}.html`);
    await pause(400);
    const shots = [['load', null]];
    shots.push(['def', '.lineno.mdef']);
    shots.push(['loose', 'button.lnum.loose']);
    shots.push(['fold', '.pathgrid:not([hidden]) .prow.decision']);
    for (const [state, selector] of shots) {
      if (selector) {
        const found = await page.$(selector);
        if (!found) { console.log(name, state, 'none'); continue; }
        await page.evaluate((s) => document.querySelector(s).click(), selector);
        await pause(500);
      }
      const file = `/out/${mode}/${name}-${state}.png`;
      await page.screenshot({ path: file, fullPage: true });
      if (mode === 'now') {
        const same = fs.readFileSync(file).equals(fs.readFileSync(`/out/golden/${name}-${state}.png`));
        console.log(name, state, same ? 'same' : 'DIFFERENT');
      }
    }
    await page.close();
  }
  await browser.close();
})();
