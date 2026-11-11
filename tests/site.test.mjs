// Site tests (node, no packages): the configurator's validator must agree with every fixture in tests/fixtures,
// and site/data.js must carry exactly the repo's schema, example, themes and sample data.
// Run: node tests/site.test.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => readFileSync(join(repo, p), 'utf8').replace(/^﻿/, '');
const ctx = { window: {}, globalThis: {} };
vm.createContext(ctx);
vm.runInContext(read('site/data.js'), ctx);
vm.runInContext(read('site/schema.js'), ctx);
const D = ctx.window.DESK_DATA;
const validate = ctx.window.validateDesk;
const themes = Object.keys(D.themes);
let fails = 0;
const check = (name, fn) => { try { fn(); console.log('PASS  ' + name); } catch (e) { fails++; console.log('FAIL  ' + name + '  ' + e.message); } };
const plain = (o) => JSON.parse(JSON.stringify(o));

check('data.js schema equals config/desk.schema.json', () => assert.deepEqual(plain(D.schema), JSON.parse(read('config/desk.schema.json'))));
check('data.js example equals config/desk.example.json', () => assert.deepEqual(plain(D.example), JSON.parse(read('config/desk.example.json'))));
for (const t of readdirSync(join(repo, 'themes'), { withFileTypes: true }).filter((d) => d.isDirectory())) {
  check(`data.js theme ${t.name} equals themes/${t.name}/theme.json`, () => assert.deepEqual(plain(D.themes[t.name]), JSON.parse(read(`themes/${t.name}/theme.json`))));
}
for (const k of ['weather', 'prices', 'status']) {
  check(`data.js mock ${k} equals examples/${k}.json`, () => assert.deepEqual(plain(D.mock[k]), JSON.parse(read(`examples/${k}.json`))));
}
check('example desk is valid in the site validator', () => assert.equal(validate(plain(D.example), D.schema, themes).length, 0));

for (const f of readdirSync(join(repo, 'tests/fixtures')).filter((n) => n.endsWith('.json'))) {
  const fx = JSON.parse(read('tests/fixtures/' + f));
  const errs = validate(fx.config, D.schema, themes);
  check('fixture ' + f, () => {
    if (fx.expect === 'valid') assert.equal(errs.length, 0, errs.join('; '));
    else { assert.ok(errs.length > 0, 'expected errors'); assert.ok(errs.join(' ').includes(fx.mustMention), 'errors do not mention ' + fx.mustMention + ': ' + errs.join('; ')); }
  });
}

const html = read('site/index.html');
check('site makes no network requests (CSP connect-src none, no remote URLs)', () => {
  assert.ok(html.includes("connect-src 'none'"));
  const all = html + read('site/app.js') + read('site/schema.js');
  assert.ok(!/https?:\/\//.test(all.replace(/http:\/\/json-schema\.org[^"]*/g, '')), 'found a remote URL');
});
console.log(fails ? `site: FAIL (${fails})` : 'site: PASS');
process.exit(fails ? 1 : 0);
