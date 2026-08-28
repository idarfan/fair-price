/**
 * 技術面儀表板：Max Pain 到期日篩選。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.symbol
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/technical_dashboard/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function () {
    var sym  = root.dataset.symbol;
    var base = '/technical_dashboard';
    function getFilters() {
      return {
        expiration: document.getElementById('mp-exp-'  + sym)?.value,
        strikes:    document.getElementById('mp-str-'  + sym)?.value,
        volume_oi:  document.getElementById('mp-oi-'   + sym)?.value
      };
    }
    function setLoading(on) {
      var el  = document.getElementById('mp-loading-' + sym);
      var err = document.getElementById('mp-error-'   + sym);
      if (el)  el.classList.toggle('hidden', !on);
      if (err) { err.classList.add('hidden'); err.textContent = ''; }
      ['mp-exp-', 'mp-str-', 'mp-oi-'].forEach(function (p) {
        var s = document.getElementById(p + sym); if (s) s.disabled = on;
      });
    }
    function showError(msg) {
      setLoading(false);
      var err = document.getElementById('mp-error-' + sym);
      if (err) { err.classList.remove('hidden'); err.textContent = msg; }
    }
    function redirectWithFilters(f) {
      var p = new URLSearchParams({
        symbol: sym, mp_expiration: f.expiration,
        mp_strikes: f.strikes, mp_vol_oi: f.volume_oi
      });
      window.location.href = base + '?' + p.toString();
    }
    function pollJob(jobId, f) {
      var attempts = 0;
      var timer = setInterval(function () {
        if (++attempts > 80) { clearInterval(timer); showError('抓取逾時，請重試'); return; }
        fetch(base + '/status?job_id=' + jobId)
          .then(function (r) { return r.json(); })
          .then(function (d) {
            if (d.status === 'pending' || d.status === 'not_found') return;
            clearInterval(timer);
            if (d.status === 'success') { redirectWithFilters(f); }
            else if (d.status === 'session_expired') { showError('Barchart 登入已過期，請重新登入後重試'); }
            else { showError('抓取失敗：' + (d.errors?.[0] || d.status)); }
          }).catch(function () {});
      }, 2000);
    }
    function triggerFetch() {
      var f = getFilters(); if (!f.expiration) return;
      setLoading(true);
      fetch(base + '/fetch_max_pain', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]')?.content },
        body: JSON.stringify({ symbol: sym, expiration: f.expiration, strikes: f.strikes, volume_oi: f.volume_oi })
      })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        if (d.status === 'ready') { redirectWithFilters(f); }
        else if (d.job_id) { pollJob(d.job_id, f); }
        else if (d.status === 'cdp_offline') { showError('CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動後重試'); }
        else { showError('請求失敗：' + (d.error || '未知錯誤')); }
      }).catch(function () { showError('網路錯誤，請重試'); });
    }
    ['mp-exp-', 'mp-str-', 'mp-oi-'].forEach(function (p) {
      var s = document.getElementById(p + sym);
      if (s) s.addEventListener('change', triggerFetch);
    });
  })();
}
