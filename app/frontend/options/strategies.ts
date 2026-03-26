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
      {
        key: 'pmcc', name: 'Poor Man\'s Covered Call（PMCC / 對角價差）',
        desc: '買長天期深價內 Call 替代持股 + 賣短天期 OTM Call 收租。低資金版 Covered Call。',
        dte: '長腳 120–180 天 / 短腳 21–35 天', delta: '長腳 0.70+ / 短腳 0.20–0.30', credit: false,
        maxProfit: '短腳 Strike − 長腳 Strike − 淨 Debit', risk: '淨 Debit（長腳 Premium − 短腳 Premium）',
        defaultLegs: [
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.35, dte: 150 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.33, dte: 30 },
        ],
        detail: {
          what: '用一張長天期深價內（Deep ITM）Call 模擬持有 100 股，同時賣出短天期 OTM Call 收月租。長腳 Delta 接近 0.70–0.80，走勢幾乎等同持股但成本遠低於買 100 股。短腳每月到期後可反覆賣出新的 OTM Call 持續收租。',
          when: 'IV 低時長腳便宜，適合看好股票長期走勢但資金不足以買 100 股的投資者。相較 Covered Call 需要整筆持股資金，PMCC 只需 1/3 到 1/5 的成本即可建倉。',
          risks: '股票大跌時長腳 Call 虧損幅度接近持股但 Theta 還在流失；短腳被 Assign 時需要回補（若短腳 Strike < 長腳 Strike + 淨 Debit 會出現虧損）；長腳到期前需要滾動續約（Roll），增加交易成本。',
          scenario: 'WULF $5.00，買 150 天 $3.50 Call（深 ITM，Delta ~0.75）付 $1.80，賣 30 天 $5.50 Call 收 $0.20。淨 Debit $1.60 = $160，相較買 100 股需 $500 省下 68%。每月收 $20 租金，4 個月回本。',
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
      {
        key: 'bear_put_spread_hiv', name: 'Bear Put Spread（高 IV 版）',
        desc: '買高 Strike Put + 賣低 Strike Put，高 IV 時賣出腳抵銷更多成本。',
        dte: '21–35 天', delta: '淨 −0.30 ~ −0.45', credit: false,
        maxProfit: '兩 Strike 差 − 淨 Debit', risk: '淨 Debit',
        defaultLegs: [
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.62, dte: 28 },
          { type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.58, dte: 28 },
        ],
        detail: {
          what: '買入較高 Strike 的 Put（方向腳）＋賣出較低 Strike 的 Put（降低成本）。高 IV 環境下賣出腳的 Premium 更豐厚，能大幅抵銷買入腳的成本，讓淨 Debit 降低、風險回報比提升。結構與低 IV 版相同，但進場時機更有利。',
          when: 'IV Rank 高但你看跌不想做賣方（怕被軋空頭），想要有方向性的有限風險策略。高 IV 讓 Spread 的淨成本降低，等 IV 回落時還有額外 Vega 獲利。適合財報前建倉看跌。',
          risks: '股票不跌反漲，損失全部淨 Debit；IV 持續上升時短腳虧損加大（但有長腳保護）；兩腳 Bid-Ask 各吃一次；需要在到期前主動管理。',
          scenario: 'WULF $5.00，買 $5.00 Put / 賣 $4.00 Put，高 IV 下淨 Debit 僅 ~$0.22 = $22。最大獲利 $78（$100 − $22），風險回報比 1:3.5。WULF 跌至 $4.00 以下全賺。',
        },
      },
      {
        key: 'put_ratio_backspread', name: 'Put Ratio Backspread（看跌比率回差）',
        desc: '賣 1 張 ATM Put + 買 2 張 OTM Put，大跌時爆發性獲利。',
        dte: '30–45 天', delta: '淨 −0.20 ~ −0.40', credit: false,
        maxProfit: '理論無限（股票跌至 0）', risk: '淨 Debit 或中間甜蜜區最大虧損',
        defaultLegs: [
          { type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.58, dte: 35 },
          { type: 'long_put',  strike: 0, premium: 0, quantity: 2, iv: 0.62, dte: 35 },
        ],
        detail: {
          what: '賣出 1 張較高 Strike（接近 ATM）的 Put 收 Premium，同時買入 2 張較低 Strike 的 Put。建倉可能是小額 Debit 或甚至 Credit。股票大跌時 2 張長腳 Put 的獲利遠超 1 張短腳的虧損，爆發性獲利。股票不動或小跌時有一個虧損甜蜜區（在兩個 Strike 之間）。',
          when: '預期可能出現大幅下跌（黑天鵝、重大利空），但不確定時間點。高 IV 環境下短腳收的 Premium 多，能大幅降低建倉成本。適合「大部分時間小虧、偶爾大賺」的交易者。',
          risks: '股票在兩 Strike 之間到期時會出現最大虧損（通常是 1 個 Strike 寬度 − 淨 Credit）；股票小幅下跌比完全不動更糟；需要「真正的大跌」才能獲利，溫和下跌反而虧最多。',
          scenario: 'WULF $5.00，賣 1x $5.00 Put 收 $0.45 / 買 2x $4.50 Put 付 $0.25 × 2。淨 Credit $0.00（幾乎零成本）。WULF 跌至 $3.50 → 獲利 $50；收在 $4.50 → 最大虧損 $50。',
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
      {
        key: 'put_diagonal', name: 'Put Diagonal Spread（看跌對角價差）',
        desc: '買長天期 ITM Put + 賣短天期 OTM Put，低成本版看跌策略，可反覆收租。',
        dte: '長腳 90–120 天 / 短腳 21–35 天', delta: '長腳 −0.60 / 短腳 −0.20', credit: false,
        maxProfit: '長腳 Strike − 短腳 Strike − 淨 Debit', risk: '淨 Debit',
        defaultLegs: [
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.40, dte: 100 },
          { type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.38, dte: 30 },
        ],
        detail: {
          what: '買入長天期價內 Put（方向腳，Delta −0.60 左右）＋賣出短天期 OTM Put（收租腳）。長腳提供看跌方向性，短腳每月到期後可反覆賣出新的 OTM Put 降低持倉成本。類似 PMCC 的看跌版本。',
          when: 'IV 低時長天期 Put 便宜，適合中長期看跌但不想一次投入太多 Premium。每月賣短腳收租，逐步降低建倉成本。適合有耐心的看空交易者。',
          risks: '股票反彈上漲時長腳 Put 虧損且 Theta 持續衰減；短腳被 Assign 時需要處理股票部位；滾動短腳時若 IV 持續走低可收租金額遞減。',
          scenario: 'WULF $5.00，買 100 天 $5.50 Put（ITM，Delta −0.60）付 $1.00，賣 30 天 $4.50 Put 收 $0.15。淨 Debit $0.85 = $85。每月收 $15 租金，3 個月後 WULF 跌至 $4.00 → 長腳獲利 $1.50 − 短腳虧損 $0.50 = 淨獲利 $1.00。',
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
      {
        key: 'jade_lizard', name: 'Jade Lizard（翡翠蜥蜴）',
        desc: 'Short Put + Bear Call Spread，上方無風險、下方有風險。高 IV 偏看漲的中性策略。',
        dte: '21–35 天', delta: '淨 −0.10 ~ −0.25', credit: true,
        maxProfit: '淨 Credit', risk: 'Put Strike − 淨 Credit（僅下方）',
        defaultLegs: [
          { type: 'short_put',  strike: 0, premium: 0, quantity: 1, iv: 0.58, dte: 30 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.53, dte: 30 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.50, dte: 30 },
        ],
        detail: {
          what: '賣出 OTM Put（下方）＋建立 Bear Call Spread（上方），三條腿合計收到的淨 Credit 大於 Call Spread 的寬度。這意味著上方完全沒有虧損風險（即使股票大漲也不虧），風險只在下方（股票大跌穿過 Put Strike）。',
          when: 'IV Rank 高、預期股票偏中性或微漲、想要比 Iron Condor 更寬鬆的上方空間。特別適合你不介意接股的標的——最壞情況就是以低價接股，上方完全免擔心。',
          risks: '股票大跌穿過 Put Strike 虧損無限（和裸賣 Put 相同）；建倉需要確保淨 Credit > Call Spread 寬度（否則上方仍有風險）；三腳 Bid-Ask 成本較高。',
          scenario: 'WULF $5.00，賣 $4.50 Put 收 $0.18 + 賣 $5.50 Call / 買 $6.00 Call 收 $0.08，淨 Credit $0.26 > $0.50 Spread 寬度 ✗（此例不成立）。實際需要選擇 Premium 更豐厚的 Strike 組合。高 IV 時容易達成條件。',
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
      {
        key: 'call_calendar_spread', name: 'Calendar Spread（Call 行事曆價差）',
        desc: '賣近月 ATM Call + 買遠月 ATM Call，賺 Theta 差值。低 IV 時遠月便宜。',
        dte: '近月 21–30 天 / 遠月 50–60 天', delta: '接近 0', credit: false,
        maxProfit: '近月到期時股票在 Strike 附近', risk: '淨 Debit',
        defaultLegs: [
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.38, dte: 25 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.36, dte: 55 },
        ],
        detail: {
          what: '賣出近月 ATM Call + 買入遠月相同 Strike 的 Call。近月 Call 的 Theta 衰減比遠月快，時間流逝讓近月 Call 更快貶值，產生獲利。近月到期時若股票在 Strike 附近 → 近月歸零，遠月仍有價值 → 最大獲利。',
          when: 'IV Rank 低、預期短期不動但中期可能有動作。低 IV 時遠月 Call 便宜，建倉成本低。若 IV 在建倉後上升（Long Vega），遠月 Call 價值增加更多 → 額外獲利。',
          risks: '股票大幅移動（不管方向）讓兩腳的價值差收窄，虧損淨 Debit；近月到期時若股票遠離 Strike → 兩腳都接近零，損失全部投入；IV 下降對遠月影響更大（Long Vega 逆風）。',
          scenario: 'WULF $5.00，賣 25 天 $5.00 Call 收 $0.30 / 買 55 天 $5.00 Call 付 $0.50，淨 Debit $0.20 = $20。25 天後 WULF 仍在 $5.00 → 近月歸零，遠月剩 ~$0.35 → 獲利 $15（75%）。',
        },
      },
      {
        key: 'double_diagonal', name: 'Double Diagonal（雙對角價差）',
        desc: '同時建立 Put 與 Call 的 Calendar Spread，雙向收 Theta 差值。盤整環境的全方位策略。',
        dte: '近月 21–30 天 / 遠月 50–60 天', delta: '接近 0', credit: false,
        maxProfit: '近月到期時股票在兩 Strike 之間', risk: '淨 Debit',
        defaultLegs: [
          { type: 'short_put',  strike: 0, premium: 0, quantity: 1, iv: 0.40, dte: 25 },
          { type: 'long_put',   strike: 0, premium: 0, quantity: 1, iv: 0.38, dte: 55 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.38, dte: 25 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.36, dte: 55 },
        ],
        detail: {
          what: '同時在 OTM Put 和 OTM Call 各建一組 Calendar Spread。近月兩腳 OTM（Delta 較小，Theta 衰減快）、遠月兩腳 OTM（提供方向保護和 Vega 獲利）。比 Iron Condor 多了遠月保護，比 Calendar Spread 多了第二個方向。',
          when: 'IV 低、預期短期盤整、想要比 Iron Butterfly 更寬的盈利區間。若 IV 在建倉後上升，四腳中遠月受益更多（Long Vega）。適合有耐心管理多腳策略的交易者。',
          risks: '四腳策略管理複雜，Bid-Ask 成本高；股票大幅移動讓所有腳的時間差值消失；近月到期時需要決定是否平倉遠月或繼續滾動。',
          scenario: 'WULF $5.00，賣近月 $4.50 Put + $5.50 Call，買遠月 $4.50 Put + $5.50 Call，淨 Debit 合計 ~$0.30 = $30。近月到期 WULF 在 $4.50–$5.50 之間 → 近月歸零，遠月仍有價值 → 獲利 ~$20。',
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

    } else if (template.key === 'jade_lizard') {
      // [short_put(OTM), short_call(OTM), long_call(further OTM)]
      const offsets = [-1, 1, 2]
      strike = Math.round((price + offsets[i] * step * 1.5) / step) * step

    } else if (template.key === 'put_ratio_backspread') {
      // [short_put(ATM), long_put×2(OTM)]
      const offsets = [0, -1]
      strike = Math.round((price + offsets[i] * step) / step) * step

    } else if (template.key === 'double_diagonal') {
      // [short_put(near OTM), long_put(far OTM), short_call(near OTM), long_call(far OTM)]
      const offsets = [-1, -1, 1, 1]
      strike = Math.round((price + offsets[i] * step * 1.5) / step) * step

    } else if (template.key === 'call_calendar_spread') {
      // Both legs ATM
      strike = Math.round(price / step) * step

    } else if (template.key === 'pmcc') {
      // [long_call(deep ITM far), short_call(OTM near)]
      if (i === 0) {
        strike = Math.round((price * 0.75) / step) * step // deep ITM
      } else {
        strike = Math.round((price * 1.10) / step) * step // OTM
      }

    } else if (template.key === 'put_diagonal') {
      // [long_put(ITM far), short_put(OTM near)]
      if (i === 0) {
        strike = Math.round((price * 1.10) / step) * step // ITM put
      } else {
        strike = Math.round((price * 0.90) / step) * step // OTM put
      }

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
