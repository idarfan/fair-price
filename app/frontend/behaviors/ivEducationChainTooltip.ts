/**
 * 教學頁：期權鏈截圖的欄位說明 tooltip（滑鼠移到圖上的某一欄就顯示解釋）。
 *
 * 稽核 H-3：原本內嵌在 app/components/iv_analysis/education_component.rb 的 heredoc 裡。
 *
 * 型別化時把兩段逐字重複的邏輯（chain 圖與 barchart 圖）抽成
 * setupImageColumnTooltip()——兩者只差 DOM id 前綴、欄位邊界、欄位說明資料與
 * tooltip 的預設尺寸。欄位說明資料原封不動保留。
 */

interface ColumnInfo {
  num: string;
  en: string;
  zh: string;
  color: string;
  example: string;
  summary: string;
  bullets: string[];
}

interface ImageTooltipOptions {
  /** DOM id 前綴：'chain' 或 'barchart' */
  prefix: string;
  /** 各欄左邊界的百分比（長度 = 欄數 + 1） */
  bounds: number[];
  cols: ColumnInfo[];
  /** tooltip 尚未量到尺寸時的預設寬高 */
  defaultW: number;
  defaultH: number;
}

function setupImageColumnTooltip(opts: ImageTooltipOptions): void {
  const { prefix, bounds, cols, defaultW, defaultH } = opts;

  const wrapperEl = document.getElementById(`${prefix}-img-container`);
  const tipEl = document.getElementById(`${prefix}-col-tooltip`);
  const hlEl = document.getElementById(`${prefix}-col-hl`);
  if (!wrapperEl || !tipEl || !hlEl) return;
  // 明確型別的 const：narrowing 在巢狀 function declaration（posTip）裡不保證留存。
  const wrapper: HTMLElement = wrapperEl;
  const tip: HTMLElement = tipEl;
  const hl: HTMLElement = hlEl;

  const hdr = document.getElementById(`${prefix}-tt-hdr`);
  const num = document.getElementById(`${prefix}-tt-num`);
  const en = document.getElementById(`${prefix}-tt-en`);
  const zh = document.getElementById(`${prefix}-tt-zh`);
  const ex = document.getElementById(`${prefix}-tt-ex`);
  const sm = document.getElementById(`${prefix}-tt-sum`);
  const bl = document.getElementById(`${prefix}-tt-bul`);

  let lastCol = -1;

  function posTip(e: MouseEvent): void {
    let x = e.clientX + 20;
    let y = e.clientY - 20;
    const tw = tip.offsetWidth || defaultW;
    const th = tip.offsetHeight || defaultH;
    if (x + tw > window.innerWidth - 12) x = e.clientX - tw - 20;
    if (y + th > window.innerHeight - 12) y = window.innerHeight - th - 12;
    if (y < 8) y = 8;
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
  }

  function fillTip(col: ColumnInfo): void {
    if (hdr) hdr.style.background = col.color;
    if (num) num.textContent = col.num;
    if (en) en.textContent = col.en;
    if (zh) zh.textContent = col.zh;
    if (ex) ex.textContent = col.example;
    if (sm) sm.textContent = col.summary;
    if (bl) {
      bl.innerHTML = col.bullets.map((b) =>
        '<p style="display:flex;gap:4px;font-size:0.85rem;color:#6b7280;line-height:1.5">'
        + `<span style="color:${col.color};flex-shrink:0">›</span>${b}</p>`,
      ).join("");
    }
  }

  // 監聽整個容器——不論子元素透明度如何都收得到事件
  wrapper.style.cursor = "crosshair";

  wrapper.addEventListener("mousemove", (e) => {
    const rect = wrapper.getBoundingClientRect();
    const xPct = (e.clientX - rect.left) / rect.width * 100;
    let col = -1;
    for (let i = 0; i < bounds.length - 1; i++) {
      const lo = bounds[i];
      const hi = bounds[i + 1];
      if (lo === undefined || hi === undefined) continue;
      if (xPct >= lo && xPct < hi) { col = i; break; }
    }
    if (col < 0) {
      tip.classList.add("hidden");
      hl.style.opacity = "0";
      lastCol = -1;
      return;
    }
    const lo = bounds[col];
    const hi = bounds[col + 1];
    const info = cols[col];
    if (lo === undefined || hi === undefined || !info) return;

    // 更新欄位highlight
    hl.style.left = `${lo}%`;
    hl.style.width = `${hi - lo}%`;
    hl.style.opacity = "1";
    // 只在換欄時重填內容
    if (col !== lastCol) { fillTip(info); lastCol = col; }
    tip.classList.remove("hidden");
    posTip(e);
  });

  wrapper.addEventListener("mouseleave", () => {
    tip.classList.add("hidden");
    hl.style.opacity = "0";
    lastCol = -1;
  });
}

