(function () {
  function getVal(tr, key) {
    var raw = tr.getAttribute('data-sort-json');
    if (!raw) return null;
    try {
      var obj = JSON.parse(raw);
      var v = obj[key];
      if (v === null || v === undefined) return null;
      var f = parseFloat(v);
      return isFinite(f) ? f : null;
    } catch { return null; }
  }

  function sortTable(table, key, dir) {
    var tbody = table.querySelector('tbody');
    if (!tbody) return;
    var rows = Array.prototype.slice.call(tbody.querySelectorAll('tr'));
    var floor = -Infinity;
    rows.sort(function (a, b) {
      var av = getVal(a, key);
      var bv = getVal(b, key);
      av = av === null ? floor : av;
      bv = bv === null ? floor : bv;
      return dir === 'asc' ? av - bv : bv - av;
    });
    rows.forEach(function (r) { tbody.appendChild(r); });
  }

  // 一排互斥 toggle：同一個 data-sort-scope 內同時只能有一個開關是 on。
  // 點還沒開的 toggle → 關掉其他、開這個、預設高到低；
  // 點已經開著的 toggle → 原地切換高到低/低到高（不影響互斥狀態）。
  function setToggleState(btn, on, dir) {
    btn.classList.toggle('sort-toggle-active', on);
    var track = btn.querySelector('.sort-toggle-track');
    var knob  = btn.querySelector('.sort-toggle-knob');
    var arrow = btn.querySelector('.sort-toggle-arrow');
    if (on) {
      btn.setAttribute('data-sort-dir', dir);
      if (track) { track.classList.remove('bg-gray-300'); track.classList.add('bg-green-400'); }
      if (knob)  knob.classList.add('translate-x-2.5');
      if (arrow) arrow.textContent = dir === 'desc' ? '▾' : '▴';
    } else {
      btn.removeAttribute('data-sort-dir');
      if (track) { track.classList.remove('bg-green-400'); track.classList.add('bg-gray-300'); }
      if (knob)  knob.classList.remove('translate-x-2.5');
      if (arrow) arrow.textContent = '';
    }
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.sort-toggle[data-sort-key]');
    if (!btn) return;

    var scope = btn.closest('[data-sort-scope]');
    if (!scope) return;
    var tables = scope.querySelectorAll('table[data-sortable]');
    if (!tables.length) return;

    var wasOn  = btn.classList.contains('sort-toggle-active');
    var curDir = btn.getAttribute('data-sort-dir');
    var nextDir = wasOn ? (curDir === 'desc' ? 'asc' : 'desc') : 'desc';

    scope.querySelectorAll('.sort-toggle[data-sort-key]').forEach(function (b) {
      if (b === btn) return;
      setToggleState(b, false, null);
    });
    setToggleState(btn, true, nextDir);

    var key = btn.getAttribute('data-sort-key');
    tables.forEach(function (table) { sortTable(table, key, nextDir); });
  });
})();
