// Runs site/app.js against a tiny stand-in for the browser DOM (node, no packages), to check behaviour the
// validator tests cannot see: Copy refuses an invalid desk, odd coin ids cannot break the preview,
// and the theme accent stays readable as text on the page.
// Run: node tests/site-app.test.mjs
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => readFileSync(join(repo, p), 'utf8').replace(/^﻿/, '');

function makeEl(id) {
  const e = {
    id: id || '', className: '', textContent: '', value: '', checked: false, disabled: false, open: false,
    clientWidth: 1920, style: { setProperty() {} }, dataset: {}, handlers: {},
    appendChild(c) { return c; }, remove() {}, setAttribute() {}, focus() {},
    addEventListener(type, fn) { this.handlers[type] = fn; },
    querySelectorAll() { return []; }, closest() { return null; }
  };
  let parent = null;
  Object.defineProperty(e, 'parentNode', { get() { return parent || (parent = makeEl()); } });
  return e;
}

function load(page) {
  const byId = {};
  const copied = [];
  const props = {};
  const document = {
    getElementById(id) { return byId[id] || (byId[id] = makeEl(id)); },
    createElement() { return makeEl(); },
    querySelectorAll() { return []; },
    documentElement: Object.assign(makeEl(), { style: { setProperty(k, v) { props[k] = v; } } }), body: makeEl(),
    createRange() { return { selectNodeContents() {} }; }
  };
  const window = {
    isSecureContext: true, addEventListener() {},
    getSelection() { return { removeAllRanges() {}, addRange() {} }; }
  };
  // page: the configurator's own --bg and --ink, as the browser would report them for light or dark
  if (page) window.getComputedStyle = () => ({ getPropertyValue: (k) => page[k] || '' });
  const navigator = { clipboard: { writeText(t) { copied.push(t); return { then(ok) { ok(); } }; } } };
  const ctx = { window, document, navigator, setTimeout };
  vm.createContext(ctx);
  vm.runInContext(read('site/data.js'), ctx);
  vm.runInContext(read('site/schema.js'), ctx);
  vm.runInContext(read('site/app.js'), ctx);
  const $ = (id) => document.getElementById(id);
  const type = (id, value) => { $(id).value = value; $('controls').handlers.input({ target: $(id) }); };
  const pickTheme = (name) => $('controls').handlers.change({ target: { name: 'theme', value: name } });
  return { $, type, copied, props, pickTheme };
}

let fails = 0;
const check = (name, fn) => { try { fn(); console.log('PASS  ' + name); } catch (e) { fails++; console.log('FAIL  ' + name + '  ' + e.message); } };

check('the page loads and the example desk is valid', () => {
  const p = load();
  assert.match(p.$('status').textContent, /ready to export/i);
  assert.equal(p.$('download').disabled, false);
});

check('Copy copies a valid desk', () => {
  const p = load();
  p.$('copy').handlers.click();
  assert.equal(p.copied.length, 1);
  assert.equal(JSON.parse(p.copied[0]).schemaVersion, 1);
  assert.equal(p.$('status').textContent, 'Copied');
});

check('Copy does nothing and says so when the desk has errors', () => {
  const p = load();
  p.type('city', 'Bad [city]');
  assert.equal(p.$('download').disabled, true, 'the fixture should make the desk invalid');
  p.$('copy').handlers.click();
  assert.equal(p.copied.length, 0, 'an invalid desk was copied');
  assert.match(p.$('status').textContent, /not copied/i);
  assert.match(p.$('status').className, /bad/);
});

for (const id of ['constructor', 'toString', '__proto__', 'hasownproperty']) {
  check(`coin id "${id}" does not break the page`, () => {
    const p = load();
    p.type('coin1', id);
    assert.ok(p.$('json').textContent.includes(JSON.stringify(id.toLowerCase())), 'the coin did not reach desk.json');
  });
}

const lum = (hex) => {
  const n = parseInt(hex.slice(1), 16), f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(n >> 16 & 255) + 0.7152 * f(n >> 8 & 255) + 0.0722 * f(n & 255);
};
const contrast = (a, b) => (Math.max(lum(a), lum(b)) + 0.05) / (Math.min(lum(a), lum(b)) + 0.05);
const LIGHT = { '--bg': '#f3f1ec', '--ink': '#151514' }, DARK = { '--bg': '#0b0b0b', '--ink': '#ececec' };

check('the grey theme accent stays readable as text on the light page', () => {
  const p = load(LIGHT);
  p.pickTheme('minimal-grey');
  assert.equal(p.props['--accent'], '#d0d0cc', 'the button fill keeps the theme accent');
  assert.ok(contrast(p.props['--accent-text'], LIGHT['--bg']) >= 3, 'accent text is ' + p.props['--accent-text']);
});
check('an accent that is already readable is left alone', () => {
  const p = load(DARK);
  p.pickTheme('minimal-grey');
  assert.equal(p.props['--accent-text'], '#d0d0cc');
});
check('the theme never sets the error colour', () => {
  const p = load(LIGHT);
  for (const t of ['minimal-grey', 'paper-light', 'red-on-black', 'terminal-green']) p.pickTheme(t);
  assert.ok(!('--error' in p.props));
  assert.ok(!/--error\s*:[^;]*var\(--accent/.test(read('site/style.css')), '--error must not follow --accent');
});

console.log(fails ? `site-app: FAIL (${fails})` : 'site-app: PASS');
process.exit(fails ? 1 : 0);
