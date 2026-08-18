# frozen_string_literal: true

module LeapsRecommendations::SharedConstants
  LIQUIDITY_STYLE = {
    "充足" => ApplicationComponent::SIGNAL_COLORS[:confirm_bull],
    "普通" => ApplicationComponent::SIGNAL_COLORS[:caution],
    "偏低" => ApplicationComponent::SIGNAL_COLORS[:warning]
  }.freeze


  DIR_STYLE = {
    "bullish" => ApplicationComponent::SIGNAL_COLORS[:confirm_bull].merge(label: "偏多").freeze,
    "bearish" => ApplicationComponent::SIGNAL_COLORS[:confirm_bear].merge(label: "偏空").freeze,
    "neutral" => ApplicationComponent::SIGNAL_COLORS[:neutral].merge(label: "中性").freeze
  }.freeze


  # 術語字卡（leaps-column-tooltips-spec.md「術語字卡區」）：15 張，音標依 instruction 逐字，
  # 背面文案沿用 LEAPS_COL_EXPLAIN 觀點擴寫（買方視角），例子取自本頁實測資料。
  VOCAB_CARDS = [
    { en: "LEAPS", ipa: "/liːps/", zh: "長天期選擇權", hint: "Long-term Equity AnticiPation Securities",
      back: "到期日一年以上的選擇權，時間緩衝大，適合取代持股做方向部位；本表只列 DTE ≥ 364 的合約。",
      ex: "例：2028-01-21 到期、DTE 568 天的 Call 就是 LEAPS。" },
    { en: "Strike Price", ipa: "/straɪk praɪs/", zh: "履約價", hint: "你約定買入股票的價格",
      back: "Call 買方有權以履約價買入正股；履約價越低於現價越深價內，行為越接近持有正股。",
      ex: "例：現價 $14.46 時，$10 Call 已深入價內 $4.46。" },
    { en: "Delta", ipa: "/ˈdɛltə/", zh: "方向敏感度", hint: "股價動 $1，權利金動多少",
      back: "股價每動 $1，權利金理論上變動 Delta 元；也近似到期價內機率。本表篩 Delta ≥ 0.60 的深價內區間。",
      ex: "例：Delta 0.85 的 Call，股價 +$1 → 權利金約 +$0.85。" },
    { en: "Open Interest", ipa: "/ˈoʊpən ˈɪntrəst/", zh: "未平倉量", hint: "市場上還活著的合約數",
      back: "尚未平倉的合約總數，只在盤後更新；是本表排序主鍵，OI 越高通常越容易進出。",
      ex: "例：OI 8,273 的檔位遠比 OI 349 的容易成交。" },
    { en: "Volume", ipa: "/ˈvɑːljuːm/", zh: "成交量", hint: "今天實際成交了幾口",
      back: "當日即時成交口數。OI 高但 Volume 長期為零，實際進出仍可能困難，要搭配著看。",
      ex: "例：Volume 145、OI 8,273 → Vol/OI ≈ 0.018，近期交投清淡。" },
    { en: "Bid", ipa: "/bɪd/", zh: "買價", hint: "市場願意付的最高價",
      back: "掛單簿上的最高買價，是你「賣出」時的底價參考；市價賣出約落在 Bid 附近。",
      ex: "例：Bid 8.70／Ask 9.95 時，市價賣出約拿 $8.70。" },
    { en: "Ask", ipa: "/æsk/", zh: "賣價", hint: "市場願意賣的最低價",
      back: "掛單簿上的最低賣價，是你「買入」時的天花板參考；直接市價買會付到 Ask。",
      ex: "例：市價買付 $9.95，掛 Mid 約可省 $0.63。" },
    { en: "Mid Price", ipa: "/mɪd praɪs/", zh: "中間價", hint: "(Bid+Ask)/2，掛單參考",
      back: "Bid 與 Ask 的中點，掛限價單的參考價；本系統所有衍生欄位一律以 Mid 為權利金基準。",
      ex: "例：Bid 8.70／Ask 9.95 → Mid 9.325。" },
    { en: "Spread", ipa: "/sprɛd/", zh: "買賣價差", hint: "一次進出的滑價成本",
      back: "Ask−Bid 的距離；深價內 LEAPS 常偏寬，Spread% 超過 10% 進出成本明顯，建議用限價單。",
      ex: "例：(9.95−8.70)/9.325 ≈ 13.4%，偏寬。" },
    { en: "Intrinsic Value", ipa: "/ɪnˈtrɪnsɪk ˈvæljuː/", zh: "內在價值", hint: "已經在錢裡的部分",
      back: "max(0, 現價−履約價)，權利金裡「已在錢裡」的部分，股價不動也不會流失。",
      ex: "例：現價 14.46、履約價 10 → 內在 $4.46。" },
    { en: "Extrinsic Value", ipa: "/ɛkˈstrɪnsɪk ˈvæljuː/", zh: "外在價值", hint: "付出去的保險費",
      back: "Mid−內在價值，時間＋波動率溢價；隨時間流逝與 IV 回落而流失，是買方的主要成本。",
      ex: "例：Mid 9.325−內在 4.46 → 外在 $4.865，佔比 52%。" },
    { en: "Implied Volatility", ipa: "/ɪmˈplaɪd ˌvɑːləˈtɪləti/", zh: "隱含波動率", hint: "市場預期的波動大小",
      back: "由市場價格反推的預期波動；IV 越高權利金越貴，買方在高 IV 位進場要小心回落侵蝕。",
      ex: "例：IV 121.7% 屬極高水位，外在價值特別肥。" },
    { en: "Vega", ipa: "/ˈveɪɡə/", zh: "IV 敏感度", hint: "IV 動 1%，權利金動多少",
      back: "IV 每變 1% 權利金的理論變化；DTE 越長 Vega 越大，LEAPS 買方天然是 Vega 多頭。",
      ex: "例：Vega 0.0418 → IV 回落 10%，權利金約損失 $0.42。" },
    { en: "IV Crush", ipa: "/aɪ viː krʌʃ/", zh: "波動率回落", hint: "外在價值的瞬間蒸發",
      back: "IV 快速下降造成外在價值蒸發（常見於財報後）；高 IV 買入 LEAPS 的主要風險之一。",
      ex: "例：IV 120% → 80%，Vega 0.04 → 約損 $1.6。" },
    { en: "Assignment", ipa: "/əˈsaɪnmənt/", zh: "被指派", hint: "到期價內就會發生",
      back: "賣方被要求履約；買方視角對應「行權」。本表「被指派機率」欄＝Barchart 估的到期價內機率。",
      ex: "例：ITM Prob 59.6% ≈ 六成機率到期仍在價內。" }
  ].freeze
end
