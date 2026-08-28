/**
 * LEAPS 推薦：抓取進度與輪詢。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.csrf
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/leaps_recommendations/page_header.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function () {
    var form    = document.getElementById('leaps-form');
    var btn     = document.getElementById('leaps-submit-btn');
    var loading = document.getElementById('leaps-loading');
    if (!form || !btn || !loading) return;

    var inp = document.getElementById('leaps-symbol-input');
    var strikeInp = document.getElementById('leaps-strike-input');
    var strikeErr = document.getElementById('leaps-strike-error');

    if (inp) {
      inp.addEventListener('input', function () {
        this.value = this.value.toUpperCase();
        // Clear strike and error when symbol changes (snapshot no longer valid)
        if (strikeInp) strikeInp.value = '';
        if (strikeErr) { strikeErr.classList.add('hidden'); strikeErr.textContent = ''; }
      });
    }

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var symbol = inp ? inp.value.trim().toUpperCase() : '';
      if (!symbol) return;

      if (strikeErr) { strikeErr.classList.add('hidden'); strikeErr.textContent = ''; }
      var userStrike = strikeInp ? strikeInp.value.trim() : '';

      btn.disabled = true;
      btn.textContent = '查詢中…';
      btn.classList.add('opacity-50', 'cursor-not-allowed');
      loading.classList.remove('hidden');
      loading.classList.add('flex');

      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var token = csrfToken ? csrfToken.content : (root.dataset.csrf || '');

      var strikeSuffix = userStrike ? '&user_strike=' + encodeURIComponent(userStrike) : '';

      var body = { symbol: symbol };
      if (userStrike) body.user_strike = userStrike;

      fetch('/leaps/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
        body: JSON.stringify(body)
      })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (data.status === 'ready') {
          window.location.href = '/leaps?symbol=' + symbol + strikeSuffix;
          return;
        }
        if (data.status === 'cdp_offline') {
          window.location.href = '/leaps?symbol=' + symbol + '&job_status=cdp_offline' + strikeSuffix;
          return;
        }
        if (data.status === 'invalid_strike') {
          // Show inline error, re-enable form
          if (strikeErr) {
            strikeErr.textContent = data.message || '履約價不在有效範圍，請重新輸入。';
            strikeErr.classList.remove('hidden');
          }
          btn.disabled = false;
          btn.textContent = '查詢';
          btn.classList.remove('opacity-50', 'cursor-not-allowed');
          loading.classList.add('hidden');
          loading.classList.remove('flex');
          return;
        }
        var jobId = data.job_id;
        if (!jobId) {
          window.location.href = '/leaps?symbol=' + symbol + '&job_status=error' + strikeSuffix;
          return;
        }
        var attempts = 0;
        var pollInterval = setInterval(function () {
          attempts++;
          if (attempts > 240) {
            clearInterval(pollInterval);
            window.location.href = '/leaps?symbol=' + symbol + '&job_status=error' + strikeSuffix;
            return;
          }
          fetch('/leaps/status?job_id=' + jobId)
            .then(function (r) { return r.json(); })
            .then(function (s) {
              if (s.status === 'pending' || s.status === 'not_found') return;
              clearInterval(pollInterval);
              window.location.href = '/leaps?symbol=' + symbol + '&job_status=' + s.status + strikeSuffix;
            }).catch(function () {});
        }, 2500);
      }).catch(function () {
        window.location.href = '/leaps?symbol=' + symbol + '&job_status=error' + strikeSuffix;
      });
    });
  })();
}