// 欄位左邊界百分比（由 1077px 原圖的像素分析得出）
const CHAIN_BOUNDS: number[] = [0, 8.3, 15.5, 22.5, 29.0, 35.3, 42.5, 49.0, 55.4, 62.2, 69.7, 77.7, 85.5, 93.0, 100];

const CHAIN_COLS: ColumnInfo[] = [
  { num:'①', en:'Strike',   zh:'行權價',      color:'#3b82f6', example:'$80.00',
    summary:'你有權以此價格買（Call）或賣（Put）股票。',
    bullets:['股價 > Strike → Call 在價內（ITM）','股價 < Strike → Put 在價內（ITM）','反之稱為價外（OTM）'] },
  { num:'②', en:'Latest',   zh:'最新成交價',   color:'#3b82f6', example:'$2.05',
    summary:'這份期權在市場上最後成交的價格，即買入需付的費用。',
    bullets:['1 份合約 = 100 股，費用 = Latest x 100 美元','流動性差時 Latest 可能遠離合理價','搭配 Theor. 確認定價是否合理'] },
  { num:'③', en:'Theor.',   zh:'理論價值',     color:'#8b5cf6', example:'$2.05',
    summary:'用 Black-Scholes 公式計算出來的「合理」期權價格。',
    bullets:['Latest = Theor. 流動性好，可放心交易','差距大代表 Bid/Ask 價差寬，進出成本高','常與 Latest 比較，判斷當前定價是否合理'] },
  { num:'④', en:'IV',       zh:'隱含波動率',   color:'#f59e0b', example:'57.42%',
    summary:'把市場成交價代入 B-S 公式反推出的波動率預期。',
    bullets:['IV 高期權貴，賣方策略（Wheel）有利','IV 低期權便宜，買方策略有利','IVR / IVP 正是衡量這個數字在歷史中的位置'] },
  { num:'⑤', en:'Delta',    zh:'方向敏感度',   color:'#10b981', example:'-0.4482',
    summary:'股價每漲 $1，期權價格的理論變化量（Put Delta 為負值）。',
    bullets:[
      'Call: 0~1（正值）；Put: −1~0（負值）',
      'ATM ≈ ±0.50，也近似「到期在價內的機率」',
      '─ 計算範例（Delta = −0.4482 的 Put）─',
      '股價跌 $1 → −0.4482 × (−1) = 期權漲 +$0.4482',
      '股價漲 $1 → −0.4482 × (+1) = 期權跌 −$0.4482',
      '⚠ 理論值（瞬間線性估計）：實際還要考慮',
      'Gamma（Delta 本身隨股價移動而改變）',
      'Theta（時間流逝侵蝕價值）',
      'Bid/Ask 價差 — 股價大幅波動時誤差更大'
    ] },
  { num:'⑥', en:'Gamma',    zh:'Delta 加速度', color:'#10b981', example:'0.0094',
    summary:'股價每漲 $1，Delta 本身的變化量。',
    bullets:['越接近到期且接近 ATM，Gamma 越大','買方：方向對了，獲利會加速放大','賣方：方向逆轉時 Delta 快速擴大，風險上升'] },
  { num:'⑦', en:'Theta',    zh:'每日時間耗損', color:'#ef4444', example:'-0.0408',
    summary:'期權每過一天，價值自動減少（即使股價沒動）。買方受害，賣方（你）受益。',
    bullets:['買方：每天醒來期權自動貶值，即使股價完全沒動','賣方範例：Short Put $14 市價 $1.00（純時間價值）','今天 $1.00 → 明天 $0.97（+$30）→ 後天 $0.94（再 +$30）','每天睡一覺起來自動多賺，直到歸零','越接近到期 Theta 越大，快到期 OTM 可能一夜變廢紙'] },
  { num:'⑧', en:'Vega',     zh:'波動率敏感度', color:'#f59e0b', example:'0.0972',
    summary:'IV 每上升 1%，期權價值的理論變化。',
    bullets:['買方持有正 Vega：IV 漲受益、IV 跌受損','財報後 IV 崩潰（IV Crush）是正 Vega 的大陷阱','方向做對了，IV 暴跌仍可能讓期權虧損'] },
  { num:'⑨', en:'Rho',      zh:'利率敏感度',   color:'#6b7280', example:'-0.0273',
    summary:'無風險利率每上升 1%，期權價值的變化。',
    bullets:['日常交易中影響最小，通常可忽略','持有 LEAPS 長期期權時才需注意','升息環境：Call 略漲，Put 略跌'] },
  { num:'⑩', en:'Volume',   zh:'當日成交量',   color:'#0ea5e9', example:'60',
    summary:'今天共有多少份合約在市場上成交。',
    bullets:['Volume 高代表活絡，容易以合理價成交','Volume 低時 Bid/Ask 差大，實際成交成本高','搭配 Open Int 一起判斷市場熱度'] },
  { num:'⑪', en:'Open Int', zh:'未平倉量',     color:'#0ea5e9', example:'792',
    summary:'目前市場上尚未結算的合約總量。',
    bullets:['大代表流動性好，有足夠對手盤','增加代表有新倉位建立，資金進場','減少代表有人平倉或合約到期結算'] },
  { num:'⑫', en:'Vol/OI',   zh:'當日交投比',   color:'#0ea5e9', example:'0.08',
    summary:'Volume 除以 Open Interest，衡量今日活躍程度。',
    bullets:['比值突然偏高，可能有大戶或消息面在動','是觀察異常佈局的快速指標','正常情況下多在 0.05~0.2 之間'] },
  { num:'⑬', en:'ITM Prob', zh:'到期價內機率', color:'#8b5cf6', example:'18.21%',
    summary:'到期時「處於價內」的估計機率，由 Delta 近似計算。',
    bullets:['賣 CSP 常選 ITM Prob < 20% 的 Strike','約 80% 機率讓期權到期歸零，收全額權利金','直接以機率角度判斷勝率，最直觀'] },
  { num:'⑭', en:'Type',     zh:'合約類型',     color:'#64748b', example:'Put',
    summary:'標示這份合約是看漲（Call）還是看跌（Put）。',
    bullets:['Call：有權以 Strike 買入股票','Put：有權以 Strike 賣出股票','Wheel：賣 Put（CSP）被行使後再賣 Covered Call'] }
];

