/**
 * Daily Momentum：觀察清單的新增/編輯/排序。
 *
 * 稽核 H-3：原本內嵌在 app/components/daily_momentum/watchlist_manager_component.rb 的 heredoc 裡。
 * 這裡是「逐字搬移」——行為完全不變，只是離開 Ruby 字串、進到 Vite 打包與 ESLint 覆蓋範圍。
 * TODO：型別化成 .ts（strict 模式下這批共約 600 個「可能是 null」與隱含 any 要處理）。
 */

export function init() {
  (function() {
    // ── Stock logo fallback ───────────────────────────────────
    document.querySelectorAll('.stock-logo').forEach(function(img) {
      img.addEventListener('error', function() {
        var fallbackSrc = img.dataset.fallback;
        if (fallbackSrc && img.src !== fallbackSrc) {
          img.src = fallbackSrc;
        } else {
          img.style.display = 'none';
          var span = img.nextElementSibling;
          if (span) span.style.display = 'flex';
        }
      });
    });

    // ── Sortable drag & drop ──────────────────────────────────────
    var el = document.getElementById('watchlist-sortable');
    if (el && typeof Sortable !== 'undefined') {
      Sortable.create(el, {
        handle: '.drag-handle',
        animation: 150,
        ghostClass: 'bg-blue-50',
        onEnd: function() {
          var ids = Array.from(el.querySelectorAll('tr[data-id]')).map(function(tr) {
            return tr.dataset.id;
          });
          fetch('/momentum/watchlist/reorder', {
            method: 'PATCH',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
            },
            body: JSON.stringify({ ids: ids })
          });
        }
      });
    }

    // ── Edit / Cancel via event delegation ───────────────────────
    document.addEventListener('click', function(e) {
      var startBtn = e.target.closest('[data-start-edit]');
      if (startBtn) {
        var id = startBtn.dataset.startEdit;
        document.getElementById('view-' + id).classList.add('hidden');
        var form = document.getElementById('edit-form-' + id);
        form.classList.remove('hidden');
        var inp = form.querySelector('input[name="symbol"]');
        inp.focus(); inp.select();
        return;
      }

      var cancelBtn = e.target.closest('[data-cancel-edit]');
      if (cancelBtn) {
        var id = cancelBtn.dataset.cancelEdit;
        document.getElementById('view-' + id).classList.remove('hidden');
        document.getElementById('edit-form-' + id).classList.add('hidden');
        return;
      }

      // Delete confirm
      var delBtn = e.target.closest('button[data-confirm]');
      if (delBtn) {
        e.preventDefault();
        if (confirm(delBtn.dataset.confirm)) {
          delBtn.disabled = true;
          delBtn.style.opacity = '0.4';
          delBtn.closest('form').submit();
        }
      }
    });
  })();
}
