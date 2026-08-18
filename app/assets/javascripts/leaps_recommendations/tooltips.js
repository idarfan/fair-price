(function () {
  var LEAPS_COL_EXPLAIN = {
    expiration:     { el: '#leaps-th-expiration',     title: '📅 Expiration',           desc: '合約到期日。LEAPS 慣例為一年以上，本表只列 364 天以上。', side: 'bottom' },
    dte:            { el: '#leaps-th-dte',            title: '⏱ Days to Expiration',    desc: '距到期天數。364–550 近天期、550+ 遠天期；越長時間緩衝越大，Vega 曝險也越高。', side: 'bottom' },
    strike:         { el: '#leaps-th-strike',         title: '🎯 Strike',               desc: '約定買入股價。深價內的 Call 行為越接近持有正股。', side: 'bottom' },
    delta:          { el: '#leaps-th-delta',          title: '⚡ Delta',                 desc: '股價每動 $1 權利金的理論變化。本表篩 Delta ≥ 0.60；越接近 1 越像股票替代品，槓桿越低但越穩。', side: 'bottom' },
    oi:             { el: '#leaps-th-oi',             title: '🔓 Open Interest',        desc: '未平倉合約數，本表排序主鍵。OI 高流動性通常較好；只在盤後更新。', side: 'bottom' },
    volume:         { el: '#leaps-th-volume',         title: '📊 Volume',               desc: '當日成交量（即時）。OI 高但 Volume 長期為零，進出仍可能困難。', side: 'bottom' },
    liquidity:      { el: '#leaps-th-liquidity',      title: '🚦 流動性判斷',            desc: '依本次查詢候選的 OI 三分位相對排名（充足/普通/偏低），非固定門檻；「⚠ 近期無成交」由 Vol/OI 比率判斷。', side: 'bottom' },
    bid:            { el: '#leaps-th-bid',            title: '⬇️ Bid',                  desc: '市場最高買價（賣出時的底價參考）。', side: 'bottom' },
    ask:            { el: '#leaps-th-ask',            title: '⬆️ Ask',                  desc: '市場最低賣價（買入時的天花板參考）。', side: 'bottom' },
    mid:            { el: '#leaps-th-mid',            title: '⚖️ Mid',                  desc: '(Bid+Ask)/2，掛限價單參考價。本系統衍生欄位一律以 Mid 為權利金基準，不用可能過時的最後成交價。', side: 'bottom' },
    spread:         { el: '#leaps-th-spread',         title: '↔️ Spread%',              desc: '(Ask−Bid)/Mid，一次進出的滑價成本。深價內常偏寬，>10% 要注意。', side: 'bottom' },
    intrinsic:      { el: '#leaps-th-intrinsic',      title: '💎 Intrinsic Value',      desc: 'max(0, 現價−履約價)，權利金裡「已在錢裡」的部分，股價不動也不流失。', side: 'bottom' },
    extrinsic:      { el: '#leaps-th-extrinsic',      title: '🎈 Extrinsic Value',      desc: 'Mid−內在價值，時間＋波動率溢價（保險費），隨時間與 IV 回落流失。', side: 'bottom' },
    extrinsic_pct:  { el: '#leaps-th-extrinsic_pct',  title: '🧮 外在佔比',              desc: '外在÷Mid，「權利金裡幾 % 是保險費」。深 ITM LEAPS 核心指標：越低越接近持股替代，高 IV 環境尤其要壓低。', side: 'bottom' },
    time_value_pct: { el: '#leaps-th-time_value_pct', title: '📐 Time Value%',          desc: '外在÷股價，「相對直接持股多付幾 % 溢價」。與外在佔比分母不同，回答不同問題。', side: 'bottom' },
    iv:             { el: '#leaps-th-iv',             title: '🌊 Implied Volatility',   desc: '該檔位隱含波動率。IV 越高權利金越貴；高 IV 買 LEAPS 要留意回落侵蝕（搭配 Vega）。', side: 'bottom' },
    vega:           { el: '#leaps-th-vega',           title: '🌀 Vega',                 desc: 'IV 每變 1% 權利金的理論變化。DTE 越長 Vega 越大；IV Crush 風險量化：IV 回落 10% ≈ 損失 Vega×10。', side: 'bottom' },
    itm_prob:       { el: '#leaps-th-itm_prob',       title: '🎲 ITM Probability',      desc: 'Barchart 估到期價內機率。買方視角＝到期仍有內在價值的機率，與 Delta 相關但獨立模型計算。', side: 'bottom' },
    f_type:         { el: '#leaps-th-f_type',         title: '🏷 Type',                 desc: 'Call（買權）或 Put（賣權）。搭配 Side 與方向欄一起判讀該筆大單的多空含義。', side: 'bottom' },
    f_strike:       { el: '#leaps-th-f_strike',       title: '🎯 Strike',               desc: '該筆成交合約的履約價。', side: 'bottom' },
    f_expiration:   { el: '#leaps-th-f_expiration',   title: '📅 Expiration',           desc: '該筆成交合約的到期日。本面板不限 LEAPS，任何到期日都會入榜。', side: 'bottom' },
    f_dte:          { el: '#leaps-th-f_dte',          title: '⏱ DTE',                   desc: '距到期天數。與排行表的 364 天門檻無關，這裡看的是當天市場在哪些天期活動。', side: 'bottom' },
    f_delta:        { el: '#leaps-th-f_delta',        title: '⚡ Delta',                 desc: '正值=Call、負值=Put；絕對值越大越深價內。', side: 'bottom' },
    f_code:         { el: '#leaps-th-f_code',         title: '🏳 Code',                 desc: '交易所成交代碼。標準單腿代碼可信；AUTO／多腿類（SLAN、MLET、ISOI 等）標記普遍缺失，判讀需保守。', side: 'bottom' },
    f_size:         { el: '#leaps-th-f_size',         title: '📦 Size',                 desc: '該筆成交口數（1 口 = 100 股）。', side: 'bottom' },
    f_side:         { el: '#leaps-th-f_side',         title: '↕️ Side',                 desc: '成交價位置：靠 bid=賣方主動（偏空）、靠 ask=買方主動（偏多）、mid=中性。', side: 'bottom' },
    f_premium:      { el: '#leaps-th-f_premium',      title: '💰 Premium',              desc: '該筆成交的權利金總額。本面板依 Premium 降序取前 20 筆。', side: 'bottom' },
    f_direction:    { el: '#leaps-th-f_direction',    title: '🧭 方向',                  desc: '綜合 Type／Side／Code 的看多/看空/中性判讀。情緒參考，不參與排行排序。', side: 'bottom' },
    /* PMCC v3 §9.1 表格欄位教學。這批沒有 el（表格每個到期日桶各渲染一次，
       同一個 key 的 th 出現三次，沒有唯一 id 可對應）——點擊時改用被點到的
       元素本身當 popover 目標（見下方 click handler），不查表；因此也不放進
       TOUR_ORDER（28 步全覽需要每個 key 對應唯一一個元素）。 */
    pmcc_kl:         { title: '🔵 KL（LEAPS 履約價）',      desc: 'Long Call 的履約價，黃金法則公式裡的 KL。深 ITM 越接近持股替代。', side: 'bottom' },
    pmcc_pl:         { title: '💵 PL（LEAPS Mid）',        desc: 'Long Call 的權利金（Mid 基準），黃金法則公式裡的 PL，也是實際買入成本／張。', side: 'bottom' },
    pmcc_long_dte:   { title: '⏱ Long DTE',               desc: 'LEAPS 腳距到期天數。前置檢查 (b) 要求 Long DTE ≥ Short DTE + 180 天，否則黃金法則不成立。', side: 'bottom' },
    pmcc_long_delta: { title: '⚡ Long Δ',                 desc: 'LEAPS 腳 Delta。✅ 標記門檻 ≥0.80（僅標記不淘汰），越高越接近持股替代。', side: 'bottom' },
    pmcc_ks:         { title: '🔴 KS（Short Call 履約價）', desc: 'Short Call 的履約價，黃金法則公式裡的 KS。前置檢查 (a) 要求 KS > KL，否則直接判定失敗。', side: 'bottom' },
    pmcc_ps:         { title: '💰 PS（Short Call Mid）',    desc: 'Short Call 的權利金（Mid 基準），黃金法則公式裡的 PS，賣出後收到的收租金額。', side: 'bottom' },
    pmcc_short_delta:{ title: '⚡ Short Δ',                desc: 'Short Call 腳 Delta。粗篩 0.15–0.40 才會列入組合；✅ 建議標記門檻 0.20–0.35（兩者是不同規則，見 §2.3）。', side: 'bottom' },
    pmcc_spread:     { title: '↔️ Spread',                desc: 'KS−KL，兩腳履約價的價差，代表這組 PMCC 理論上最多能賺多少（不含收租）。', side: 'bottom' },
    pmcc_net_debit:  { title: '🧾 NetDebit',              desc: 'PL−PS，實際投入的淨成本（買 LEAPS 付的錢減去賣 Short Call 收的租）。', side: 'bottom' },
    pmcc_max_profit: { title: '🏆 MaxProfit(含SC)',        desc: 'Spread−NetDebit，★這組合真正的最大獲利（已扣掉/加上收租），本表主排序鍵。展開列可見未收租版本 MaxProfit(未收租) 供對照。', side: 'bottom' },
    pmcc_yield_ann:  { title: '📈 年化收租率',              desc: '(PS/NetDebit)÷Short DTE×365，把不同天期的收租率換算成同一個年化基準才能公平比較（6 天跟 45 天的原始收租率相近時，年化後差異會很大）。', side: 'bottom' },
    pmcc_passes:     { title: '⚖️ Golden Rule',           desc: '黃金法則判定：✅通過（PL < Spread）或 ❌ 未通過並附數值化原因（例如 KS≤KL 或 DTE 差距不足 180 天）。未通過的列會標紅底。', side: 'bottom' }
  };
  var TOUR_ORDER = ['expiration','dte','strike','delta','oi','volume','liquidity','bid','ask','mid','spread',
                    'intrinsic','extrinsic','extrinsic_pct','time_value_pct','iv','vega','itm_prob',
                    'f_type','f_strike','f_expiration','f_dte','f_delta','f_code','f_size','f_side','f_premium','f_direction'];

  /* hover tooltip 引擎（document 委派 + 單一 fixed 元素，掛 body、export root 之外） */
  var tip = document.createElement('div');
  tip.id = 'leaps-col-tip';
  tip.innerHTML = '<div class="tip-t"></div><div class="tip-b"></div>';
  document.body.appendChild(tip);
  var tT = tip.querySelector('.tip-t'), tB = tip.querySelector('.tip-b');
  function posTip(e) {
    var x = e.clientX + 14, y = e.clientY + 12,
        w = tip.offsetWidth || 280, h = tip.offsetHeight || 100;
    if (x + w > window.innerWidth - 10)  x = e.clientX - w - 10;
    if (y + h > window.innerHeight - 10) y = e.clientY - h - 10;
    tip.style.left = x + 'px'; tip.style.top = y + 'px';
  }
  document.addEventListener('mouseover', function (e) {
    var el = e.target.closest('[data-tip-key]');
    if (el) {
      var d = LEAPS_COL_EXPLAIN[el.dataset.tipKey];
      if (!d) return;
      tT.textContent = d.title; tB.textContent = d.desc;
      tip.style.opacity = '1'; posTip(e);
    } else { tip.style.opacity = '0'; }
  });
  document.addEventListener('mousemove', function (e) {
    if (tip.style.opacity !== '0') posTip(e);
  });
  document.addEventListener('mouseout', function (e) {
    if (!e.target.closest('[data-tip-key]')) tip.style.opacity = '0';
  });

  /* 術語字卡：speechSynthesis 不支援時隱藏全部 🔊（降級，不報錯） */
  if (!('speechSynthesis' in window)) {
    document.querySelectorAll('.leaps-vocab-card .speak-btn').forEach(function (b) { b.style.display = 'none'; });
  }

  /* 點擊 → 單步聚光 popover；導覽按鈕 → 28 步 tour（同一份文案 map）；
     字卡 → 翻面；🔊 → 朗讀不翻面（第 8 課 inline onclick 改為委派） */
  function drv() { return window.driver && window.driver.js && window.driver.js.driver; }
  document.addEventListener('click', function (e) {
    var spk = e.target.closest('.leaps-vocab-card .speak-btn');
    if (spk) {
      e.stopPropagation();
      if (!('speechSynthesis' in window)) return;
      if (speechSynthesis.speaking) speechSynthesis.cancel();
      var utt = new SpeechSynthesisUtterance(spk.dataset.term);
      utt.lang = 'en-US'; utt.rate = 0.85; utt.pitch = 1.0;
      spk.classList.add('speaking');
      utt.onend = function () { spk.classList.remove('speaking'); };
      utt.onerror = function () { spk.classList.remove('speaking'); };
      speechSynthesis.speak(utt);
      return;
    }
    var vcard = e.target.closest('.leaps-vocab-card');
    if (vcard) { vcard.classList.toggle('flipped'); return; }
    var el = e.target.closest('[data-tip-key]');
    if (el && drv()) {
      var d = LEAPS_COL_EXPLAIN[el.dataset.tipKey];
      if (!d) return;
      tip.style.opacity = '0';
      // 用被點到的元素本身當 popover 目標，不查 d.el——PMCC 表格欄位
      // 沒有唯一 id（同一個 key 會在三個到期日桶各出現一次），這樣寫法
      // 對 LEAPS（有唯一 id）跟 PMCC（無 id）都適用，不用分兩套邏輯。
      drv()({ animate: true, allowClose: true, overlayOpacity: 0.35,
              steps: [{ element: el, popover: { title: d.title, description: d.desc, side: d.side, align: 'center' } }] }).drive();
      return;
    }
    var btn = e.target.closest('#leaps-tour-btn');
    if (btn && !btn.disabled && drv()) {
      var steps = TOUR_ORDER
        .filter(function (k) { return document.querySelector(LEAPS_COL_EXPLAIN[k].el); })
        .map(function (k) {
          var d = LEAPS_COL_EXPLAIN[k];
          return { element: d.el, popover: { title: d.title, description: d.desc, side: d.side, align: 'center' } };
        });
      if (steps.length) {
        drv()({ animate: true, allowClose: true, overlayOpacity: 0.4, showProgress: true, steps: steps }).drive();
      }
    }
  });
})();