// 欄位邊界（%）——由 1631px 原圖的像素分析得出
// 20 欄：Links | Type | Latest | Bid | Ask | Change | Volume | Open Int | IV | Last Trade
//        | Strike |
//        Type | Latest | Bid | Ask | Change | Volume | Open Int | IV | Last Trade（Puts）
const BARCHART_BOUNDS: number[] = [0, 3.7, 9.2, 17.1, 21.5, 26.4, 32.0, 39.5, 45.5, 49.6, 53.8, 58.7, 62.1, 65.8, 69.7, 73.5, 77.0, 81.0, 88.7, 92.0, 100];

const BARCHART_COLS: ColumnInfo[] = [
  { num:'①', en:'Links', zh:'圖表連結', color:'#64748b', example:'🔗',
    summary:'每列左側的圖示連結，點擊可直接進入該合約的走勢圖或下單介面。',
    bullets:['Click → 查看單一期權的歷史 IV 走勢圖', '方便快速進入 Calls 或 Puts 的交易頁面'] },
  { num:'②', en:'Type', zh:'合約類型（Calls）', color:'#3b82f6', example:'C',
    summary:'C = Call（買權），表示這是 Calls 那一側的合約。',
    bullets:['Call 給你「以 Strike 買入股票」的權利', 'Barchart 左半部全為 Call 合約', '搭配 Strike 判斷是否在價內（ITM）'] },
  { num:'③', en:'Latest', zh:'最新成交價（Call）', color:'#3b82f6', example:'$2.05',
    summary:'這份 Call 期權最近一筆成交的市場價格。',
    bullets:['1 合約 = 100 股，實際費用 = Latest × 100', '流動性差時 Latest 可能遠離中間報價', '搭配 Bid/Ask 確認成交是否合理'] },
  { num:'④', en:'Bid', zh:'買入出價（Call）', color:'#3b82f6', example:'$1.90',
    summary:'市場上最高的買入報價（做市商願意以此價格收購你的合約）。',
    bullets:['賣出合約時通常以 Bid 成交', 'Bid 越接近 Ask 代表流動性越好', 'Bid/Ask 差大時實際進出成本高'] },
  { num:'⑤', en:'Ask', zh:'賣出要價（Call）', color:'#3b82f6', example:'$2.10',
    summary:'市場上最低的賣出報價（需支付此價格才能買入合約）。',
    bullets:['買入合約時通常以 Ask 成交', '中間價 Mid = (Bid + Ask) / 2，可嘗試掛在此', 'Ask 遠高於 Bid → 流動性差，避免市價單'] },
  { num:'⑥', en:'Change', zh:'價格變動（Call）', color:'#f59e0b', example:'+$0.15',
    summary:'相對前一交易日收盤價的漲跌幅。',
    bullets:['正值（綠色）= Call 漲價，隱含 IV 或股價走高', '負值（紅色）= Call 跌價，股價下跌或 IV 壓縮', '觀察 Change 可判斷市場方向情緒'] },
  { num:'⑦', en:'Volume', zh:'當日成交量（Call）', color:'#0ea5e9', example:'230',
    summary:'今日這份 Call 合約的成交總量（合約數）。',
    bullets:['Volume 高 → 市場活躍，Bid/Ask 差窄', 'Volume 低 → 流動性差，避免大量進出', '突然大量 Volume → 可能有機構佈局或消息面'] },
  { num:'⑧', en:'Open Int', zh:'未平倉量（Call）', color:'#0ea5e9', example:'1,820',
    summary:'目前市場上這份 Call 合約尚未結算的總量。',
    bullets:['Open Int 大 → 流動性好，容易找到對手盤', '搭配 Volume 一起看：Volume 遠大於 OI 代表今天進了大量新倉', '減少代表有人平倉或合約到期'] },
  { num:'⑨', en:'IV', zh:'隱含波動率（Call）', color:'#f59e0b', example:'58.3%',
    summary:'這份 Call 合約的隱含波動率，由市場價格反推而來。',
    bullets:['IV 高 → 合約偏貴，賣 Covered Call 有利', 'ATM 附近 IV 最低；深 ITM / OTM 的 IV 會偏高（IV Skew）', '與 HV 比較：IV > HV → 賣方有優勢'] },
  { num:'⑩', en:'Last Trade', zh:'最後成交時間（Call）', color:'#64748b', example:'05/13 10:32',
    summary:'這份 Call 合約最近一次成交的日期與時間。',
    bullets:['時間久遠代表流動性差、很久沒有成交', '配合 Volume 判斷：Low Volume + 舊 Last Trade = 避開', '活絡合約通常當天就有多筆成交'] },
  { num:'⑪', en:'Strike', zh:'行權價（中央軸）', color:'#7c3aed', example:'$80.00',
    summary:'這列期權的行權價，是 Calls 與 Puts 共用的核心基準價格。',
    bullets:['股價 > Strike → Call ITM（有內在價值）', '股價 < Strike → Put ITM（有內在價值）', 'ATM Strike 是波動率最集中的區域，也是 Wheel 策略最常選擇的位置'] },
  { num:'⑫', en:'Type', zh:'合約類型（Puts）', color:'#ef4444', example:'P',
    summary:'P = Put（賣權），表示這是 Puts 那一側的合約。',
    bullets:['Put 給你「以 Strike 賣出股票」的權利', 'Barchart 右半部全為 Put 合約', 'Wheel 的 CSP（現金擔保賣權）即是賣出 Put'] },
  { num:'⑬', en:'Latest', zh:'最新成交價（Put）', color:'#ef4444', example:'$1.85',
    summary:'這份 Put 期權最近一筆成交的市場價格。',
    bullets:['Put Latest 通常隨股價下跌而上漲', '1 合約 = 100 股，Wheel 收到的權利金 = Latest × 100', '流動性差時避免市價單'] },
  { num:'⑭', en:'Bid', zh:'買入出價（Put）', color:'#ef4444', example:'$1.75',
    summary:'市場最高買入報價，賣出 Put 時通常以此成交。',
    bullets:['賣 CSP 時以 Bid 成交，實際收到的權利金', 'Bid/Ask 差越小越好，進出成本低', '可嘗試掛 Mid 價，通常也能成交'] },
  { num:'⑮', en:'Ask', zh:'賣出要價（Put）', color:'#ef4444', example:'$1.95',
    summary:'市場最低賣出報價，買入 Put 時需支付此價格。',
    bullets:['保護性買 Put（Protective Put）用 Ask 進場', 'Bid/Ask 差大的 Put → 流動性差，避免買入', 'Mid = (Bid+Ask)/2 是最佳掛單目標'] },
  { num:'⑯', en:'Change', zh:'價格變動（Put）', color:'#f59e0b', example:'-$0.10',
    summary:'Put 合約相對前一交易日的價格變化。',
    bullets:['股價下跌時 Put 通常漲價（負 Change 代表股價漲）', '觀察 Put Change 可判斷市場對下行風險的憂慮程度', '財報前後 Put Change 常非常劇烈'] },
  { num:'⑰', en:'Volume', zh:'當日成交量（Put）', color:'#0ea5e9', example:'520',
    summary:'今日這份 Put 合約的成交總量。',
    bullets:['Put Volume 暴增可能反映大戶買保護或押注下跌', '與 Call Volume 比較：Put/Call Ratio 是市場情緒指標', 'Wheel 賣 CSP 選擇 Volume > 100 的合約較安全'] },
  { num:'⑱', en:'Open Int', zh:'未平倉量（Put）', color:'#0ea5e9', example:'3,240',
    summary:'這份 Put 合約目前未平倉的總合約數。',
    bullets:['Open Int 大 → 流動性好，容易以合理價成交', '選 CSP 執行價時常參考 Open Int 找支撐位', '大量 Open Int 聚集的 Strike 常形成支撐或阻力'] },
  { num:'⑲', en:'IV', zh:'隱含波動率（Put）', color:'#f59e0b', example:'61.2%',
    summary:'這份 Put 的隱含波動率，反映市場對下行風險的定價。',
    bullets:['Put IV 通常略高於 Call IV（Skew 效應）', 'Put IV 越高 → CSP 權利金越豐厚', 'IV 高位（IVR > 60%）賣 Put 是 Wheel 黃金時機'] },
  { num:'⑳', en:'Last Trade', zh:'最後成交時間（Put）', color:'#64748b', example:'05/13 09:45',
    summary:'這份 Put 合約最近一次成交的時間。',
    bullets:['時間久遠 = 流動性差，賣出時難找買家', 'Wheel 選 CSP 要選當天有成交紀錄的 Strike', '配合 Volume / Open Int 三項合一判斷流動性'] }
];

export function init(): void {
  setupImageColumnTooltip({
    prefix: "chain", bounds: CHAIN_BOUNDS, cols: CHAIN_COLS,
    defaultW: 300, defaultH: 160,
  });
  setupImageColumnTooltip({
    prefix: "barchart", bounds: BARCHART_BOUNDS, cols: BARCHART_COLS,
    defaultW: 320, defaultH: 180,
  });
}
