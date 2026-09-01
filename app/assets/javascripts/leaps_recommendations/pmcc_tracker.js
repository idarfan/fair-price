/*
 * PMCC 部位追蹤的寫入操作（pmcc-tracker Phase 5）。
 *
 * Phlex 2.x 封鎖 on* 屬性，所以表單只放 data-pmcc-* 標記，行為全部靠這裡的
 * 委派監聽。所有請求都打 /api/v1/pmcc_positions，伺服器端一律從 current_user
 * 出發，前端拿不到也改不到別人的部位。
 */
(function () {
  function csrf() {
    var m = document.querySelector('meta[name="csrf-token"]');
    return m ? m.getAttribute('content') : '';
  }

  /* 收集同一個 [data-pmcc-form] 容器裡的所有欄位。空字串不送出——
     送空字串會讓「沒填」跟「填 0」在後端變成同一件事。 */
  function collect(form) {
    var payload = {};
    form.querySelectorAll('[data-pmcc-field]').forEach(function (el) {
      var v = el.value.trim();
      if (v !== '') payload[el.dataset.pmccField] = v;
    });
    return payload;
  }

  function post(url, payload, btn) {
    var original = btn.textContent;
    btn.disabled = true;
    btn.textContent = '處理中…';

    return fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-CSRF-Token': csrf()
      },
      credentials: 'same-origin',
      body: JSON.stringify(payload)
    }).then(function (res) {
      if (res.ok) { window.location.reload(); return; }
      return res.json().catch(function () { return {}; }).then(function (body) {
        throw new Error(body.error || ('HTTP ' + res.status));
      });
    }).catch(function (err) {
      btn.disabled = false;
      btn.textContent = original;
      window.alert('操作失敗：' + err.message);
    });
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest('[data-pmcc-action]');
    if (!btn) return;

    var action = btn.dataset.pmccAction;
    var form   = btn.closest('[data-pmcc-form]');
    if (!form) return;

    var payload = collect(form);

    if (action === 'create') {
      payload.ticker = form.dataset.pmccSymbol;
      post('/api/v1/pmcc_positions', payload, btn);
      return;
    }

    var scope = btn.closest('[data-pmcc-position-id]');
    if (!scope) return;
    var id = scope.dataset.pmccPositionId;

    /* 平倉與被指派會結束或改變部位狀態，先確認再送——這兩個動作寫進帳本
       之後要靠手動改資料才收得回來。 */
    if (action === 'close' && !window.confirm('確定要把長腳與短腳一起平倉？部位會結案。')) return;
    if (action === 'assign' && !window.confirm('確定短腳已被指派？')) return;

    post('/api/v1/pmcc_positions/' + id + '/' + action, payload, btn);
  });
})();
