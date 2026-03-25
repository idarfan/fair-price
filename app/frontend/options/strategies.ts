import type { MarketOutlook, IvEnv, StrategyTemplate } from './types'

type StrategyMap = {
  [K in MarketOutlook]: Partial<Record<IvEnv | 'any', StrategyTemplate[]>>
}

export const STRATEGIES: StrategyMap = {
  bullish: {
    high_iv: [
      {
        key: 'cash_secured_put', name: 'Cash Secured Put（CSP）',
        desc: '賣 OTM Put 收 Premium，願意在 Strike 價接股。Wheel 前半段。',
        dte: '30–45 天', delta: '−0.20 ~ −0.35', credit: true,
        maxProfit: '收入 Premium', risk: 'Strike 全額（同持股）',
        defaultLegs: [{ type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.60, dte: 35 }],
        detail: {
          what: '賣出 OTM Put，不管股票有沒有跌到 Strike 都先收 Premium。若跌至 Strike → 依約以低價接股；沒跌 → Premium 全部入袋。Wheel 策略前半段，目的是用比現價更低的成本買到你想要的股票。',
          when: 'IV Rank 高（賣方有利）、你本來就想以更低價買入這檔股票、有足夠現金擔保（Strike × 100）。不適合用在你不想持有的股票上。',
          risks: '股票急跌遠低於 Strike（接到相對貴的股）、黑天鵝單邊暴跌 Premium 完全無法覆蓋損失、流動性差的股票 Bid-Ask Spread 吃掉大量獲利。',
          scenario: 'WULF 現價 $5.00，FairPrice 公允價值打八折約 $4.00 → 賣 35 天 $4.00 Put 收 $0.20。最大獲利 $20 / contract，若被 Assign 持倉成本 $3.80，已低於公允價值，繼續進入 Wheel。',
        },
      },
      {
        key: 'bull_put_spread', name: 'Bull Put Spread（牛市 Put 價差）',
        desc: '賣高 Strike Put + 買低 Strike Put，限定風險看漲收 Credit。',
        dte: '21–35 天', delta: '−0.25 ~ −0.35', credit: true,
        maxProfit: '淨 Credit', risk: '兩 Strike 差 − 淨 Credit',
        defaultLegs: [
          { type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.60, dte: 30 },
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.65, dte: 30 },
        ],
        detail: {
          what: '賣出較高 Strike 的 Put（收 Premium）＋買入較低 Strike 的 Put（付保護費），形成有上限、有下限的空間。股票收在賣出 Strike 上方 → 淨 Credit 全拿；跌進兩 Strike 之間 → 部分虧損；跌穿買入 Strike → 最大虧損。',
          when: '看漲但不想裸賣 Put 承擔無限風險，或資金有限需要降低保證金要求。比單純賣 Put 風險更小，適合 IV 高時收租。',
          risks: '股票大跌穿過整個 Spread 區間，損失固定但也相對大；兩腳 Bid-Ask 各吃一次成本較高；臨近到期前 Delta 加速變化管理較難。',
          scenario: 'WULF $5.00，賣 $4.50 Put / 買 $4.00 Put，淨 Credit ~$0.12。最大獲利 $12，最大虧損 $38（$50 寬度 − $12 Credit）。只要 WULF 收盤 ≥ $4.50 就全賺。',
        },
      },
      {
        key: 'covered_call', name: 'Covered Call（備兌買權）',
        desc: '已持有股票，賣 OTM Call 收月租，降低持倉成本。Wheel 後半段。',
        dte: '21–30 天', delta: '0.20 ~ 0.30', credit: true,
        maxProfit: 'Strike − 成本 + Premium（上漲封頂）', risk: '現價以下 Premium 緩衝',
        defaultLegs: [
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.55, dte: 25 },
        ],
        detail: {
          what: '已持有 100 股，同時賣出 OTM Call 收租。若股票漲過 Strike → 股票被 Call 走，賺到「Strike − 持倉成本 + Premium」；沒漲 → Premium 入袋降低成本。Wheel 策略後半段，持股 → 賣 Call → 可能被 Call 走 → 再賣 Put。',
          when: '持股後短期看法中性或微漲，想降低持倉成本或提升報酬。IV 偏高時租金更豐，適合長期持有者月月收租。股票剛從 CSP 接到時尤其適合立即轉入 Wheel。',
          risks: '股票大漲超過 Strike 只賺封頂，踏空上方漲幅；股票繼續下跌時 Premium 緩衝有限，跌超過 Premium 就開始虧損；若做 Deep ITM Call 有提前被 Assign 風險（除息前）。',
          scenario: 'WULF 以 CSP $3.80 接股，現價 $5.00 → 賣 30 天 $5.50 Call 收 $0.25。Break-even 成本降至 $3.55，若被 Call 走獲利 $1.95（51%）。每月收租逐步降低持倉成本。',
        },
      },
    ],
    low_iv: [
      {
        key: 'long_call', name: 'Long Call（買進買權）',
        desc: '直接買 Call，低 IV 時 Premium 便宜，看漲方向最直接。',
        dte: '45–60 天', delta: '0.30 ~ 0.50', credit: false,
        maxProfit: '無限（股票漲越多賺越多）', risk: '全部 Premium',
        defaultLegs: [{ type: 'long_call', strike: 0, premium: 0, quantity: 1, iv: 0.35, dte: 50 }],
        detail: {
          what: '直接買入 Call 期權，擁有以 Strike 價格購買 100 股股票的「權利」。股票漲過 Strike + Premium → 開始獲利；漲越多賺越多；沒漲超過 → 損失全部 Premium。',
          when: 'IV Rank 低（期權便宜）、強烈看漲、不想承擔持股的全部下行風險、有催化劑（財報、產品發布）。適合有明確方向判斷的交易者。',
          risks: 'Theta 衰減每天都在吃掉時間價值，越接近到期越快；IV 如果下降（即使股票漲了也可能虧損）；方向看對但幅度不夠也可能虧損。',
          scenario: 'WULF $5.00，買 50 天 $5.50 Call，Premium $0.30 = $30 / contract。股票需漲至 $5.80 才損益兩平。漲至 $7 獲利 $1.20（400%）；無任何動作到期 → 損失 $30。',
        },
      },
      {
        key: 'bull_call_spread', name: 'Bull Call Spread（牛市 Call 價差）',
        desc: '買低 Strike Call + 賣高 Strike Call，降低成本，風險有限。期權新手最安全的看漲入門。',
        dte: '30–45 天', delta: '淨 0.30 ~ 0.45', credit: false,
        maxProfit: '兩 Strike 差 − 淨 Debit', risk: '淨 Debit（全部 Premium）',
        defaultLegs: [
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.35, dte: 40 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.33, dte: 40 },
        ],
        detail: {
          what: '買低 Strike Call（方向腳）＋賣高 Strike Call（減少成本）。股票漲至賣出 Strike 上方 → 最大獲利；收在買入 Strike 下方 → 損失全部 Debit；介於兩 Strike 之間 → 部分獲利。風險與報酬都有明確上下限。',
          when: '看漲但 IV 不算特別低、希望降低買 Call 的成本、適合期權新手第一個有方向的策略。比單買 Call 便宜約 30–50%，風險固定且直觀易懂。',
          risks: '最大獲利有上限，股票大漲也只能賺到 Strike 差；兩腳 Bid-Ask 各吃一次；若股票介於兩 Strike 之間到期需要主動管理。',
          scenario: 'WULF $5.00，買 $5.00 Call / 賣 $6.00 Call，淨 Debit ~$0.25 = $25。最大獲利 $75（$100 − $25），風險回報比 1:3。WULF 漲至 $6.00 以上 → 全賺 $75。',
        },
      },
    ],
  },
  bearish: {
    high_iv: [
      {
        key: 'bear_call_spread', name: 'Bear Call Spread（熊市 Call 價差）',
        desc: '賣低 Strike Call + 買高 Strike Call，限定風險看跌收 Credit。',
        dte: '21–35 天', delta: '0.25 ~ 0.35', credit: true,
        maxProfit: '淨 Credit', risk: '兩 Strike 差 − 淨 Credit',
        defaultLegs: [
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.55, dte: 30 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.52, dte: 30 },
        ],
        detail: {
          what: '賣出較低 Strike 的 Call（收 Premium）＋買入較高 Strike 的 Call（付保護費）。股票收在賣出 Strike 下方 → 淨 Credit 全拿；漲進兩 Strike 之間 → 部分虧損；漲穿買入 Strike → 最大虧損。',
          when: 'IV 高（賣方有利）、看跌但不想裸賣 Call 承擔無限風險、希望限定保證金需求。適合高 IV 環境下的防守型看空策略。',
          risks: '股票大漲穿過整個 Spread 區間損失固定；兩腳 Bid-Ask 各吃成本；若股票急漲需要快速調整。',
          scenario: 'WULF $5.00，賣 $5.50 Call / 買 $6.00 Call，淨 Credit ~$0.12。只要 WULF 不漲超過 $5.50 就全賺 $12，最大虧損 $38。',
        },
      },
    ],
    low_iv: [
      {
        key: 'long_put', name: 'Long Put（買進賣權）',
        desc: '直接買 Put，低 IV 時 Premium 便宜，看跌方向最直接。',
        dte: '45–60 天', delta: '−0.30 ~ −0.50', credit: false,
        maxProfit: 'Strike − Premium（股票跌越多賺越多）', risk: '全部 Premium',
        defaultLegs: [{ type: 'long_put', strike: 0, premium: 0, quantity: 1, iv: 0.38, dte: 50 }],
        detail: {
          what: '買入 Put 期權，獲得以 Strike 賣出 100 股的「權利」。股票跌穿 Strike − Premium → 開始獲利；跌越多賺越多；沒跌 → 損失全部 Premium。',
          when: 'IV Rank 低（期權便宜）、強烈看跌、有系統性風險需要避險、有催化劑（壞消息、財報地雷）。',
          risks: 'Theta 每天衰減；股票橫盤不動慢慢虧損；IV 下降即使股票跌了也可能虧損（Long Vega 策略）。',
          scenario: 'WULF $5.00，買 50 天 $4.50 Put，Premium $0.25 = $25。股票需跌至 $4.25 才損益兩平，跌至 $3 獲利 $1.25（500%）。',
        },
      },
      {
        key: 'bear_put_spread', name: 'Bear Put Spread（熊市 Put 價差）',
        desc: '買高 Strike Put + 賣低 Strike Put，降低成本，風險有限的看跌策略。',
        dte: '30–45 天', delta: '淨 −0.30 ~ −0.45', credit: false,
        maxProfit: '兩 Strike 差 − 淨 Debit', risk: '淨 Debit',
        defaultLegs: [
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.42, dte: 40 },
          { type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.40, dte: 40 },
        ],
        detail: {
          what: '買高 Strike Put（方向腳）＋賣低 Strike Put（減少成本）。股票跌至賣出 Strike 下方 → 最大獲利；收在買入 Strike 上方 → 損失全部 Debit；介於兩 Strike 之間 → 部分獲利。',
          when: '看跌但 IV 不算低、希望降低買 Put 的成本、風險有限的看跌策略。適合有方向判斷但不想全押的交易者。',
          risks: '最大獲利有上限；兩腳 Bid-Ask 各吃一次；若股票反彈需要管理損失。',
          scenario: 'WULF $5.00，買 $5.00 Put / 賣 $4.00 Put，淨 Debit ~$0.30 = $30。最大獲利 $70，跌至 $4.00 以下全賺。風險回報比 1:2.3。',
        },
      },
    ],
  },
  neutral: {
    high_iv: [
      {
        key: 'iron_condor', name: 'Iron Condor（鐵兀鷹）',
        desc: '同時賣 Put Spread + Call Spread，在兩側築牆，中間盤整全賺。期權賣方的主力收租策略。',
        dte: '30–45 天', delta: '±0.15 ~ ±0.25', credit: true,
        maxProfit: '淨 Credit', risk: '翼部寬度 − 淨 Credit',
        defaultLegs: [
          { type: 'long_put',   strike: 0, premium: 0, quantity: 1, iv: 0.68, dte: 35 },
          { type: 'short_put',  strike: 0, premium: 0, quantity: 1, iv: 0.62, dte: 35 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.55, dte: 35 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.52, dte: 35 },
        ],
        detail: {
          what: '同時建立一個 Bull Put Spread（下方支撐）和一個 Bear Call Spread（上方阻力），形成中間的「盈利走廊」。只要股票到期時留在兩個賣出 Strike 之間 → 全部四條腿都過期無價值，淨 Credit 全拿。',
          when: 'IV Rank 高（賣方有利）、預期股票短期盤整不大動、財報後 IV Crush 之後最適合。四條腿都是賣方，是 Theta 正的策略，時間流逝對你有利。',
          risks: '股票大漲或大跌穿過翼部造成最大損失；進場後 IV 繼續上升（Delta 中性但 Short Vega 損失）；需要管理整個結構，調整成本較高。',
          scenario: 'WULF $5.00，賣 $4.50/$4.00 Put Spread + $5.50/$6.00 Call Spread，淨 Credit ~$0.18 = $18。只要 WULF 收在 $4.50–$5.50 之間 → 全賺 $18，最大虧損 $32。',
        },
      },
      {
        key: 'short_strangle', name: 'Short Strangle（賣出寬跨式）',
        desc: '賣 OTM Call + 賣 OTM Put，最大化 Premium 收入，無翼部保護。',
        dte: '30–45 天', delta: '±0.20 ~ ±0.30', credit: true,
        maxProfit: '淨 Credit', risk: '無限（需保證金）',
        defaultLegs: [
          { type: 'short_put',  strike: 0, premium: 0, quantity: 1, iv: 0.58, dte: 35 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.53, dte: 35 },
        ],
        detail: {
          what: '同時賣出 OTM Put 和 OTM Call，兩腳都收 Premium，只要股票收在兩 Strike 之間就全賺。比 Iron Condor 收更多 Premium，但沒有翼部保護，理論上兩個方向都有無限虧損風險。',
          when: '高 IV 環境、預期股票盤整、有足夠保證金承擔風險、操盤者有足夠經驗管理部位。需要主動監控並在突破時調整。',
          risks: '無限風險（特別是賣 Call 方）、需要較高保證金、突破時損失大且速度快、不適合新手或無法主動監控的人。',
          scenario: 'WULF $5.00，賣 $4.25 Put / $5.75 Call，收 Premium ~$0.25 = $25。只要 WULF 在 $4.25–$5.75 之間 → 全賺，超出範圍開始虧損。',
        },
      },
    ],
    low_iv: [
      {
        key: 'iron_butterfly', name: 'Iron Butterfly（鐵蝶式）',
        desc: 'ATM Short Straddle + OTM 翼部保護，押注「完全不動」，獲利最高但甜蜜區最窄。',
        dte: '21–35 天', delta: 'ATM（接近 0）', credit: true,
        maxProfit: '淨 Credit（最大）', risk: '翼部寬度 − 淨 Credit',
        defaultLegs: [
          { type: 'long_put',   strike: 0, premium: 0, quantity: 1, iv: 0.42, dte: 28 },
          { type: 'short_put',  strike: 0, premium: 0, quantity: 1, iv: 0.44, dte: 28 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.44, dte: 28 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.42, dte: 28 },
        ],
        detail: {
          what: '在 ATM 同時賣 Put + Call（Short Straddle），外側各買一個 OTM 選擇權作為保護翼。股票到期精準收在中間 Strike → 最大獲利（兩個賣出 Strike 都到期無價值）；離中間越遠損失越大；超出翼部 → 最大虧損固定。',
          when: 'IV Rank 低時用 Iron Condor 獲利有限，Butterfly 的 ATM 賣出可以拿到更多 Premium。預期股票「幾乎不動」，甜蜜區非常窄但最大獲利很高。',
          risks: '甜蜜區極窄，稍微移動就進入虧損；管理較複雜需要主動調整；不適合有明確方向預期的股票。',
          scenario: 'WULF $5.00，賣 $5.00 Put + $5.00 Call（ATM），買 $4.50 Put + $5.50 Call 翼，淨 Credit ~$0.35 = $35。WULF 到期收 $5.00 → 最大獲利 $35，偏離 $0.50 → 進入虧損。',
        },
      },
    ],
  },
  volatile: {
    any: [
      {
        key: 'long_straddle', name: 'Long Straddle（買入跨式）',
        desc: '同時買 ATM Call + Put，賭大波動不管方向。財報前的「賭波動」策略。最大敵人是不動 + Theta 衰減。',
        dte: '45–60 天', delta: '接近 0（方向中立）', credit: false,
        maxProfit: '無限（任一方向突破）', risk: '總 Premium（兩腳合計）',
        defaultLegs: [
          { type: 'long_call', strike: 0, premium: 0, quantity: 1, iv: 0.50, dte: 50 },
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.52, dte: 50 },
        ],
        detail: {
          what: '同時買入 ATM Call 和 ATM Put，兩腳都是買方。股票大漲 → Call 賺錢；大跌 → Put 賺錢；不管哪個方向只要突破夠大就獲利。最大損失是兩腳 Premium 合計（股票完全不動到到期）。',
          when: '有重大事件即將到來（財報、FDA 審批、重大政策），確定會有大波動但不確定方向。要在事件「發生前」建倉，事件「發生後」IV 通常會崩塌（IV Crush）。',
          risks: 'IV Crush 是最大殺手——財報後即使股票動了但 IV 暴跌，可能買 Call 賺的抵不上 IV 縮水的損失；Theta 每天衰減，時間是最大敵人；股票「雷聲大雨點小」輕微移動虧損。',
          scenario: 'WULF 財報前現價 $5.00，買 $5.00 Call + $5.00 Put，合計 Premium $0.60 = $60。上漲需突破 $5.60、下跌需跌穿 $4.40 才損益兩平。突破越多賺越多，盤整最多虧 $60。',
        },
      },
      {
        key: 'long_strangle', name: 'Long Strangle（買入寬跨式）',
        desc: '買 OTM Call + OTM Put，成本低於 Straddle，需要更大波動才能獲利。',
        dte: '45–60 天', delta: '接近 0（方向中立）', credit: false,
        maxProfit: '無限（任一方向突破）', risk: '總 Premium（較 Straddle 低）',
        defaultLegs: [
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.52, dte: 50 },
          { type: 'long_call', strike: 0, premium: 0, quantity: 1, iv: 0.50, dte: 50 },
        ],
        detail: {
          what: '買入 OTM Call 和 OTM Put，兩腳都在價外，成本比 Straddle 低 30–50%。但需要股票移動更大的幅度才能獲利，Break-even 區間更寬。適合預期「超大波動」但預算有限的情況。',
          when: '有重大事件但 ATM 期權太貴（IV 已很高），想降低成本同時保留大波動的獲利空間。也可以用 OTM 比例調整方向傾向（買更多 OTM Put 傾向看跌）。',
          risks: '與 Straddle 相同——IV Crush 和 Theta 衰減；移動幅度需要更大才能回本；OTM 的 Delta 較小，初期漲/跌對損益影響較小。',
          scenario: 'WULF $5.00，買 $5.50 Call + $4.50 Put，合計 Premium $0.35 = $35。上漲需至 $5.85、下跌需至 $4.15 才損益兩平，比 Straddle 需要更大移動但成本低 $25。',
        },
      },
      {
        key: 'long_call_butterfly', name: 'Long Call Butterfly（蝶式價差）',
        desc: '買低 + 買高 + 賣兩張中間 Call，成本極低但最大獲利高。猜「股價回到某個點」的精準策略。',
        dte: '30–45 天', delta: '接近 0（目標在中間）', credit: false,
        maxProfit: '翼部寬度 − 淨 Debit', risk: '淨 Debit（通常極低）',
        defaultLegs: [
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.42, dte: 35 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 2, iv: 0.40, dte: 35 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.38, dte: 35 },
        ],
        detail: {
          what: '買 1 張低 Strike Call + 賣 2 張中間 Strike Call + 買 1 張高 Strike Call。股票到期精準收在中間 Strike → 最大獲利（通常是翼部寬度 − 少量 Debit）；在翼部外面 → 損失全部 Debit（但 Debit 通常很少）。這個策略的風險回報比可達 1:5 以上。',
          when: '有一個明確的「目標股價」預測，認為股票會在某個特定價位附近到期。例如：技術分析顯示阻力位 / 支撐位、有股票回到近期均線的預期。成本很低，非常適合用來「精準賭一個點」。',
          risks: '甜蜜區很窄，稍微偏差就大幅減少獲利；若股票大漲或大跌超出翼部損失全部 Debit（雖然 Debit 小）；三腳 Bid-Ask 各吃一次成本比例相對 Debit 較高。',
          scenario: 'WULF $5.00，買 $4.50 Call / 賣 2x $5.00 Call / 買 $5.50 Call，淨 Debit ~$0.08 = $8。股票到期收 $5.00 → 最大獲利 $42。風險回報比約 1:5.3，押注「WULF 回到 $5」。',
        },
      },
    ],
  },
}

