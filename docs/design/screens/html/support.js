/*
 * Minimal standalone renderer for the screen mockups in this folder.
 *
 * Each *.dc.html file holds one screen as an <x-dc> template plus a
 * `class Component extends DCLogic` script. This file renders that template
 * in any browser, without the design canvas: {{ path }} holes in text and
 * attributes, <sc-if value>, <sc-for list as>, on* event handlers, state via
 * setState, and props from the script's data-props defaults.
 *
 * Props can be overridden from the URL to show other states, for example
 * HudTraining.dc.html?overtime=true or ResultExam.dc.html?level=1.
 */
(function () {
  'use strict';

  var WHOLE = /^\s*\{\{([^}]+)\}\}\s*$/;
  var ANY = /\{\{([^}]+)\}\}/g;
  var scheduled = false;
  var renderFn = null;

  function schedule() {
    if (scheduled || !renderFn) return;
    scheduled = true;
    Promise.resolve().then(function () {
      scheduled = false;
      renderFn();
    });
  }

  function shallowEqual(a, b) {
    var ka = Object.keys(a);
    if (ka.length !== Object.keys(b).length) return false;
    return ka.every(function (k) { return a[k] === b[k]; });
  }

  function DCLogic(props) {
    this.props = props || {};
    this.state = {};
  }
  DCLogic.prototype.setState = function (patch) {
    var next = typeof patch === 'function' ? patch(this.state, this.props) : patch;
    var merged = Object.assign({}, this.state, next);
    if (shallowEqual(merged, this.state)) return;
    this.state = merged;
    schedule();
  };
  DCLogic.prototype.forceUpdate = function () { schedule(); };
  window.DCLogic = DCLogic;

  function literal(path) {
    if (path === 'true') return { v: true };
    if (path === 'false') return { v: false };
    if (path === 'null') return { v: null };
    if (/^-?\d+(\.\d+)?$/.test(path)) return { v: Number(path) };
    if (/^(['"]).*\1$/.test(path)) return { v: path.slice(1, -1) };
    return null;
  }

  function lookup(raw, scopes) {
    var path = raw.trim();
    var lit = literal(path);
    if (lit) return lit.v;
    var parts = path.split('.');
    for (var i = scopes.length - 1; i >= 0; i--) {
      var scope = scopes[i];
      if (scope && Object.prototype.hasOwnProperty.call(scope, parts[0])) {
        var value = scope[parts[0]];
        for (var j = 1; j < parts.length; j++) value = value == null ? undefined : value[parts[j]];
        return value;
      }
    }
    return undefined;
  }

  function interpolate(text, scopes) {
    return text.replace(ANY, function (_, path) {
      var v = lookup(path, scopes);
      return v == null ? '' : String(v);
    });
  }

  function holeValue(attrValue, scopes) {
    var m = WHOLE.exec(attrValue || '');
    return m ? lookup(m[1], scopes) : attrValue;
  }

  function renderChildren(source, target, scopes) {
    source.childNodes.forEach(function (node) { renderNode(node, target, scopes); });
  }

  function renderNode(node, target, scopes) {
    if (node.nodeType === Node.TEXT_NODE) {
      target.appendChild(document.createTextNode(interpolate(node.nodeValue, scopes)));
      return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    var tag = node.localName;
    if (tag === 'sc-if') {
      if (holeValue(node.getAttribute('value'), scopes)) renderChildren(node, target, scopes);
      return;
    }
    if (tag === 'sc-for') {
      var list = holeValue(node.getAttribute('list'), scopes) || [];
      var as = node.getAttribute('as') || 'item';
      list.forEach(function (item, index) {
        var scope = { $index: index };
        scope[as] = item;
        renderChildren(node, target, scopes.concat([scope]));
      });
      return;
    }
    var el = document.createElementNS(node.namespaceURI, node.localName);
    Array.prototype.forEach.call(node.attributes, function (attr) {
      var whole = WHOLE.exec(attr.value);
      if (/^on/.test(attr.name) && whole) {
        var fn = lookup(whole[1], scopes);
        if (typeof fn === 'function') el.addEventListener(attr.name.slice(2), fn);
        return;
      }
      el.setAttribute(attr.name, interpolate(attr.value, scopes));
    });
    renderChildren(node, el, scopes);
    target.appendChild(el);
  }

  function coerce(value) {
    if (value === 'true') return true;
    if (value === 'false') return false;
    if (value !== '' && !isNaN(Number(value))) return Number(value);
    return value;
  }

  function readProps(script) {
    var props = {};
    var declared = {};
    try { declared = JSON.parse(script.getAttribute('data-props') || '{}'); } catch (e) { declared = {}; }
    Object.keys(declared).forEach(function (key) {
      if (key.charAt(0) !== '$' && declared[key] && 'default' in declared[key]) props[key] = declared[key].default;
    });
    new URLSearchParams(window.location.search).forEach(function (value, key) {
      var spec = declared[key];
      props[key] = spec && spec.editor === 'enum' ? value : coerce(value);
    });
    return props;
  }

  function focusPath(root) {
    var path = [];
    var node = document.activeElement;
    while (node && node !== root) {
      if (!node.parentNode) return null;
      path.unshift(Array.prototype.indexOf.call(node.parentNode.children, node));
      node = node.parentNode;
    }
    return node === root ? path : null;
  }

  function restoreFocus(root, path) {
    if (!path || !path.length) return;
    var node = root;
    for (var i = 0; i < path.length && node; i++) node = node.children[path[i]];
    if (node && typeof node.focus === 'function') node.focus();
  }

  function mount() {
    var host = document.querySelector('x-dc');
    var script = document.querySelector('script[data-dc-script]');
    if (!host || !script) return;

    var helmet = host.querySelector('helmet');
    if (helmet) {
      Array.prototype.slice.call(helmet.childNodes).forEach(function (n) { document.head.appendChild(n); });
      helmet.remove();
    }

    var template = document.createElement('template');
    Array.prototype.slice.call(host.childNodes).forEach(function (n) { template.content.appendChild(n); });
    var root = document.createElement('div');
    host.replaceWith(root);

    var Component = new Function('DCLogic', script.textContent + '\nreturn Component;')(DCLogic);
    var instance = new Component(readProps(script));

    renderFn = function () {
      var path = focusPath(root);
      var vals = instance.renderVals();
      root.replaceChildren();
      renderChildren(template.content, root, [vals]);
      restoreFocus(root, path);
    };
    renderFn();
    if (typeof instance.componentDidMount === 'function') instance.componentDidMount();
  }

  var style = document.createElement('style');
  style.textContent = 'x-dc{display:none}';
  document.head.appendChild(style);

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount);
  else mount();
})();
