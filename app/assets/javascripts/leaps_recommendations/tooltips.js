(function () {
  /* 欄位說明的排版助手：定義句之後接一個小標題＋條列，讓多段說明不會擠成一團。
     hover tooltip 與 driver.js popover 都以 innerHTML 呈現，兩邊共用同一份字串。
     內容全是本檔案寫死的靜態文案，不含任何使用者輸入。 */
  function TIP_H(t) {
    return '<div class="tip-h">' + t + "</div>";
  }
  function TIP_L(items) {
    return '<ul class="tip-l"><li>' + items.join("</li><li>") + "</li></ul>";
  }

  /* 這一項在畫面上的實際數值（例如「FVG 138.22–144.49」）。
     原本掛在元素的 title 屬性上，但瀏覽器的原生提示會跟自訂 tooltip 疊在一起
     互相遮擋，很難看（使用者實測截圖）。改成顯示在解釋文字最上面那一列。
     文字是伺服器端組好的標籤、不含使用者輸入，但這裡走 innerHTML，仍逐字轉義。 */
  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      }[c];
    });
  }
  /* tone（data-tip-tone）讓數值列上色：賺錢綠／損益兩平黃／賠錢紅。只接受白名單，
     其他值一律忽略——它會被拼進 class，不能讓任意字串進 HTML。 */
  var TIP_TONES = { profit: true, breakeven: true, loss: true };
  function TIP_V(value, tone) {
    var cls = TIP_TONES[tone] ? "tip-v tip-v--" + tone : "tip-v";
    return value ? '<div class="' + cls + '">' + esc(value) + "</div>" : "";
  }
  /* data-tip-lines：伺服器依當下數據組好的說明句（JSON 字串陣列），逐字轉義後條列。
     LEAPS 垂直價差用它讓 tooltip 的計算過程跟著畫面上實際的兩腳走，不寫死範例。 */
  function linesFor(el) {
    var raw = el && el.dataset ? el.dataset.tipLines : null;
    if (!raw) return "";
    var parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return "";
    }
    if (!Array.isArray(parsed)) return "";
    var items = parsed
      .filter(function (s) {
        return typeof s === "string";
      })
      .map(esc);
    return items.length ? TIP_H("以目前組合計算") + TIP_L(items) : "";
  }
  /* 解釋文字 + 該項實際數值；有 data-tip-value 就把數值放最前面，有 data-tip-lines 就接在後面。 */
  function descFor(d, el) {
    var ds = el && el.dataset ? el.dataset : {};
    return TIP_V(ds.tipValue, ds.tipTone) + d.desc + linesFor(el);
  }

  var LEAPS_COL_EXPLAIN = {
    expiration: {
      el: "#leaps-th-expiration",
      title: "📅 Expiration",
      desc: "合約到期日。LEAPS 慣例為一年以上，本表只列 364 天以上。",
      side: "bottom",
    },
    dte: {
      el: "#leaps-th-dte",
      title: "⏱ Days to Expiration",
      desc: "距到期天數。364–550 近天期、550+ 遠天期；越長時間緩衝越大，Vega 曝險也越高。",
      side: "bottom",
    },
    strike: {
      el: "#leaps-th-strike",
      title: "🎯 Strike",
      desc: "約定買入股價。深價內的 Call 行為越接近持有正股。",
      side: "bottom",
    },
    delta: {
      el: "#leaps-th-delta",
      title: "⚡ Delta",
      desc: "股價每動 $1 權利金的理論變化。本表篩 Delta ≥ 0.60；越接近 1 越像股票替代品，槓桿越低但越穩。",
      side: "bottom",
    },
    oi: {
      el: "#leaps-th-oi",
      title: "🔓 Open Interest",
      desc: "未平倉合約數，本表排序主鍵。OI 高流動性通常較好；只在盤後更新。",
      side: "bottom",
    },
    volume: {
      el: "#leaps-th-volume",
      title: "📊 Volume",
      desc: "當日成交量（即時）。OI 高但 Volume 長期為零，進出仍可能困難。",
      side: "bottom",
    },
    liquidity: {
      el: "#leaps-th-liquidity",
      title: "🚦 流動性判斷",
      desc: "依本次查詢候選的 OI 三分位相對排名（充足/普通/偏低），非固定門檻；「⚠ 近期無成交」由 Vol/OI 比率判斷。",
      side: "bottom",
    },
    bid: {
      el: "#leaps-th-bid",
      title: "⬇️ Bid",
      desc: "市場最高買價（賣出時的底價參考）。",
      side: "bottom",
    },
    ask: {
      el: "#leaps-th-ask",
      title: "⬆️ Ask",
      desc: "市場最低賣價（買入時的天花板參考）。",
      side: "bottom",
    },
    mid: {
      el: "#leaps-th-mid",
      title: "⚖️ Mid",
      desc: "(Bid+Ask)/2，掛限價單參考價。本系統衍生欄位一律以 Mid 為權利金基準，不用可能過時的最後成交價。",
      side: "bottom",
    },
    spread: {
      el: "#leaps-th-spread",
      title: "↔️ Spread%（買賣差價比）",
      desc:
        "(Ask−Bid)/Mid。你一次進出（買進＋賣出）要付出的滑價成本，%數越低代表流動性越好、成交價越接近理論中間價。" +
        TIP_H("經驗法則") +
        TIP_L([
          "&lt; 5%：流動性佳，正常交易沒問題",
          "5%–10%：普通，大單要注意分批進出",
          "&gt; 10%：要注意 — 深度價內（Deep ITM）的 LEAPS 常見這個問題，因為外在價值本身就小，Bid−Ask 的絕對價差在 Mid 中占比會被放大",
        ]),
      side: "bottom",
    },
    intrinsic: {
      el: "#leaps-th-intrinsic",
      title: "💎 Intrinsic Value",
      desc:
        "max(0, 現價−履約價)，權利金裡「已在錢裡」的部分，股價不動也不流失。" +
        TIP_H("為什麼越高越好") +
        TIP_L([
          "LEAPS Call 買方本質上是用選擇權替代股票（stock replacement），賺的就是股價上漲的內在價值",
          "內在價值越高＝價內（ITM）越深，Delta 越接近 1，越貼近正股走勢，槓桿效果穩定",
          "這部分價值不隨時間流逝而減損；只有外在價值（extrinsic value）才會隨到期日接近而衰減",
        ]),
      side: "bottom",
    },
    extrinsic: {
      el: "#leaps-th-extrinsic",
      title: "🎈 Extrinsic Value",
      desc:
        "Mid−內在價值，時間＋波動率溢價（保險費），隨時間與 IV 回落流失。" +
        TIP_H("買進當下：越低越好") +
        TIP_L([
          "付出去的溢價少，時間損耗（theta）風險也小",
          "同樣的資金能買到更多內在價值，部位更接近正股",
        ]),
      side: "bottom",
    },
    extrinsic_pct: {
      el: "#leaps-th-extrinsic_pct",
      title: "🧮 外在佔比",
      desc: "外在÷Mid，「權利金裡幾 % 是保險費」。深 ITM LEAPS 核心指標：越低越接近持股替代，高 IV 環境尤其要壓低。",
      side: "bottom",
    },
    time_value_pct: {
      el: "#leaps-th-time_value_pct",
      title: "📐 Time Value%",
      desc: "外在÷股價，「相對直接持股多付幾 % 溢價」。與外在佔比分母不同，回答不同問題。",
      side: "bottom",
    },
    iv: {
      el: "#leaps-th-iv",
      title: "🌊 Implied Volatility",
      desc:
        "該檔位隱含波動率。IV 越高權利金越貴；高 IV 買 LEAPS 要留意回落侵蝕（搭配 Vega）。" +
        TIP_H("IV Rank / IV Percentile") +
        TIP_L([
          "≤ 30%：理想進場點，權利金相對便宜，之後 IV 若回升對你的部位有利",
          "30%–50%：可接受，但非最佳時機",
          "&gt; 50%：不建議買進，權利金偏貴；長天期部位要持有數月甚至一兩年，IV 均值回歸會侵蝕獲利（vega 逆風）",
        ]),
      side: "bottom",
    },
    vega: {
      el: "#leaps-th-vega",
      title: "🌀 Vega",
      desc: "IV 每變 1% 權利金的理論變化。DTE 越長 Vega 越大；IV Crush 風險量化：IV 回落 10% ≈ 損失 Vega×10。",
      side: "bottom",
    },
    itm_prob: {
      el: "#leaps-th-itm_prob",
      title: "🎲 ITM Probability",
      desc: "Barchart 估到期價內機率。買方視角＝到期仍有內在價值的機率，與 Delta 相關但獨立模型計算。",
      side: "bottom",
    },
    f_type: {
      el: "#leaps-th-f_type",
      title: "🏷 Type",
      desc: "Call（買權）或 Put（賣權）。搭配 Side 與方向欄一起判讀該筆大單的多空含義。",
      side: "bottom",
    },
    f_strike: {
      el: "#leaps-th-f_strike",
      title: "🎯 Strike",
      desc: "該筆成交合約的履約價。",
      side: "bottom",
    },
    f_expiration: {
      el: "#leaps-th-f_expiration",
      title: "📅 Expiration",
      desc: "該筆成交合約的到期日。本面板不限 LEAPS，任何到期日都會入榜。",
      side: "bottom",
    },
    f_dte: {
      el: "#leaps-th-f_dte",
      title: "⏱ DTE",
      desc: "距到期天數。與排行表的 364 天門檻無關，這裡看的是當天市場在哪些天期活動。",
      side: "bottom",
    },
    f_delta: {
      el: "#leaps-th-f_delta",
      title: "⚡ Delta",
      desc: "正值=Call、負值=Put；絕對值越大越深價內。",
      side: "bottom",
    },
    f_code: {
      el: "#leaps-th-f_code",
      title: "🏳 Code",
      desc: "交易所成交代碼。標準單腿代碼可信；AUTO／多腿類（SLAN、MLET、ISOI 等）標記普遍缺失，判讀需保守。",
      side: "bottom",
    },
    f_size: {
      el: "#leaps-th-f_size",
      title: "📦 Size",
      desc: "該筆成交口數（1 口 = 100 股）。",
      side: "bottom",
    },
    f_side: {
      el: "#leaps-th-f_side",
      title: "↕️ Side",
      desc: "成交價位置：靠 bid=賣方主動（偏空）、靠 ask=買方主動（偏多）、mid=中性。",
      side: "bottom",
    },
    f_premium: {
      el: "#leaps-th-f_premium",
      title: "💰 Premium",
      desc: "該筆成交的權利金總額。本面板依 Premium 降序取前 20 筆。",
      side: "bottom",
    },
    f_direction: {
      el: "#leaps-th-f_direction",
      title: "🧭 方向",
      desc: "綜合 Type／Side／Code 的看多/看空/中性判讀。情緒參考，不參與排行排序。",
      side: "bottom",
    },
    /* PMCC v3 §9.1 表格欄位教學。這批沒有 el（表格每個到期日桶各渲染一次，
       同一個 key 的 th 出現三次，沒有唯一 id 可對應）——點擊時改用被點到的
       元素本身當 popover 目標（見下方 click handler），不查表；因此也不放進
       TOUR_ORDER（28 步全覽需要每個 key 對應唯一一個元素）。 */
    pmcc_kl: {
      title: "🔵 KL（LEAPS 履約價）",
      desc: "Long Call 的履約價，黃金法則公式裡的 KL。深 ITM 越接近持股替代。",
      side: "bottom",
    },
    pmcc_pl: {
      title: "💵 PL（LEAPS Mid）",
      desc: "Long Call 的權利金（Mid 基準），黃金法則公式裡的 PL，也是實際買入成本／張。",
      side: "bottom",
    },
    pmcc_long_dte: {
      title: "⏱ Long DTE",
      desc: "LEAPS 腳距到期天數。前置檢查 (b) 要求 Long DTE ≥ Short DTE + 180 天，否則黃金法則不成立。",
      side: "bottom",
    },
    pmcc_long_delta: {
      title: "⚡ Long Δ",
      desc: "LEAPS 腳 Delta。✅ 標記門檻 ≥0.80（僅標記不淘汰），越高越接近持股替代。",
      side: "bottom",
    },
    pmcc_ks: {
      title: "🔴 KS（Short Call 履約價）",
      desc: "Short Call 的履約價，黃金法則公式裡的 KS。前置檢查 (a) 要求 KS > KL，否則直接判定失敗。",
      side: "bottom",
    },
    pmcc_ps: {
      title: "💰 PS（Short Call Mid）",
      desc: "Short Call 的權利金（Mid 基準），黃金法則公式裡的 PS，賣出後收到的收租金額。",
      side: "bottom",
    },
    pmcc_short_delta: {
      title: "⚡ Short Δ",
      desc: "Short Call 腳 Delta。粗篩 0.15–0.40 才會列入組合；✅ 建議標記門檻 0.20–0.35（兩者是不同規則，見 §2.3）。",
      side: "bottom",
    },
    pmcc_spread: {
      title: "↔️ Spread",
      desc: "KS−KL，兩腳履約價的價差，代表這組 PMCC 理論上最多能賺多少（不含收租）。",
      side: "bottom",
    },
    pmcc_net_debit: {
      title: "🧾 NetDebit",
      desc: "PL−PS，實際投入的淨成本（買 LEAPS 付的錢減去賣 Short Call 收的租）。",
      side: "bottom",
    },
    pmcc_max_profit: {
      title: "🏆 MaxProfit(含SC)",
      desc: "Spread−NetDebit，★這組合真正的最大獲利（已扣掉/加上收租），本表主排序鍵。展開列可見未收租版本 MaxProfit(未收租) 供對照。",
      side: "bottom",
    },
    pmcc_yield_ann: {
      title: "📈 年化收租率",
      desc: "(PS/NetDebit)÷Short DTE×365，把不同天期的收租率換算成同一個年化基準才能公平比較（6 天跟 45 天的原始收租率相近時，年化後差異會很大）。",
      side: "bottom",
    },
    pmcc_passes: {
      title: "⚖️ Golden Rule",
      desc: "黃金法則判定：✅通過（PL < Spread）或 ❌ 未通過並附數值化原因（例如 KS≤KL 或 DTE 差距不足 180 天）。未通過的列會標紅底。",
      side: "bottom",
    },
  };
  /* ── 價格情境 widget（POI / 52 週區間 / 當日區間）的名詞解釋 ──────────────
     兩種用法共用同一份文案：
       有 el 的 → 進 TOUR_ORDER，「欄位導覽」會逐步聚光說明
       沒有 el 的 → 掛在 POI 標籤與圖例的 data-tip-key 上，滑過看、點擊聚光
     縮寫印在圖上但沒人解釋等於沒說（使用者實測回報「沒有解釋 FVG、LVN、POC、POI」）。 */
  var POI_EXPLAIN = {
    poi_overview: {
      el: "#leaps-poi-card",
      title: "🗺 POI（Point of Interest）",
      desc:
        "「市場會盯的關鍵價區」清單。" +
        TIP_H("POI ≠ POC") +
        TIP_L([
          "POC 只是 POI 的<b>其中一項</b>——它是成交量最大的那一個價位",
          "POI 是一整類：量價節點、結構型價區、選擇權大 OI 履約價、重要均線都算",
          "所以同一張圖上會同時看到 POC、HVN、FVG、履約價這些不同來源的標記",
        ]) +
        TIP_H("這張卡的四類來源") +
        TIP_L([
          "<b>量價節點</b>：POC / HVN / LVN（Barchart VOLAP 算的，本系統不重算）",
          "<b>結構型</b>：FVG / 缺口 / Order Block / 供需區（由日線 K 棒推導）",
          "<b>選擇權</b>：未平倉量最大的幾個履約價，加上你這次查詢輸入的那個",
          "<b>均線</b>：MA20 / 50 / 100 / 200",
        ]),
      side: "right",
    },
    poi_poc: {
      title: "🎯 POC（Point of Control）",
      desc:
        "Volume Profile 裡成交量<b>最大的那一個價位</b>，代表這段期間市場最認同的價格。" +
        TIP_H("怎麼看") +
        TIP_L([
          "價格往往會被 POC 吸引回去（均值回歸的錨點）",
          "站上或跌破 POC 常伴隨趨勢轉折，是多空的心理分水嶺",
          "對 LEAPS 來說：履約價選在 POC 之下，等於買在「大多數人的成本」以下",
        ]),
    },
    poi_hvn: {
      title: "📊 HVN（High Volume Node，高量節點）",
      desc:
        "成交量明顯偏高的價格帶——這裡曾經有大量籌碼換手。" +
        TIP_H("怎麼看") +
        TIP_L([
          "籌碼堆積 → 價格走到這裡容易<b>盤整、放慢</b>",
          "在現價下方＝潛在支撐；在現價上方＝潛在壓力",
          "本系統的門檻是「總量 ≥ POC 的 55%」，相鄰的會合併成一段價區",
        ]),
    },
    poi_lvn: {
      title: "💨 LVN（Low Volume Node，低量節點）",
      desc:
        "成交量明顯偏低的價格帶——這個價位幾乎沒人想成交。" +
        TIP_H("怎麼看") +
        TIP_L([
          "沒有籌碼卡住 → 價格容易<b>快速穿越</b>，常出現急拉或急殺",
          "HVN 是「牆」，LVN 是「走廊」",
          "只在 Value Area 之內才標記：價格區間的頭尾本來就沒什麼量，那是「很少走到」不是「走到了沒人接」",
        ]),
    },
    poi_value_area: {
      title: "🟩 Value Area 70%",
      desc:
        "從 POC 往兩側擴張，直到涵蓋整段期間 <b>70% 成交量</b>的價格區間（Barchart 標的）。" +
        TIP_H("怎麼看") +
        TIP_L([
          "這是市場認定的「合理價格範圍」，淡綠底的列就是",
          "價格在區間內＝平衡；跑到區間外＝失衡，之後常見的是回到區間內",
          "上下緣常被當成短線的支撐與壓力",
        ]),
    },
    poi_fvg: {
      title: "🕳 FVG（Fair Value Gap，公允價值缺口）",
      desc:
        "連續三根 K 棒中，<b>第一根與第三根的影線沒有重疊</b>，中間那段價格沒有被成交填滿。" +
        TIP_H("怎麼看") +
        TIP_L([
          "代表那一段價格「走得太快」，買賣雙方沒有充分換手",
          "價格常會回頭把這段缺口補掉（回測），補完才繼續原方向",
          "已經被回補一半以上的不會列出來——那種已經失效了",
        ]),
    },
    poi_gap: {
      title: "⚡ 缺口（Gap）",
      desc:
        "開盤價相對前一根收盤<b>跳空</b>，中間那段價格當天完全沒有成交。" +
        TIP_H("跟 FVG 的差別") +
        TIP_L([
          "FVG 看的是三根 K 棒影線的結構；缺口只看「昨收 → 今開」這一段",
          "常見成因：盤後財報、重大新聞",
          "同樣只列出尚未被回補一半以上的",
        ]) +
        TIP_H("門檻") +
        TIP_L([
          "寬度要達到 0.5 個 ATR 才算——不設下限的話幾乎每天都有缺口，沒有鑑別度",
        ]),
    },
    poi_order_block: {
      title: "🧱 Order Block",
      desc:
        "在一根「位移根」（實體 ≥ 1 個 ATR 的大幅推動）之前的<b>最後一根反向 K 棒</b>的實體。" +
        TIP_H("怎麼看") +
        TIP_L([
          "推測為機構在推動行情之前佈單的價格帶",
          "多頭位移前的最後一根黑 K＝需求方掛單區；空頭位移前的最後一根紅 K＝供給方掛單區",
          "價格回到這裡時常出現反應",
        ]),
    },
    poi_demand: {
      title: "🟢 需求區（Demand Zone）",
      desc:
        "急漲起點<b>之前</b>那段窄幅盤整的價格區間——籌碼在這裡換手之後才往上走。" +
        TIP_H("判定規則") +
        TIP_L([
          "連續 ≥ 3 根 K 棒，整段高低全距 ≤ 1.5 個 ATR，且緊接著出現位移根",
        ]),
    },
    poi_supply: {
      title: "🔴 供給區（Supply Zone）",
      desc:
        "急跌起點<b>之前</b>那段窄幅盤整的價格區間——賣壓在這裡累積之後才往下走。" +
        TIP_H("判定規則") +
        TIP_L(["與需求區同一套規則，只是後面接的是向下的位移根"]),
    },
    poi_strike: {
      title: "🎫 大 OI 履約價",
      desc:
        "未平倉量（Open Interest）最大的幾個 Call 履約價，<b>跨到期日加總</b>。" +
        TIP_H("為什麼算 POI") +
        TIP_L([
          "大量選擇權部位集中的價位，到期前常對股價形成磁吸或阻力（pinning）",
          "跨到期日相加才對——同一個履約價分散在多個到期日，只看單一列會低估",
          "你這次查詢輸入的履約價一定會列出來，即使它的 OI 排不進前幾名",
        ]),
    },
    poi_ma: {
      title: "📈 重要均線",
      desc:
        "MA20 / MA50 / MA100 / MA200。交易者普遍盯著同一組均線，所以它們本身就會變成支撐壓力。" +
        TIP_H("資料來源") +
        TIP_L([
          "讀 technical_analyses 表的既有欄位，不重算；該代號沒抓過技術分析時就不會出現",
        ]),
    },
    poi_updown: {
      title: "🟢🔴 Up / Down 成交量",
      desc:
        "每一條長條分成兩段：綠色是<b>上漲 K 棒</b>貢獻的量，紅色是<b>下跌 K 棒</b>貢獻的量。" +
        TIP_H("注意：這不是支撐/壓力") +
        TIP_L([
          "顏色代表的是「那個價位上買賣方誰比較積極」，不是它在現價的哪一邊",
          "這是 Barchart VOLAP 的 Up/Down 模式，與你圖表上的設定一致",
          "整條的長度才代表該價位的總成交量占比（相對 POC）",
        ]),
    },
    poi_now: {
      el: "#leaps-poi-now",
      title: "🟣 現價列",
      desc:
        "紫色膠囊與橫線標出現價落在哪一箱。" +
        TIP_H("怎麼用") +
        TIP_L([
          "看現價上方有幾道 HVN／供給區＝往上要穿過幾道牆",
          "看現價下方最近的 HVN／需求區＝跌下來大概在哪裡有接手",
          "現價來自 LEAPS 快照的標的價，與排行表顯示的是同一個數字",
        ]),
      side: "bottom",
    },
    poi_legend_tour: {
      el: "#leaps-poi-legend",
      title: "🔍 想知道某個名詞的意思",
      desc:
        "圖上每一個標籤（POC、HVN、LVN、FVG、缺口、Order Block、履約價…）都可以互動。" +
        TIP_H("兩種用法") +
        TIP_L([
          "<b>滑過</b>標籤 → 跳出解釋小卡",
          "<b>點一下</b>標籤 → 聚光標示該項並顯示完整說明",
          "圖例上的「❓ 什麼是 POI」可以看整張卡的概念",
        ]),
      side: "top",
    },
    week52_card: {
      el: "#leaps-week52-card",
      title: "📏 52 週區間",
      desc:
        "近 52 週的最高與最低，以及現價落在區間裡的相對位置。" +
        TIP_H("怎麼看") +
        TIP_L([
          "百分比越低＝越靠近年度低點，對買 LEAPS Call 的人相對有利",
          "這裡的高低點直接取自日線 1 年的 Volume Profile 價格範圍，與左邊那張圖同一份資料，數字不會打架",
        ]),
      side: "bottom",
    },
    day_card: {
      el: "#leaps-day-card",
      title: "📐 當日區間",
      desc:
        "最新一個交易日的高低點、開盤、前收與振幅。" +
        TIP_H("副標會寫出實際日期") +
        TIP_L([
          "盤中最新一根日線可能還是前一天的，所以副標直接標日期而不是寫「今日」",
          "現價若落在這個區間之外，會顯示提醒並<b>不畫游標</b>——那代表現價與這根 K 棒不是同一個時間點，硬畫一個位置只會誤導",
        ]),
      side: "bottom",
    },
  };

  Object.keys(POI_EXPLAIN).forEach(function (k) {
    LEAPS_COL_EXPLAIN[k] = POI_EXPLAIN[k];
  });

  /* ── LEAPS 垂直價差區塊的 8 格（leaps-call-spread-spec P6）────────────────
     這裡只放「定義」，不放任何範例數字：實際的數值與計算過程由伺服器依當下
     選到的兩腳組好，放在元素的 data-tip-value／data-tip-lines（見 linesFor）。
     沒有 el，不進 TOUR_ORDER；滑過看、點擊聚光。 */
  var VERTICAL_SPREAD_EXPLAIN = {
    vs_long_leg: {
      title: "📈 買入腳",
      desc: "你付錢買進的 LEAPS Call，履約價固定是你輸入的價格；可以切換到期日。",
      side: "bottom",
    },
    vs_short_leg: {
      title: "📉 賣出腳",
      desc: "你同時賣出的 Call：同一個到期日、履約價較高且必須價外。收到的權利金抵掉買入腳的成本，代價是股價漲過這個履約價之後的獲利不屬於你。",
      side: "bottom",
    },
    vs_net_cost: {
      title: "💵 實付淨成本",
      desc: "開這個價差每口實際要付的錢 = (買入腳權利金 − 賣出腳權利金) × 100（一口 100 股）。",
      side: "top",
    },
    vs_max_profit: {
      title: "🟢 最大獲利",
      desc: "到期時股價在賣出腳履約價以上，拿到最大獲利 = (價差寬度 − 淨成本) × 100。",
      side: "top",
    },
    vs_breakeven: {
      title: "🟡 損益兩平",
      desc: "到期時股價要高於「買入腳履約價 + 每股淨成本」才開始賺錢。",
      side: "top",
    },
    vs_max_loss: {
      title: "🔴 最大虧損",
      desc: "到期時股價在買入腳履約價以下，兩腳都沒有價值，付出的淨成本全部虧掉；這就是最多虧的金額。",
      side: "top",
    },
    vs_risk_reward: {
      title: "⚖️ 風險報酬比",
      desc: "最多賺的錢是最多虧的錢的幾倍。只比較兩個極端，沒有考慮發生的機率。",
      side: "top",
    },
    vs_width: {
      title: "📏 價差寬度",
      desc: "兩個履約價的差距，是這個價差每股最多值多少錢。",
      side: "top",
    },
  };
  Object.keys(VERTICAL_SPREAD_EXPLAIN).forEach(function (k) {
    LEAPS_COL_EXPLAIN[k] = VERTICAL_SPREAD_EXPLAIN[k];
  });

  /* 價格情境 widget 在頁面上位於排行表之上，導覽順序跟著閱讀順序走，放最前面。
     沒有 el 的純名詞（poi_poc、poi_fvg…）不進 TOUR_ORDER——它們沒有唯一的
     聚光目標（同一個 key 可能出現在好幾列），改由滑過／點擊標籤觸發。
     tour 本身會過濾掉 DOM 裡不存在的錨點，所以 widget 還在輪詢時不會出錯。 */
  var TOUR_ORDER = [
    "poi_overview",
    "poi_now",
    "poi_legend_tour",
    "week52_card",
    "day_card",
    "expiration",
    "dte",
    "strike",
    "delta",
    "oi",
    "volume",
    "liquidity",
    "bid",
    "ask",
    "mid",
    "spread",
    "intrinsic",
    "extrinsic",
    "extrinsic_pct",
    "time_value_pct",
    "iv",
    "vega",
    "itm_prob",
    "f_type",
    "f_strike",
    "f_expiration",
    "f_dte",
    "f_delta",
    "f_code",
    "f_size",
    "f_side",
    "f_premium",
    "f_direction",
  ];

  /* hover tooltip 引擎（document 委派 + 單一 fixed 元素，掛 body、export root 之外） */
  var tip = document.createElement("div");
  tip.id = "leaps-col-tip";
  tip.innerHTML = '<div class="tip-t"></div><div class="tip-b"></div>';
  document.body.appendChild(tip);
  var tT = tip.querySelector(".tip-t"),
    tB = tip.querySelector(".tip-b");
  function posTip(e) {
    var x = e.clientX + 14,
      y = e.clientY + 12,
      w = tip.offsetWidth || 280,
      h = tip.offsetHeight || 100;
    if (x + w > window.innerWidth - 10) x = e.clientX - w - 10;
    if (y + h > window.innerHeight - 10) y = e.clientY - h - 10;
    tip.style.left = x + "px";
    tip.style.top = y + "px";
  }
  document.addEventListener("mouseover", function (e) {
    var el = e.target.closest("[data-tip-key]");
    if (el) {
      var d = LEAPS_COL_EXPLAIN[el.dataset.tipKey];
      if (!d) return;
      tT.textContent = d.title;
      tB.innerHTML = descFor(d, el);
      tip.style.opacity = "1";
      posTip(e);
    } else {
      tip.style.opacity = "0";
    }
  });
  document.addEventListener("mousemove", function (e) {
    if (tip.style.opacity !== "0") posTip(e);
  });
  document.addEventListener("mouseout", function (e) {
    if (!e.target.closest("[data-tip-key]")) tip.style.opacity = "0";
  });

  /* 術語字卡：speechSynthesis 不支援時隱藏全部 🔊（降級，不報錯） */
  if (!("speechSynthesis" in window)) {
    document
      .querySelectorAll(".leaps-vocab-card .speak-btn")
      .forEach(function (b) {
        b.style.display = "none";
      });
  }

  /* 點擊 → 單步聚光 popover；導覽按鈕 → 28 步 tour（同一份文案 map）；
     字卡 → 翻面；🔊 → 朗讀不翻面（第 8 課 inline onclick 改為委派） */
  function drv() {
    return window.driver && window.driver.js && window.driver.js.driver;
  }
  document.addEventListener("click", function (e) {
    var spk = e.target.closest(".leaps-vocab-card .speak-btn");
    if (spk) {
      e.stopPropagation();
      if (!("speechSynthesis" in window)) return;
      if (speechSynthesis.speaking) speechSynthesis.cancel();
      var utt = new SpeechSynthesisUtterance(spk.dataset.term);
      utt.lang = "en-US";
      utt.rate = 0.85;
      utt.pitch = 1.0;
      spk.classList.add("speaking");
      utt.onend = function () {
        spk.classList.remove("speaking");
      };
      utt.onerror = function () {
        spk.classList.remove("speaking");
      };
      speechSynthesis.speak(utt);
      return;
    }
    var vcard = e.target.closest(".leaps-vocab-card");
    if (vcard) {
      vcard.classList.toggle("flipped");
      return;
    }
    var el = e.target.closest("[data-tip-key]");
    if (el && drv()) {
      var d = LEAPS_COL_EXPLAIN[el.dataset.tipKey];
      if (!d) return;
      tip.style.opacity = "0";
      // 用被點到的元素本身當 popover 目標，不查 d.el——PMCC 表格欄位
      // 沒有唯一 id（同一個 key 會在三個到期日桶各出現一次），這樣寫法
      // 對 LEAPS（有唯一 id）跟 PMCC（無 id）都適用，不用分兩套邏輯。
      drv()({
        animate: true,
        allowClose: true,
        overlayOpacity: 0.35,
        steps: [
          {
            element: el,
            popover: {
              title: d.title,
              description: descFor(d, el),
              side: d.side,
              align: "center",
            },
          },
        ],
      }).drive();
      return;
    }
    var btn = e.target.closest("#leaps-tour-btn");
    if (btn && !btn.disabled && drv()) {
      var steps = TOUR_ORDER.filter(function (k) {
        return document.querySelector(LEAPS_COL_EXPLAIN[k].el);
      }).map(function (k) {
        var d = LEAPS_COL_EXPLAIN[k];
        return {
          element: d.el,
          // 導覽這幾步是卡片層級的概念，通常沒有 data-tip-value；
          // 走同一個 descFor 只是為了兩條路徑的行為一致，有值就會顯示。
          popover: {
            title: d.title,
            description: descFor(d, document.querySelector(d.el)),
            side: d.side,
            align: "center",
          },
        };
      });
      if (steps.length) {
        drv()({
          animate: true,
          allowClose: true,
          overlayOpacity: 0.4,
          showProgress: true,
          steps: steps,
        }).drive();
      }
    }
  });
})();
