// Просмотрщик холста: чистый JS, без зависимостей.
(function () {
  var B = window.CB_BOARDS, T = window.CB_TITLES;
  var view = document.getElementById('view'), world = document.getElementById('world');
  var nav = document.getElementById('nav'), zl = document.getElementById('zl');
  document.getElementById('ttl').textContent = window.CB_TITLE;
  document.title = window.CB_TITLE;

  var s = 1, tx = 0, ty = 0, els = {};

  // --- доски
  B.forEach(function (b) {
    var d = document.createElement('div');
    d.className = 'board'; d.id = 'b-' + b.id;
    d.style.cssText = 'left:' + b.x + 'px;top:' + b.y + 'px;width:' + b.w + 'px;height:' + b.h + 'px';
    var t = document.createElement('a');
    t.className = 'bt'; t.textContent = b.title; t.href = b.url; t.target = '_blank';
    t.title = 'Открыть отдельно'; t.addEventListener('mousedown', function (e) { e.stopPropagation(); });
    d.appendChild(t);
    d.dataset.src = b.url;
    world.appendChild(d); els[b.id] = d;
  });
  T.forEach(function (n) {
    var d = document.createElement('div'); d.className = 'sec'; d.textContent = n.text;
    d.style.left = n.x + 'px'; d.style.top = n.y + 'px'; world.appendChild(d);
  });

  // --- меню слева: по разделам (по заголовкам холста)
  var secs = T.slice().sort(function (a, b) { return a.y - b.y; });
  function secOf(b) { var r = null; secs.forEach(function (t) { if (t.y <= b.y + 1) r = t; }); return r; }
  var last = null;
  B.slice().sort(function (a, b) { return a.y - b.y || a.x - b.x; }).forEach(function (b) {
    var sec = secOf(b);
    if (sec !== last) { var h = document.createElement('h2'); h.textContent = sec ? sec.text : ''; nav.appendChild(h); last = sec; }
    var a = document.createElement('a'); a.textContent = b.title; a.dataset.id = b.id;
    a.addEventListener('click', function () { go(b.id); });
    nav.appendChild(a);
  });

  // --- рендер и ленивая загрузка iframe
  function apply() {
    world.style.transform = 'translate(' + tx + 'px,' + ty + 'px) scale(' + s + ')';
    zl.textContent = Math.round(s * 100) + '%';
    lazy();
  }
  var pend = 0;
  function lazy() {
    cancelAnimationFrame(pend);
    pend = requestAnimationFrame(function () {
      var vw = view.clientWidth, vh = view.clientHeight;
      B.forEach(function (b) {
        var el = els[b.id];
        if (el.firstChild && el.querySelector('iframe')) return;
        var x = b.x * s + tx, y = b.y * s + ty;
        if (x < vw + 400 && x + b.w * s > -400 && y < vh + 400 && y + b.h * s > -400) {
          var f = document.createElement('iframe');
          f.src = b.url; f.title = b.title; el.appendChild(f);
        }
      });
    });
  }
  function zoomAt(k, cx, cy) {
    var n = Math.min(2, Math.max(0.03, s * k)); k = n / s;
    tx = cx - (cx - tx) * k; ty = cy - (cy - ty) * k; s = n; apply();
  }
  function fit(box) {
    var vw = view.clientWidth, vh = view.clientHeight, pad = 60;
    s = Math.min(2, Math.min((vw - pad * 2) / box.w, (vh - pad * 2) / box.h));
    tx = (vw - box.w * s) / 2 - box.x * s; ty = (vh - box.h * s) / 2 - box.y * s; apply();
  }
  function fitAll() {
    var x1 = 1e9, y1 = 1e9, x2 = -1e9, y2 = -1e9;
    B.forEach(function (b) { x1 = Math.min(x1, b.x); y1 = Math.min(y1, b.y - 40); x2 = Math.max(x2, b.x + b.w); y2 = Math.max(y2, b.y + b.h); });
    fit({ x: x1, y: y1, w: x2 - x1, h: y2 - y1 });
  }
  function go(id) {
    var b = B.filter(function (q) { return q.id === id; })[0]; if (!b) return;
    var vh = view.clientHeight;
    fit({ x: b.x, y: b.y - 30, w: Math.max(b.w, 400), h: b.h + 30 });
    if (b.h < 2000) { s = Math.min(s, 1); }
    [].forEach.call(nav.querySelectorAll('a'), function (a) { a.classList.toggle('on', a.dataset.id === id); });
    var el = els[id]; el.classList.add('flash'); setTimeout(function () { el.classList.remove('flash'); }, 1400);
    history.replaceState(null, '', '#' + id);
  }

  // --- мышь / тач / клавиши
  view.addEventListener('wheel', function (e) {
    e.preventDefault();
    var r = view.getBoundingClientRect();
    if (e.ctrlKey || e.metaKey || Math.abs(e.deltaY) >= 50 && !e.shiftKey) zoomAt(Math.exp(-e.deltaY * 0.0016), e.clientX - r.left, e.clientY - r.top);
    else { tx -= e.deltaX; ty -= e.deltaY; apply(); }
  }, { passive: false });
  var drag = null;
  view.addEventListener('pointerdown', function (e) {
    if (e.target.closest('.bt')) return;
    drag = { x: e.clientX, y: e.clientY, tx: tx, ty: ty };
    view.classList.add('drag'); view.setPointerCapture(e.pointerId);
    [].forEach.call(document.querySelectorAll('iframe'), function (f) { f.style.pointerEvents = 'none'; });
  });
  view.addEventListener('pointermove', function (e) { if (!drag) return; tx = drag.tx + e.clientX - drag.x; ty = drag.ty + e.clientY - drag.y; apply(); });
  function up() { drag = null; view.classList.remove('drag'); [].forEach.call(document.querySelectorAll('iframe'), function (f) { f.style.pointerEvents = ''; }); }
  view.addEventListener('pointerup', up); view.addEventListener('pointercancel', up);
  function center() { return [view.clientWidth / 2, view.clientHeight / 2]; }
  document.getElementById('zi').onclick = function () { var c = center(); zoomAt(1.25, c[0], c[1]); };
  document.getElementById('zo').onclick = function () { var c = center(); zoomAt(0.8, c[0], c[1]); };
  document.getElementById('fit').onclick = fitAll;
  window.addEventListener('keydown', function (e) {
    var c = center();
    if (e.key === '0') fitAll(); else if (e.key === '+' || e.key === '=') zoomAt(1.25, c[0], c[1]); else if (e.key === '-') zoomAt(0.8, c[0], c[1]);
  });
  window.addEventListener('resize', lazy);
  // ссылки внутри экранов (см. build.mjs): переход к доске
  window.addEventListener('message', function (e) { if (e.data && e.data.craftGo) go(e.data.craftGo); });

  window.addEventListener('hashchange', function () { var q = location.hash.slice(1); if (els[q]) go(q); });
  var h = location.hash.slice(1);
  if (h && els[h]) go(h); else fitAll();
})();
