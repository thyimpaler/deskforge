// Runs site/app.js against a tiny stand-in for the browser DOM (node, no packages), to check behaviour the
// validator tests cannot see: Copy refuses an invalid desk, and odd coin ids cannot break the preview.
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

function load() {
  const byId = {};
  const copied = [];
  const document = {
    getElementById(id) { return byId[id] || (byId[id] = makeEl(id)); },
    createElement() { return makeEl(); },
    querySelectorAll() { return []; },
    documentElement: makeEl(), body: makeEl(),
    createRange() { return { selectNodeContents() {} }; }
  };
  const window = {
    isSecureContext: true, addEventListener() {},
    getSelection() { return { removeAllRanges() {}, addRange() {} }; }
  };
  const navigator = { clipboard: { writeText(t) { copied.push(t); return { then(ok) { ok(); } }; } } };
  const ctx = { window, document, navigator, setTimeout };
  vm.createContext(ctx);
  vm.runInContext(read('site/data.js'), ctx);
  vm.runInContext(read('site/schema.js'), ctx);
  vm.runInContext(read('site/app.js'), ctx);
  const $ = (id) => document.getElementById(id);
  const type = (id, value) => { $(id).value = value; $('controls').handlers.input({ target: $(id) }); };
  return { $, type, copied };
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

console.log(fails ? `site-app: FAIL (${fails})` : 'site-app: PASS');
process.exit(fails ? 1 : 0);
