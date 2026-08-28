/**
 * 教學頁：示意圖表。
 *
 * 稽核 H-3：原本內嵌在 app/components/iv_analysis/education_component.rb 的 heredoc 裡。
 * 這裡是「逐字搬移」——行為完全不變，只是離開 Ruby 字串、進到 Vite 打包與 ESLint 覆蓋範圍。
 * TODO：型別化成 .ts（strict 模式下這批共約 600 個「可能是 null」與隱含 any 要處理）。
 */

export function init() {
  (function () {
    var canvas = document.getElementById('iv-delta-chart');
    if (!canvas) return;
    var ctx = canvas.getContext('2d');

    var dpr  = window.devicePixelRatio || 1;
    var cssW = canvas.clientWidth || 640;
    var cssH = 320;
    canvas.width  = cssW * dpr;
    canvas.height = cssH * dpr;
    ctx.scale(dpr, dpr);

    var W = cssW, H = cssH;
    var pad = { top: 18, right: 24, bottom: 44, left: 52 };
    var cW  = W - pad.left - pad.right;
    var cH  = H - pad.top  - pad.bottom;

    function normCDF(x) {
      var t = 1 / (1 + 0.2316419 * Math.abs(x));
      var d = 0.3989422820 * Math.exp(-x * x / 2);
      var p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.7814779 + t * (-1.8212560 + t * 1.3302744))));
      return x >= 0 ? 1 - p : p;
    }
    function callDelta(S, K, sig, T) {
      if (sig <= 0 || T <= 0) return K <= S ? 1.0 : 0.0;
      var d1 = (Math.log(S / K) + 0.5 * sig * sig * T) / (sig * Math.sqrt(T));
      return normCDF(d1);
    }

    var S = 100, T = 1.0;
    var Kmin = 60, Kmax = 150, steps = 300;
    var ivs = [
      { s: 0.10, c: '#58a6ff' }, { s: 0.30, c: '#3fb950' },
      { s: 0.50, c: '#d29922' }, { s: 0.80, c: '#bc8cff' }
    ];

    function toX(K)     { return pad.left + (K - Kmin) / (Kmax - Kmin) * cW; }
    function toY(delta) { return pad.top  + (1 - delta) * cH; }

    ctx.fillStyle = '#161b22';
    ctx.fillRect(0, 0, W, H);

    ctx.strokeStyle = '#21262d'; ctx.lineWidth = 1;
    [0, 0.25, 0.5, 0.75, 1.0].forEach(function(y) {
      var cy = toY(y);
      ctx.beginPath(); ctx.moveTo(pad.left, cy); ctx.lineTo(pad.left + cW, cy); ctx.stroke();
    });
    [70,80,90,100,110,120,130,140].forEach(function(k) {
      var cx = toX(k);
      ctx.beginPath(); ctx.moveTo(cx, pad.top); ctx.lineTo(cx, pad.top + cH); ctx.stroke();
    });

    // ATM（價平）dashed line
    ctx.strokeStyle = '#444c56'; ctx.setLineDash([5,4]); ctx.lineWidth = 1.5;
    var ax = toX(100);
    ctx.beginPath(); ctx.moveTo(ax, pad.top); ctx.lineTo(ax, pad.top + cH); ctx.stroke();
    ctx.setLineDash([]);

    ctx.fillStyle = '#7d8590'; ctx.font = '11px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('價平 ATM: 100', ax + 5, pad.top + 14);
    ctx.textAlign = 'right';
    [0, 0.25, 0.5, 0.75, 1.0].forEach(function(y) {
      ctx.fillText(y.toFixed(2), pad.left - 6, toY(y) + 4);
    });
    ctx.textAlign = 'center';
    [70,80,90,100,110,120,130,140].forEach(function(k) {
      ctx.fillText(k, toX(k), pad.top + cH + 16);
    });
    ctx.fillStyle = '#9ca3af'; ctx.font = 'bold 11px sans-serif';
    ctx.fillText('履約價 Strike', pad.left + cW / 2, H - 6);
    ctx.save(); ctx.translate(13, pad.top + cH / 2); ctx.rotate(-Math.PI/2);
    ctx.fillText('買權 Delta', 0, 0); ctx.restore();

    ivs.forEach(function(iv) {
      ctx.beginPath(); ctx.strokeStyle = iv.c; ctx.lineWidth = 2.5;
      ctx.shadowColor = iv.c; ctx.shadowBlur = 4;
      for (var i = 0; i <= steps; i++) {
        var K = Kmin + (Kmax - Kmin) * i / steps;
        var d = callDelta(S, K, iv.s, T);
        i === 0 ? ctx.moveTo(toX(K), toY(d)) : ctx.lineTo(toX(K), toY(d));
      }
      ctx.stroke(); ctx.shadowBlur = 0;
    });

    ctx.strokeStyle = '#30363d'; ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(pad.left, pad.top); ctx.lineTo(pad.left, pad.top + cH);
    ctx.lineTo(pad.left + cW, pad.top + cH); ctx.stroke();
  })();
}
