// deskforge configurator. Static: reads window.DESK_DATA (built from the repo), never makes a network request.
(function () {
  'use strict';
  var D = window.DESK_DATA;
  var themeNames = Object.keys(D.themes);
  var SKINS = [
    ['panel', 'Panel', 'Clock, weather, prices, machine, Claude status'],
    ['now', 'Now playing', 'The Spotify track under the panel'],
    ['dock', 'Dock', 'A text dock instead of the taskbar'],
    ['home', 'Home', 'Full-screen launcher on Win+Z'],
    ['boot', 'Boot', 'The reveal after sign-in, unlock or wake']
  ];
  var ADDONS = [
    ['tape', 'Tape', 'BTCUSDT candles on the wallpaper'],
    ['depth', 'Depth', 'BTCUSDT order-book ladder'],
    ['wave', 'Wave', 'Audio spectrum on the dock edge'],
    ['mood', 'Mood', 'Wallpaper tint from the 4 h BTC move'],
    ['alert', 'Alert', 'A band for new unread messages']
  ];
  var LABELS = { bitcoin: 'BTC', ethereum: 'ETH', solana: 'SOL', tether: 'USDT', 'usd-coin': 'USDC', binancecoin: 'BNB', ripple: 'XRP', dogecoin: 'DOGE', cardano: 'ADA', litecoin: 'LTC' };

  var state = clone(D.example);
  var $ = function (id) { return document.getElementById(id); };
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function rgb(hex, a) {
    var n = parseInt(hex.slice(1), 16);
    return 'rgba(' + (n >> 16 & 255) + ',' + (n >> 8 & 255) + ',' + (n & 255) + ',' + (a == null ? 1 : a) + ')';
  }
  function coinLabel(id) { return LABELS[id] || String(id || '').replace(/[^a-z0-9]/g, '').toUpperCase().slice(0, 4); }

  // ------------------------------------------------------------------ controls
  function buildThemes() {
    var box = $('themes');
    themeNames.forEach(function (name) {
      var t = D.themes[name], c = t.colors;
      var lab = el('label', 'theme');
      var inp = el('input'); inp.type = 'radio'; inp.name = 'theme'; inp.value = name;
      var sw = el('span', 'sw'); sw.style.background = c.bg;
      var stake = el('i'); stake.style.background = c.accent;
      var big = el('b', null, '09:41'); big.style.color = c.ink; big.style.fontFamily = t.fonts.display + ', var(--display)';
      var bar = el('em'); bar.style.background = c.mid;
      sw.appendChild(stake); sw.appendChild(big); sw.appendChild(bar);
      lab.appendChild(inp); lab.appendChild(sw); lab.appendChild(el('span', 'label', t.label));
      box.appendChild(lab);
    });
  }

  function buildToggles(id, list, group) {
    var ul = $(id);
    list.forEach(function (it) {
      var li = el('li'), lab = el('label', 'toggle'), inp = el('input'), span = el('span', null, it[1]);
      inp.type = 'checkbox'; inp.dataset.group = group; inp.dataset.key = it[0];
      span.appendChild(el('small', null, it[2]));
      lab.appendChild(inp); lab.appendChild(span); li.appendChild(lab); ul.appendChild(li);
    });
  }

  function buildApps() {
    var ol = $('apps'); ol.textContent = '';
    state.homeApps.forEach(function (a, i) {
      var li = el('li', 'app'), pair = el('div', 'pair');
      var n = el('label', 'field', 'Name'), ni = el('input'); ni.value = a.name; ni.maxLength = 24; ni.dataset.app = i; ni.dataset.k = 'name';
      var p = el('label', 'field', 'Path'), pi = el('input'); pi.value = a.path; pi.maxLength = 260; pi.spellcheck = false; pi.dataset.app = i; pi.dataset.k = 'path';
      n.appendChild(ni); p.appendChild(pi); pair.appendChild(n); pair.appendChild(p);
      var del = el('button', 'btn del', '×'); del.type = 'button'; del.setAttribute('aria-label', 'Remove ' + (a.name || 'app')); del.dataset.del = i;
      li.appendChild(pair); li.appendChild(del); ol.appendChild(li);
    });
    $('addApp').disabled = state.homeApps.length >= 12;
  }

  function fillControls() {
    document.querySelectorAll('input[name=theme]').forEach(function (r) { r.checked = r.value === state.theme; });
    $('city').value = state.city;
    $('latitude').value = state.latitude;
    $('longitude').value = state.longitude;
    setRadio('units', state.units); setRadio('clock', state.clock); setRadio('dock', state.dock);
    $('coin1').value = state.coins[0] || '';
    $('coin2').value = state.coins[1] || '';
    $('refresh').value = state.refreshSeconds;
    document.querySelectorAll('input[data-group]').forEach(function (c) { c.checked = !!state[c.dataset.group][c.dataset.key]; });
    $('wakeOn').checked = state.wakeReveal.enabled;
    $('wakeText').value = state.wakeReveal.text;
    $('startup').checked = state.startup;
    buildApps();
  }
  function setRadio(name, v) { document.querySelectorAll('input[name=' + name + ']').forEach(function (r) { r.checked = r.value === v; }); }
  function num(v) { var s = String(v).trim(); return s !== '' && isFinite(Number(s)) ? Number(s) : s; }

  function readControls(e) {
    var t = e && e.target;
    if (!t) return;
    if (t.name === 'theme') state.theme = t.value;
    else if (t.name === 'units' || t.name === 'clock' || t.name === 'dock') state[t.name] = t.value;
    else if (t.id === 'city') state.city = t.value;
    else if (t.id === 'latitude') state.latitude = num(t.value);
    else if (t.id === 'longitude') state.longitude = num(t.value);
    else if (t.id === 'coin1' || t.id === 'coin2') {
      var c = [$('coin1').value.trim().toLowerCase(), $('coin2').value.trim().toLowerCase()].filter(function (x) { return x; });
      state.coins = c;
    }
    else if (t.id === 'refresh') state.refreshSeconds = num(t.value);
    else if (t.dataset && t.dataset.group) state[t.dataset.group][t.dataset.key] = t.checked;
    else if (t.id === 'wakeOn') state.wakeReveal.enabled = t.checked;
    else if (t.id === 'wakeText') state.wakeReveal.text = t.value;
    else if (t.id === 'startup') state.startup = t.checked;
    else if (t.dataset && t.dataset.app != null) state.homeApps[+t.dataset.app][t.dataset.k] = t.value;
    update();
  }

  // ------------------------------------------------------------------ preview (1920 x 1080, scaled to fit)
  function box(parent, x, y, w, h, color) {
    var b = el('div'); var s = b.style;
    s.position = 'absolute'; s.left = x + 'px'; s.top = y + 'px'; s.width = w + 'px'; s.height = h + 'px'; s.background = color;
    parent.appendChild(b); return b;
  }
  function text(parent, str, x, y, font, size, color, opts) {
    var t = el('div', null, str); var s = t.style; opts = opts || {};
    s.position = 'absolute'; s.top = y + 'px'; s.whiteSpace = 'pre'; s.lineHeight = '1';
    if (opts.right) s.right = (1920 - x) + 'px'; else s.left = x + 'px';
    s.font = (opts.bold ? '600 ' : '400 ') + Math.round(size * 1.333) + 'px ' + font;
    s.color = color; if (opts.upper) s.textTransform = 'uppercase';
    parent.appendChild(t); return t;
  }

  function renderDesk() {
    var t = D.themes[state.theme] || D.themes[themeNames[0]];
    var c = t.colors, disp = '"' + t.fonts.display + '", var(--display)', mono = '"' + t.fonts.mono + '", var(--mono)';
    var m = D.mock, desk = $('desk');
    desk.textContent = '';
    desk.style.background = c.bg;
    for (var y = 120; y < 1080; y += 120) box(desk, 0, y, 1920, 1, rgb(c.rule, .45));
    box(desk, Math.round(1920 * 0.618), 0, 3, 1080, c.accent);
    text(desk, 'DESKFORGE / ' + t.name.toUpperCase(), 48, 1040, mono, 9, c.dim);
    var twelve = state.clock === '12', f = state.units === 'f';
    var dockTop = state.dock === 'top', dockY = dockTop ? 0 : 1024, top = dockTop ? 76 : 0;

    if (state.addons.mood) {
      var wash = box(desk, 0, 0, 1920, 1080, 'transparent');
      wash.style.background = 'linear-gradient(to top, ' + rgb(c.accent, .28) + ', ' + rgb(c.accent, 0) + ' 75%)';
    }
    if (state.addons.tape) {
      var x0 = 120, y0 = 120 + top, p = 87000, seed = 7;
      for (var i = 0; i < 46; i++) {
        seed = (seed * 9301 + 49297) % 233280; var r1 = seed / 233280;
        var o = p; p = p + (r1 - 0.48) * 260; var up = p >= o, h = Math.max(Math.abs(p - o) / 6, 2);
        box(desk, x0 + i * 18.5, y0 + 100 - (Math.max(o, p) - 86600) / 6, 8, h, up ? rgb(c.mid, .6) : rgb(c.accent, .7));
      }
    }
    if (state.addons.depth) {
      for (var r = 0; r < 20; r++) {
        var w = 4 + Math.sqrt(((r * 37) % 11) / 11) * 200;
        box(desk, 120 + 244 - w, 380 + top + r * 22 + (r >= 10 ? 8 : 0), w, 12, r === 13 ? rgb(c.warn, .6) : rgb(c.mid, r < 10 ? .35 : .5));
      }
    }

    if (state.skins.panel) {
      var px = 1496, py = 96 + top;
      text(desk, 'BOOT 08:41  .  ONLINE  .  WIDGETS 5/5', px, py, mono, 10, c.dim);
      text(desk, twelve ? '9:41' : '09:41', px - 6, py + 22, disp, 66, c.ink, { bold: true });
      text(desk, (twelve ? 'AM  .  ' : '') + 'WED 11 NOV', px, py + 118, mono, 12, c.mid);
      box(desk, px, py + 156, 360, 1, c.rule); box(desk, px + 220, py + 152, 4, 10, c.accent);
      var cityText = (state.city || '').toUpperCase();
      text(desk, '02 / ' + cityText, px, py + 186, mono, 10, c.dim);
      var tc = m.weather.current.temperature_2m, temp = Math.floor(f ? tc * 9 / 5 + 32 : tc);
      var wind = Math.floor(f ? m.weather.current.wind_speed_10m * 0.621 : m.weather.current.wind_speed_10m);
      text(desk, temp + '°', px - 3, py + 208, disp, 39, c.ink, { bold: true });
      text(desk, 'OVERCAST', px + 104, py + 218, mono, 12, c.mid);
      text(desk, m.weather.current.relative_humidity_2m + '% HUMID  .  ' + wind + (f ? ' MPH' : ' KM/H'), px + 104, py + 240, mono, 12, c.mid);
      text(desk, '03 / PRICES', px, py + 292, mono, 10, c.dim);
      state.coins.slice(0, 2).forEach(function (id, k) {
        var d = m.prices[id] || m.prices[k === 0 ? 'bitcoin' : 'ethereum'];
        var chg = d.usd_24h_change, yy = py + 318 + k * 39;
        text(desk, coinLabel(id), px, yy + 9, mono, 12, c.mid);
        text(desk, '$' + Math.round(d.usd).toLocaleString('en-US'), px + 60, yy, disp, 24, c.ink, { bold: true });
        text(desk, (chg >= 0 ? '+' : '') + chg.toFixed(2) + '%', px + 360, yy + 12, mono, 12, chg < 0 ? c.accent : c.warn, { right: true });
      });
      text(desk, '04 / MACHINE', px, py + 416, mono, 10, c.dim);
      [['C:  61.4 GB FREE', .68, c.mid], ['RAM  54%', .54, c.mid], ['CPU  7%', .07, c.accent]].forEach(function (row, k) {
        var yy = py + 438 + k * 38;
        text(desk, row[0], px, yy, mono, 12, c.mid);
        box(desk, px, yy + 22, 360, 3, c.rule); box(desk, px, yy + 22, 360 * row[1], 3, row[2]);
      });
      text(desk, '05 / CLAUDE', px, py + 570, mono, 10, c.dim);
      box(desk, px, py + 598, 12, 12, c.mid);
      text(desk, 'OPERATIONAL', px + 24, py + 596, mono, 12, c.ink);
    }
    if (state.skins.now) {
      var ny = dockTop ? 900 : 860;
      text(desk, '06 / NOW PLAYING', 1496, ny, mono, 10, c.dim);
      box(desk, 1496, ny + 26, 4, 30, c.accent);
      text(desk, m.nowplaying.song, 1512, ny + 22, disp, 24, c.ink, { bold: true });
      text(desk, m.nowplaying.artist.toUpperCase(), 1512, ny + 62, mono, 12, c.mid);
    }
    if (state.skins.dock) {
      box(desk, 0, dockY, 1920, 56, c.surface); box(desk, 0, dockTop ? 55 : dockY, 1920, 1, c.rule);
      var dx = 24;
      var labels = [['00', 'HOME', 2]].concat(state.homeApps.slice(0, 10).map(function (a, k) {
        return [('0' + (k + 1)).slice(-2), (a.name || '').toUpperCase().replace(/[^A-Z0-9 ]/g, '').slice(0, 12), k === 2 ? 2 : (k % 2)];
      }));
      labels.forEach(function (l) {
        var idx = text(desk, l[0], dx, dockY + 22, mono, 9, l[2] === 0 ? c.dim : c.accent);
        var lab = text(desk, l[1], dx + 22, dockY + 18, disp, 12, l[2] === 0 ? c.dim : (l[2] === 1 ? c.mid : c.ink), { bold: true });
        dx += 22 + Math.max(lab.textContent.length * 10, 10) + 30;
      });
      text(desk, 'VOL 42', 1536, dockY + 20, mono, 9, c.mid); box(desk, 1536, dockY + 41, 72, 2, c.rule); box(desk, 1536, dockY + 41, 30, 2, c.accent);
      text(desk, 'BRT 70', 1628, dockY + 20, mono, 9, c.mid); box(desk, 1628, dockY + 41, 72, 2, c.rule); box(desk, 1628, dockY + 41, 50, 2, c.accent);
      text(desk, twelve ? '9:41 AM' : '09:41', 1896, dockY + 18, disp, 13, c.ink, { bold: true, right: true });
      if (state.addons.wave) {
        for (var b = 0; b < 96; b++) {
          var k2 = Math.abs(48 - b - 0.5) / 48, hh = Math.max(1, 14 * Math.pow(1 - k2, 1.6) * (0.5 + 0.5 * Math.abs(Math.sin(b * 0.7))));
          box(desk, b * 20 + 1, dockTop ? 56 : dockY - hh, 18, hh, rgb(c.accent, .8));
        }
      }
    }
    if (state.addons.alert) {
      box(desk, 0, dockTop ? 56 : 0, 1920, 72, c.accent);
      text(desk, 'MAIL', 110, (dockTop ? 56 : 0) + 18, disp, 22, c.onAccent, { bold: true });
      text(desk, '3 UNREAD', 1880, (dockTop ? 56 : 0) + 26, disp, 14, c.onAccent, { bold: true, right: true });
    }
    document.documentElement.style.setProperty('--accent', c.accent);
    document.documentElement.style.setProperty('--on-accent', c.onAccent);
    scaleDesk();
  }

  function scaleDesk() {
    var w = $('stage').clientWidth;
    $('desk').style.transform = 'scale(' + (w / 1920) + ')';
  }

  // ------------------------------------------------------------------ validate and export
  var lastErrors = [];
  function fileText() { return JSON.stringify(state, null, 2) + '\n'; }

  function update() {
    lastErrors = window.validateDesk(state, D.schema, themeNames);
    var st = $('status'), ul = $('errors');
    ul.textContent = '';
    lastErrors.forEach(function (e) { ul.appendChild(el('li', null, e)); });
    st.className = 'status ' + (lastErrors.length ? 'bad' : 'ok');
    st.textContent = lastErrors.length ? lastErrors.length + ' thing' + (lastErrors.length > 1 ? 's' : '') + ' to fix before export' : 'Valid desk.json, ready to export';
    $('download').disabled = lastErrors.length > 0;
    ['city', 'latitude', 'longitude', 'refresh', 'coin1', 'coin2', 'wakeText'].forEach(function (id) {
      var key = { refresh: 'refreshSeconds', coin1: 'coins', coin2: 'coins', wakeText: 'wakeReveal' }[id] || id;
      $(id).setAttribute('aria-invalid', lastErrors.some(function (e) { return e.indexOf('$.' + key) === 0; }) ? 'true' : 'false');
    });
    $('json').textContent = fileText();
    renderDesk();
  }

  function flash(msg, bad) { var st = $('status'); st.textContent = msg; st.className = 'status ' + (bad ? 'bad' : 'ok'); }

  $('download').addEventListener('click', function () {
    if (lastErrors.length) return;
    try {
      var blob = new Blob([fileText()], { type: 'application/json' });
      var a = el('a'); a.href = URL.createObjectURL(blob); a.download = 'desk.json';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
      flash('Saved desk.json to your downloads');
    } catch (e) { $('json').parentNode.open = true; flash('Download blocked here. Copy the file below instead.', true); }
  });

  $('copy').addEventListener('click', function () {
    // never hand out a desk.json the installer would refuse
    if (lastErrors.length) {
      flash('Not copied: fix the ' + lastErrors.length + ' thing' + (lastErrors.length > 1 ? 's' : '') + ' listed below first', true);
      return;
    }
    var done = function () { flash('Copied'); };
    var fallback = function () {
      var d = $('json').parentNode; d.open = true;
      var range = document.createRange(); range.selectNodeContents($('json'));
      var sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
      flash('Press Ctrl+C to copy the selected file');
    };
    try {
      if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(fileText()).then(done, fallback);
      else fallback();
    } catch (e) { fallback(); }
  });

  $('import').addEventListener('change', function (e) {
    var f = e.target.files && e.target.files[0];
    if (!f) return;
    if (f.size > 64 * 1024) { flash('That file is too large to be a desk.json', true); return; }
    var r = new FileReader();
    r.onload = function () {
      var o;
      try { o = JSON.parse(String(r.result).replace(/^﻿/, '')); } catch (x) { flash('That file is not valid JSON', true); return; }
      var errs = window.validateDesk(o, D.schema, themeNames);
      if (errs.length) {
        var ul = $('errors'); ul.textContent = '';
        errs.forEach(function (m) { ul.appendChild(el('li', null, m)); });
        flash('Not imported: ' + errs.length + ' problem' + (errs.length > 1 ? 's' : '') + ' in that file', true);
        return;
      }
      state = o; fillControls(); update(); flash('Imported ' + f.name);
    };
    r.onerror = function () { flash('Could not read that file', true); };
    r.readAsText(f);
    e.target.value = '';
  });

  $('reset').addEventListener('click', function () { state = clone(D.example); fillControls(); update(); flash('Back to the example desk'); });
  $('addApp').addEventListener('click', function () {
    if (state.homeApps.length >= 12) return;
    state.homeApps.push({ name: 'App', path: 'notepad.exe' }); buildApps(); update();
    var inputs = $('apps').querySelectorAll('input'); inputs[inputs.length - 2].focus();
  });
  $('apps').addEventListener('click', function (e) {
    var b = e.target.closest('[data-del]'); if (!b) return;
    state.homeApps.splice(+b.dataset.del, 1); buildApps(); update();
  });
  $('controls').addEventListener('input', readControls);
  $('controls').addEventListener('change', readControls);
  $('controls').addEventListener('submit', function (e) { e.preventDefault(); });

  buildThemes();
  buildToggles('skins', SKINS, 'skins');
  buildToggles('addons', ADDONS, 'addons');
  fillControls();
  update();
  if (window.ResizeObserver) new ResizeObserver(scaleDesk).observe($('stage'));
  else window.addEventListener('resize', scaleDesk);
})();