export function getStrategies(outlook: MarketOutlook, ivRank: number): StrategyTemplate[] {
  const env: IvEnv = ivRank >= 50 ? 'high_iv' : 'low_iv'
  return (
    STRATEGIES[outlook][env] ??
    STRATEGIES[outlook].any ??
    []
  )
}

export function buildLegsForPrice(
  template: StrategyTemplate,
  price: number
): StrategyTemplate['defaultLegs'] {
  const step = price < 5 ? 0.5 : price < 20 ? 1 : price < 50 ? 2.5 : price < 200 ? 5 : price < 500 ? 10 : 25

  return template.defaultLegs.map((leg, i) => {
    let strike: number

    if (template.key === 'iron_condor') {
      // [long_put, short_put, short_call, long_call]
      const offsets = [-2, -1, 1, 2]
      strike = Math.round((price + offsets[i] * step * 1.5) / step) * step

    } else if (template.key === 'iron_butterfly') {
      // [long_put, short_put(ATM), short_call(ATM), long_call]
      const offsets = [-2, 0, 0, 2]
      strike = Math.round((price + offsets[i] * step * 2) / step) * step

    } else if (template.key === 'long_call_butterfly') {
      // [long_call(low), short_call×2(ATM), long_call(high)]
      const offsets = [-2, 0, 2]
      strike = Math.round((price + offsets[i] * step) / step) * step

    } else if (template.defaultLegs.length === 2 && i === 0) {
      strike = leg.type.includes('put')
        ? Math.round((price * 0.90) / step) * step
        : Math.round((price * 1.05) / step) * step

    } else if (template.defaultLegs.length === 2 && i === 1) {
      strike = leg.type.includes('put')
        ? Math.round((price * 0.80) / step) * step
        : Math.round((price * 1.10) / step) * step

    } else {
      // Single-leg or fallback
      strike = leg.type.includes('put')
        ? Math.round((price * 0.90) / step) * step
        : Math.round((price * 1.10) / step) * step
    }

    const iv  = leg.iv  ?? 0.45
    const dte = leg.dte ?? 35
    const T   = dte / 365
    const intrinsicApprox = leg.type.includes('call')
      ? Math.max(price - strike, 0)
      : Math.max(strike - price, 0)
    const timeValue = iv * price * Math.sqrt(T) * 0.4
    const premium   = Math.max(Math.round((intrinsicApprox + timeValue) * 20) / 20, 0.05)

    return { ...leg, strike, premium }
  })
}
