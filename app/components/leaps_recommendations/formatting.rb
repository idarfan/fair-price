# frozen_string_literal: true

module LeapsRecommendations::Formatting
  # PDF（autotable）不能用 Tailwind class，改用等義 hex 值；語義選擇仍走既有
  # LIQUIDITY_STYLE / DIR_STYLE 的 key（tier / direction），只有顏色的「表示法」
  # 從 class 換成 hex，語義對應本身沒有另造一套。
  PDF_SIGNAL_HEX = {
    confirm_bull: { bg: "#f0fdf4", border: "#86efac", text: "#166534", dot: "#4ade80" },
    caution:      { bg: "#fefce8", border: "#fde047", text: "#854d0e", dot: "#facc15" },
    warning:      { bg: "#fff7ed", border: "#fdba74", text: "#9a3412", dot: "#fb923c" },
    confirm_bear: { bg: "#fef2f2", border: "#fca5a5", text: "#991b1b", dot: "#f87171" },
    neutral:      { bg: "#f9fafb", border: "#d1d5db", text: "#4b5563", dot: "#9ca3af" }
  }.freeze


  def pdf_signal_rgb_for_tier(tier)
    key = case tier
    when "充足" then :confirm_bull
    when "普通" then :caution
    when "偏低" then :warning
    else :neutral
    end
    PDF_SIGNAL_HEX[key]
  end


  def pdf_signal_rgb_for_direction(dir)
    key = case dir
    when "bullish" then :confirm_bull
    when "bearish" then :confirm_bear
    else :neutral
    end
    PDF_SIGNAL_HEX[key]
  end


  def pmcc_signed_color(val)
    return "" if val.nil?
    val.to_f >= 0 ? "text-green-600" : "text-red-600"
  end


  # premium_yield／premium_yield_ann 在 PmccRankingService 已經是「百分比數字」
  # （7.88 代表 7.88%，不是 0.0788），跟 fmt_pct（吃小數再 ×100）用途不同，
  # 不能共用同一支 formatter，否則會被再乘一次 100 變成離譜的數字。
  def fmt_pmcc_pct(val)
    return "—" if val.nil?
    sprintf("%.1f%%", val.to_f)
  end

  # ── PMCC v3 §9.2: 教育說明區（無資料也要獨立渲染，不得 500） ──────────────────
  #
  # CSS Token 精確移植 lesson9 :root（規格明文禁止重新設計），用 Tailwind
  # arbitrary values 表達，不建立獨立 scoped CSS 檔。


  def fmt_strike_short(val)
    f = val.to_f
    f == f.to_i ? f.to_i.to_s : f.to_s
  end

  # ── 表格點表頭排序（LEAPS 排行表 + PMCC 表共用同一套 JS，見 render_sortable_table_script）──


  def fmt_int(val)
    return "—" if val.nil?
    n = val.to_i
    n.abs >= 1_000 ? sprintf("%d", n).reverse.scan(/\d{1,3}/).join(",").reverse : n.to_s
  end


  def fmt_price(val)
    return "—" if val.nil?
    sprintf("%.2f", val.to_f)
  end


  def fmt_decimal(val, digits)
    return "—" if val.nil?
    sprintf("%.#{digits}f", val.to_f)
  end


  def fmt_pct(val)
    return "—" if val.nil?
    sprintf("%.1f%%", val.to_f * 100)
  end


  # IV 顏色分級（LEAPS 排行表 IV 欄位）：IV 越高，權利金越貴、IV Crush 風險越大，
  # 用顏色讓使用者一眼看出這口合約的波動率水位。
  #   ≤ 30%：綠（波動率便宜）／ 30%–50%：黃（偏貴，留意）／ > 50%：紅（昂貴，IV Crush 風險高）
  # val 與 fmt_pct 同樣是小數（0.30 代表 30%）。
  IV_GREEN_MAX  = 0.30
  IV_YELLOW_MAX = 0.50

  def iv_color_class(val)
    return "text-gray-400" if val.nil?

    iv = val.to_f
    if iv <= IV_GREEN_MAX
      "text-green-600 font-bold"
    elsif iv <= IV_YELLOW_MAX
      "text-yellow-600 font-bold"
    else
      "text-red-600 font-bold"
    end
  end


  def fmt_premium(val)
    return "—" if val.nil?
    n = val.to_i
    if n >= 1_000_000
      sprintf("$%.1fM", n / 1_000_000.0)
    elsif n >= 1_000
      sprintf("$%.0fK", n / 1_000.0)
    else
      sprintf("$%d", n)
    end
  end
end
