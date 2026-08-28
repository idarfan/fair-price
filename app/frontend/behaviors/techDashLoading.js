/**
 * 技術面儀表板：抓取進度與輪詢。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.csrf
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/technical_dashboard/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function () {
    var form    = document.getElementById('td-form');
    var btn     = document.getElementById('td-submit-btn');
    var loading = document.getElementById('td-loading');
    if (!form || !btn || !loading) return;

    // Auto-uppercase
    var inp = document.getElementById('td-symbol-input');
    if (inp) inp.addEventListener('input', function () { this.value = this.value.toUpperCase(); });

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var symbol = inp ? inp.value.trim().toUpperCase() : '';
      var dateEl = document.getElementById('td-date-input');
      var date   = dateEl ? dateEl.value : '';
      if (!symbol) return;

      // Show loading state immediately
      btn.disabled = true;
      btn.textContent = '分析中…';
      btn.classList.add('opacity-50', 'cursor-not-allowed');
      loading.classList.remove('hidden');
      loading.classList.add('flex');

      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var token = csrfToken ? csrfToken.content : (root.dataset.csrf || '');

      // POST to background analyze endpoint
      fetch('/technical_dashboard/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
        body: JSON.stringify({ symbol: symbol, date: date })
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (data.status === 'ready') {
          window.location.href = '/technical_dashboard?symbol=' + symbol + '&date=' + date;
          return;
        }
        var jobId = data.job_id;
        if (!jobId) {
          var qs = '?symbol=' + symbol + '&date=' + date;
          if (data.status) qs += '&job_status=' + data.status;
          window.location.href = '/technical_dashboard' + qs;
          return;
        }
        // Poll job status every 2.5s
        var attempts = 0;
        var pollInterval = setInterval(function () {
          attempts++;
          if (attempts > 60) { // 150s timeout
            clearInterval(pollInterval);
            window.location.href = '/technical_dashboard?symbol=' + symbol + '&date=' + date + '&job_status=error';
            return;
          }
          fetch('/technical_dashboard/status?job_id=' + jobId)
            .then(function(r) { return r.json(); })
            .then(function(s) {
              if (s.status === 'pending' || s.status === 'not_found') return; // keep polling
              clearInterval(pollInterval);
              var qs = '?symbol=' + symbol + '&date=' + date + '&job_status=' + s.status;
              window.location.href = '/technical_dashboard' + qs;
            })
            .catch(function () { /* keep polling on network error */ });
        }, 2500);
      })
      .catch(function () {
        // Network error — fallback to direct navigation
        window.location.href = '/technical_dashboard?symbol=' + symbol + '&date=' + date;
      });
    });
  })();
}
