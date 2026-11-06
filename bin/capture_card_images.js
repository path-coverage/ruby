// Captures one card per kind of cell from cells.rb's page in
// the cards report, and each example page with its card open,
// for the README's Reading the HTML.
// Run by bin/capture_card_images.sh, which mounts the report at
// /report and docs/ at /out.
const puppeteer = require('puppeteer');

// Each card to save: the covered file its def is in, the line
// the def is on, and the PNG it is saved as.
const SHOTS = [
  ['cells.rb', 5, 'cell-true-false'],
  ['remember.rb', 1, 'cell-blank'],
  ['cells.rb', 11, 'cell-items'],
  ['cells.rb', 14, 'cell-answers'],
  ['cells.rb', 17, 'cell-nil'],
  ['cells.rb', 20, 'cell-tick']
];

// Waits ms milliseconds, for a card to finish opening.
const pause = (ms) => new Promise((done) => setTimeout(done, ms));

// Opens file's page with the card of the def on line open, by
// clicking the def's line number when the card starts closed,
// and its first decision's fold open, so its paths' outcomes show.
// Returns the card's id, eg paths-1.
async function openCard(page, file, line) {
  await page.goto(`file:///report/files/${file}.html`);
  await pause(400);
  const id = `paths-${line}`;
  const hidden = await page.$eval(`#${id}`, (card) => card.hidden);
  if (hidden) { await page.click(`#L${line}`); }
  await pause(400);
  await page.click(`#${id} .prow.decision`);
  // Moves the mouse off the card, so no row is lit by hovering.
  await page.mouse.move(0, 0);
  await pause(800);
  return id;
}

// Saves the card of the def on line of file alone, as
// /out/<name>.png.
async function shot(page, file, line, name) {
  const id = await openCard(page, file, line);
  const card = await page.$(`#${id}`);
  await card.screenshot({ path: `/out/${name}.png` });
}

// Saves the code box of file, the card of the def on line open
// beside it, exactly as a reader sees it, as /out/<name>.png.
async function pageShot(page, file, line, name) {
  const id = await openCard(page, file, line);
  const clip = await page.evaluate((tree) => {
    const rects = ['.box', `#${tree}`].map((selector) =>
      document.querySelector(selector).getBoundingClientRect());
    // The rects are relative to the viewport, a clip to the page.
    const x = Math.min(...rects.map((r) => r.left)) + window.scrollX;
    const y = Math.min(...rects.map((r) => r.top)) + window.scrollY;
    const right = Math.max(...rects.map((r) => r.right)) + window.scrollX;
    const bottom = Math.max(...rects.map((r) => r.bottom)) + window.scrollY;
    return { x, y, width: right - x, height: bottom - y };
  }, id);
  await page.screenshot({ path: `/out/${name}.png`, clip });
}

// Each page to save, as PAGE_SHOTS has it: the covered file, the
// line its def is on, and the PNG it is saved as.
const PAGE_SHOTS = [
  ['long.rb', 1, 'example-outcome'],
  ['remember.rb', 1, 'example-unreachable'],
  ['label.rb', 1, 'example-taken'],
  ['owner_of.rb', 1, 'example-nil'],
  ['any_odd.rb', 1, 'example-count'],
  ['odds.rb', 1, 'example-both'],
  ['notify.rb', 1, 'example-overview']
];

// Saves every card in SHOTS, then every page in PAGE_SHOTS.
async function main() {
  const browser = await puppeteer.launch({ args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 900, deviceScaleFactor: 2 });
  for (const [file, line, name] of SHOTS) {
    await shot(page, file, line, name);
  }
  for (const [file, line, name] of PAGE_SHOTS) {
    await pageShot(page, file, line, name);
  }
  await browser.close();
}

main();
