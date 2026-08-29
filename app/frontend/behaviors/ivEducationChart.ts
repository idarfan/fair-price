/**
 * 教學頁：Delta vs 履約價的示意圖。
 *
 * 稽核 H-3：原本內嵌在 app/components/iv_analysis/education_component.rb 的 heredoc 裡。
 * 用原生 Canvas 2D 繪製（不是 Chart.js），所以沒有 Chart 實例可查。
 */

export function init(): void {
  const canvas = document.getElementById("iv-delta-chart");
  if (!(canvas instanceof HTMLCanvasElement)) return;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const dpr = window.devicePixelRatio || 1;
  const cssW = canvas.clientWidth || 640;
  const cssH = 320;
  canvas.width = cssW * dpr;
  canvas.height = cssH * dpr;
  ctx.scale(dpr, dpr);

  const W = cssW, H = cssH;
  const pad = { top: 18, right: 24, bottom: 44, left: 52 };
  const cW = W - pad.left - pad.right;
  const cH = H - pad.top - pad.bottom;

  function normCDF(x: number): number {
    const t = 1 / (1 + 0.2316419 * Math.abs(x));
    const d = 0.3989422820 * Math.exp(-x * x / 2);
    const p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.7814779 + t * (-1.8212560 + t * 1.3302744))));
    return x >= 0 ? 1 - p : p;
  }
  function callDelta(S: number, K: number, sig: number, T: number): number {
    if (sig <= 0 || T <= 0) return K <= S ? 1.0 : 0.0;
    const d1 = (Math.log(S / K) + 0.5 * sig * sig * T) / (sig * Math.sqrt(T));
    return normCDF(d1);
  }

  const S = 100, T = 1.0;
  const Kmin = 60, Kmax = 150, steps = 300;
  const ivs = [
    { s: 0.10, c: "#58a6ff" }, { s: 0.30, c: "#3fb950" },
    { s: 0.50, c: "#d29922" }, { s: 0.80, c: "#bc8cff" },
  ];

  const toX = (K: number): number => pad.left + (K - Kmin) / (Kmax - Kmin) * cW;
  const toY = (delta: number): number => pad.top + (1 - delta) * cH;

  ctx.fillStyle = "#161b22";
  ctx.fillRect(0, 0, W, H);

  ctx.strokeStyle = "#21262d";
  ctx.lineWidth = 1;
  [0, 0.25, 0.5, 0.75, 1.0].forEach((y) => {
    const cy = toY(y);
    ctx.beginPath(); ctx.moveTo(pad.left, cy); ctx.lineTo(pad.left + cW, cy); ctx.stroke();
  });
  [70, 80, 90, 100, 110, 120, 130, 140].forEach((k) => {
    const cx = toX(k);
    ctx.beginPath(); ctx.moveTo(cx, pad.top); ctx.lineTo(cx, pad.top + cH); ctx.stroke();
  });

  // ATM（價平）虛線
  ctx.strokeStyle = "#444c56";
  ctx.setLineDash([5, 4]);
  ctx.lineWidth = 1.5;
  const ax = toX(100);
  ctx.beginPath(); ctx.moveTo(ax, pad.top); ctx.lineTo(ax, pad.top + cH); ctx.stroke();
  ctx.setLineDash([]);

  ctx.fillStyle = "#7d8590";
  ctx.font = "11px sans-serif";
  ctx.textAlign = "left";
  ctx.fillText("價平 ATM: 100", ax + 5, pad.top + 14);
  ctx.textAlign = "right";
  [0, 0.25, 0.5, 0.75, 1.0].forEach((y) => {
    ctx.fillText(y.toFixed(2), pad.left - 6, toY(y) + 4);
  });
  ctx.textAlign = "center";
  [70, 80, 90, 100, 110, 120, 130, 140].forEach((k) => {
    ctx.fillText(String(k), toX(k), pad.top + cH + 16);
  });
  ctx.fillStyle = "#9ca3af";
  ctx.font = "bold 11px sans-serif";
  ctx.fillText("履約價 Strike", pad.left + cW / 2, H - 6);
  ctx.save();
  ctx.translate(13, pad.top + cH / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.fillText("買權 Delta", 0, 0);
  ctx.restore();

  ivs.forEach((iv) => {
    ctx.beginPath();
    ctx.strokeStyle = iv.c;
    ctx.lineWidth = 2.5;
    ctx.shadowColor = iv.c;
    ctx.shadowBlur = 4;
    for (let i = 0; i <= steps; i++) {
      const K = Kmin + (Kmax - Kmin) * i / steps;
      const d = callDelta(S, K, iv.s, T);
      if (i === 0) ctx.moveTo(toX(K), toY(d));
      else ctx.lineTo(toX(K), toY(d));
    }
    ctx.stroke();
    ctx.shadowBlur = 0;
  });

  ctx.strokeStyle = "#30363d";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(pad.left, pad.top);
  ctx.lineTo(pad.left, pad.top + cH);
  ctx.lineTo(pad.left + cW, pad.top + cH);
  ctx.stroke();
}
