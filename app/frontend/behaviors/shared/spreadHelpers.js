/**
 * 兩支價差試算頁（Bull Put / Bull Call）共用的小工具（稽核 M-6）。
 *
 * 這兩頁的差異幾乎只在 DOM id 的前綴（`bpus-` / `bcvs-`）與路由，所以用
 * prefix 參數化，行為與各自原本的實作完全一致。業務流程（選腳、推薦、試算、
 * 修復模式）留在各自的模組裡，那些是真的不一樣的東西。
 *
 * TODO：型別化成 .ts。
 */

/**
 * @param {{ prefix: string, statusPath: string }} options
 *   prefix     — DOM id 前綴，'bpus' 或 'bcvs'
 *   statusPath — 輪詢 job 狀態的路由（各頁的 CFG.routes.status）
 */
export function createSpreadHelpers(options) {
  var prefix = options.prefix;
  var statusPath = options.statusPath;

  function id(suffix) {
    return document.getElementById(prefix + "-" + suffix);
  }

  function csrf() {
    var m = document.querySelector('meta[name="csrf-token"]');
    return m ? m.content : "";
  }

  // `typeof n === 'number'` 已經排除 null（typeof null 是 'object'），所以
  // bcvs 版本原本多寫的 `&& n !== null` 永遠不會成立，合併時一併移除。
  function fmt(n) {
    return typeof n === "number" && !isNaN(n) ? n.toFixed(2) : "—";
  }

  function fmtLots(perLot, lots) {
    if (typeof perLot !== "number" || isNaN(perLot)) return "—";
    if (lots <= 1) return "$" + fmt(perLot);
    return "$" + fmt(perLot) + " × " + lots + " = $" + fmt(perLot * lots);
  }

  function currentLots() {
    var el = id("lots-input");
    var n = el ? parseInt(el.value, 10) : 1;
    return !n || n < 1 ? 1 : n;
  }

  // 進度條只需要顯示：每條路徑在 showProgress() 之後都是整頁導覽，
  // 頁面直接被銷毀，所以沒有對應的 hideProgress。
  function showProgress() {
    var bar = id("progress");
    if (bar) bar.classList.remove("hidden");
  }

  // 每 2 秒問一次 job 狀態，最多 60 次（2 分鐘）後以 'error' 收尾。
  function pollJob(jobId, onDone) {
    var attempts = 0;
    var timer = setInterval(function () {
      if (++attempts > 60) {
        clearInterval(timer);
        onDone("error");
        return;
      }
      fetch(statusPath + "?job_id=" + jobId)
        .then(function (r) {
          return r.json();
        })
        .then(function (d) {
          if (d.status === "pending" || d.status === "not_found") return;
          clearInterval(timer);
          onDone(d.status);
        })
        .catch(function () {});
    }, 2000);
  }

  return {
    id: id,
    csrf: csrf,
    fmt: fmt,
    fmtLots: fmtLots,
    currentLots: currentLots,
    showProgress: showProgress,
    pollJob: pollJob,
  };
}
