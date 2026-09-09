(function () {
  var R = 0.045, Q = 0.012;

  function erf(x) {
    var sign = x < 0 ? -1 : 1;
    x = Math.abs(x);
    var a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741,
        a4 = -1.453152027, a5 = 1.061405429, p = 0.3275911;
    var t = 1 / (1 + p * x);
    var y = 1 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);
    return sign * y;
  }
  function normCdf(x) { return 0.5 * (1 + erf(x / Math.SQRT2)); }

  function bsCall(S, K, T, r, sigma, q) {
    if (!(S > 0) || !(K > 0) || !(T > 0) || !(sigma > 0)) return null;
    var d1 = (Math.log(S / K) + (r - q + 0.5 * sigma * sigma) * T) / (sigma * Math.sqrt(T));
    var d2 = d1 - sigma * Math.sqrt(T);
    return S * Math.exp(-q * T) * normCdf(d1) - K * Math.exp(-r * T) * normCdf(d2);
  }

  var overlay = document.getElementById("leaps-price-estimator-overlay");
  if (!overlay) return;
  var info    = document.getElementById("leaps-pe-contract-info");
  var spotEl  = document.getElementById("leaps-pe-spot");
  var ivEl    = document.getElementById("leaps-pe-iv");
  var ivVal   = document.getElementById("leaps-pe-iv-value");
  var outMid       = document.getElementById("leaps-pe-result-mid");
  var outIntrinsic = document.getElementById("leaps-pe-result-intrinsic");
  var outTimeValue = document.getElementById("leaps-pe-result-time-value");
  var outDiff      = document.getElementById("leaps-pe-result-diff");

  var current = null; // { strike, dte, expiration, mid }

  function fmtMoney(v) { return isFinite(v) ? "$" + v.toFixed(2) : "—"; }

  // IV 顏色分級：與排行表 IV 欄位同一組門檻（見 components/.../formatting.rb
  // 的 iv_color_class）——≤30% 綠、30–50% 黃、>50% 紅。同一個數字在表格裡
  // 是紅的、在試算面板裡是黑的，會讓人以為兩邊算的不是同一件事。
  //
  // 門檻在兩處各寫一份是刻意的取捨：Ruby 端要在 SSR 時著色，JS 端要隨滑桿
  // 即時變色，共用一份得多開一個資料島或 API。兩邊都指向 formatting.rb 的
  // 註解，改動時看得到彼此。
  var IV_GREEN_MAX = 30, IV_YELLOW_MAX = 50;
  var IV_TONES = [ "green", "yellow", "red" ];

  function ivTone(pct) {
    if (!isFinite(pct)) return null;
    if (pct <= IV_GREEN_MAX) return IV_TONES[0];
    if (pct <= IV_YELLOW_MAX) return IV_TONES[1];
    return IV_TONES[2];
  }

  // 數字與滑桿一起變色。只染數字的話，數字紅了、軌道還是預設藍，
  // 看起來像兩個不相干的元件。
  function paintIv(pct) {
    var tone = ivTone(pct);
    IV_TONES.forEach(function (n) {
      if (ivVal) ivVal.classList.remove("leaps-pe-iv-" + n);
      if (ivEl) ivEl.classList.remove("leaps-pe-slider-" + n);
    });
    if (!tone) return;
    if (ivVal) ivVal.classList.add("leaps-pe-iv-" + tone);
    if (ivEl) ivEl.classList.add("leaps-pe-slider-" + tone);
  }

  function recompute() {
    if (!current) return;
    var S = parseFloat(spotEl.value);
    var ivPct = parseFloat(ivEl.value);
    var sigma = ivPct / 100;
    ivVal.textContent = ivPct.toFixed(1) + "%";
    paintIv(ivPct);
    var T = current.dte / 365.25;
    var mid = bsCall(S, current.strike, T, R, sigma, Q);
    if (mid === null) {
      outMid.textContent = outIntrinsic.textContent = outTimeValue.textContent = outDiff.textContent = "—";
      return;
    }
    var intrinsic = Math.max(0, S - current.strike);
    var timeValue = mid - intrinsic;
    outMid.textContent       = fmtMoney(mid);
    outIntrinsic.textContent = fmtMoney(intrinsic);
    outTimeValue.textContent = fmtMoney(timeValue);
    if (current.mid !== null && isFinite(current.mid)) {
      var diff = mid - current.mid;
      outDiff.textContent = (diff >= 0 ? "+" : "") + fmtMoney(diff);
    } else {
      outDiff.textContent = "—";
    }
  }

  function openModal(btn) {
    var strike = parseFloat(btn.dataset.strike);
    var spot   = parseFloat(btn.dataset.underlying);
    var iv     = parseFloat(btn.dataset.iv);
    var dte    = parseFloat(btn.dataset.dte);
    var mid    = parseFloat(btn.dataset.mid);
    current = {
      strike: strike, dte: dte,
      expiration: btn.dataset.expiration,
      mid: isFinite(mid) ? mid : null
    };
    info.textContent = "履約價 $" + strike.toFixed(2) + " · 到期日 " + btn.dataset.expiration +
      " · 原始 IV " + (isFinite(iv) ? iv.toFixed(1) : "—") + "% · 原始 Mid " +
      (isFinite(mid) ? "$" + mid.toFixed(2) : "—");
    spotEl.value = isFinite(spot) ? spot.toFixed(2) : "";
    // 帶入合約的原始 IV，保留小數位（data-iv 是 row[:iv] * 100 的完整精度，
    // 滑桿 step 0.1 會落在最近的 0.1，與表格 IV 欄顯示的一位小數一致）。
    // 起點就是這張合約現在的樣子，往左右拉才看得出「IV 變動對價格的影響」；
    // 從固定的 50% 起算，使用者得先自己把它調回原始值才能開始比較。
    ivEl.value = isFinite(iv) ? Math.min(Math.max(iv, 0), 100).toFixed(1) : "50";
    // 每次開啟都回到置中：記住上次位置的話，若上次拖到邊緣、之後換了
    // 較小的視窗，面板會開在看不見的地方。
    if (panel) {
      panel.classList.remove("leaps-pe-dragged");
      panel.style.left = panel.style.top = panel.style.width = "";
    }
    overlay.classList.remove("hidden");
    recompute();
  }

  function closeModal() { overlay.classList.add("hidden"); }

  // ── 拖動 ──────────────────────────────────────────────
  //
  // 面板預設由 overlay 的 flex 置中；被拖動之後改成 position:fixed 並由
  // left/top 決定位置（兩者不能並存，所以第一次拖動時要先把當下的實際
  // 座標寫進 style，再切換 class，否則面板會瞬移到左上角）。
  //
  // 位置不記憶：下次開啟回到置中。記住上次位置的話，若上次拖到螢幕邊緣、
  // 之後換了較小的視窗，面板會開在看不見的地方。
  var panel = document.getElementById("leaps-price-estimator-panel");
  var header = panel ? panel.querySelector(".leaps-pe-header") : null;
  var drag = null;

  function clamp(value, min, max) { return Math.min(Math.max(value, min), max); }

  function startDrag(e) {
    // 只有標題列可以拖；點到關閉鈕不算（否則按不到關閉）。
    if (e.target.closest(".leaps-pe-close")) return;
    if (e.button !== 0) return;

    var rect = panel.getBoundingClientRect();
    if (!panel.classList.contains("leaps-pe-dragged")) {
      panel.style.left = rect.left + "px";
      panel.style.top = rect.top + "px";
      panel.style.width = rect.width + "px";
      panel.classList.add("leaps-pe-dragged");
    }
    drag = { dx: e.clientX - rect.left, dy: e.clientY - rect.top, w: rect.width, h: rect.height };
    e.preventDefault();
  }

  function onDrag(e) {
    if (!drag) return;
    // 至少留 40px 在視窗內，否則可以把面板拖到完全看不見、也就抓不回來。
    var maxLeft = window.innerWidth - 40;
    var maxTop = window.innerHeight - 40;
    panel.style.left = clamp(e.clientX - drag.dx, 40 - drag.w, maxLeft) + "px";
    panel.style.top = clamp(e.clientY - drag.dy, 0, maxTop) + "px";
  }

  function endDrag() { drag = null; }

  if (header) {
    header.addEventListener("mousedown", startDrag);
    document.addEventListener("mousemove", onDrag);
    document.addEventListener("mouseup", endDrag);
  }

  document.addEventListener("click", function (e) {
    var btn = e.target.closest(".leaps-price-estimate-btn");
    if (btn) { openModal(btn); return; }
    if (e.target.closest("#leaps-pe-close")) { closeModal(); return; }
    // 原本「點 overlay 空白處關閉」已移除：overlay 現在是 pointer-events:none
    // 的定位層，收不到點擊；而且面板可拖動之後，使用者本來就會去點旁邊的
    // 表格做比較，那時關掉面板等於把他的比較對象弄丟。用關閉鈕或 Esc。
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && !overlay.classList.contains("hidden")) closeModal();
  });
  spotEl.addEventListener("input", recompute);
  ivEl.addEventListener("input", recompute);

  document.querySelectorAll(".leaps-col-toggle-checkbox").forEach(function (cb) {
    cb.addEventListener("change", function () {
      var key = cb.dataset.col;
      document.querySelectorAll('#leaps-ranking-table [data-col="' + key + '"]').forEach(function (el) {
        el.classList.toggle("leaps-col-hidden", !cb.checked);
      });
    });
  });
})();
