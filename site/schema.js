// desk.json validator for the configurator. Mirrors Test-DeskConfig in tools/lib/deskforge.psm1:
// the same JSON Schema subset and the same messages, so the site and install.ps1 agree.
(function (root) {
  'use strict';

  function isNum(v) { return typeof v === 'number' && isFinite(v); }
  function typeOk(v, t) {
    switch (t) {
      case 'object': return v !== null && typeof v === 'object' && !Array.isArray(v);
      case 'array': return Array.isArray(v);
      case 'string': return typeof v === 'string';
      case 'boolean': return typeof v === 'boolean';
      case 'number': return isNum(v);
      case 'integer': return isNum(v) && Math.floor(v) === v;
      case 'null': return v === null;
    }
    return false;
  }

  function node(v, s, at, errors) {
    if ('type' in s && !typeOk(v, s.type)) { errors.push(at + ' must be ' + s.type); return; }
    if ('const' in s && String(v) !== String(s.const)) errors.push(at + ' must be ' + s.const);
    if ('enum' in s && s.enum.indexOf(v) < 0) errors.push(at + ' must be one of: ' + s.enum.join(', '));
    if (isNum(v)) {
      if ('minimum' in s && v < s.minimum) errors.push(at + ' must be at least ' + s.minimum);
      if ('maximum' in s && v > s.maximum) errors.push(at + ' must be at most ' + s.maximum);
    }
    if (typeof v === 'string') {
      var len = Array.from(v).length;
      if ('minLength' in s && len < s.minLength) errors.push(at + ' is too short');
      if ('maxLength' in s && len > s.maxLength) errors.push(at + ' is too long (max ' + s.maxLength + ')');
      if ('pattern' in s && !new RegExp(s.pattern, 'u').test(v)) errors.push(at + ' has characters that are not allowed');
    }
    if (Array.isArray(v)) {
      if ('minItems' in s && v.length < s.minItems) errors.push(at + ' needs at least ' + s.minItems + ' item(s)');
      if ('maxItems' in s && v.length > s.maxItems) errors.push(at + ' allows at most ' + s.maxItems + ' item(s)');
      if (s.uniqueItems) {
        var seen = {};
        for (var i = 0; i < v.length; i++) {
          var k = JSON.stringify(v[i]);
          if (seen[k]) { errors.push(at + ' has a duplicate item'); break; }
          seen[k] = true;
        }
      }
      if (s.items) for (var j = 0; j < v.length; j++) node(v[j], s.items, at + '[' + j + ']', errors);
    }
    if (typeOk(v, 'object')) {
      var props = s.properties || {};
      (s.required || []).forEach(function (r) { if (!(r in v)) errors.push(at + '.' + r + ' is missing'); });
      Object.keys(v).forEach(function (p) {
        if (p in props) node(v[p], props[p], at + '.' + p, errors);
        else if (s.additionalProperties === false) errors.push(at + '.' + p + ' is not a known field');
      });
    }
  }

  function validateDesk(config, schema, themeNames) {
    var errors = [];
    node(config, schema, '$', errors);
    if (!errors.length && themeNames && themeNames.indexOf(config.theme) < 0) {
      errors.push("$.theme '" + config.theme + "' has no themes/" + config.theme + '/theme.json');
    }
    return errors;
  }

  root.validateDesk = validateDesk;
})(typeof window !== 'undefined' ? window : globalThis);
