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

  function recompute() {
    if (!current) return;
    var S = parseFloat(spotEl.value);
    var sigma = parseFloat(ivEl.value) / 100;
    ivVal.textContent = parseFloat(ivEl.value).toFixed(1) + "%";
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
    ivEl.value = isFinite(iv) ? iv.toFixed(1) : "20";
    overlay.classList.remove("hidden");
    recompute();
  }

  function closeModal() { overlay.classList.add("hidden"); }

  document.addEventListener("click", function (e) {
    var btn = e.target.closest(".leaps-price-estimate-btn");
    if (btn) { openModal(btn); return; }
    if (e.target.closest("#leaps-pe-close")) { closeModal(); return; }
    if (e.target === overlay) { closeModal(); return; }
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
