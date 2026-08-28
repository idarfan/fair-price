# frozen_string_literal: true

module LeapsRecommendations::PageHeader
  def render_header
    div(class: "flex items-start justify-between gap-4") do
      div do
        h1(class: "text-xl font-bold text-gray-900") { plain "LEAPS Call 候選排行" }
        p(class: "text-sm text-gray-500 mt-0.5") { plain "Delta ≥ 0.60 深度價內 Call · 依 OI 由高到低排序" }
      end
      # 匯出按鈕：data-export-exclude 讓 html-to-image filter 把按鈕排除在輸出畫面外；
      # 無資料時 disabled，避免匯出空頁。
      div(class: "flex items-center gap-2", data_export_exclude: "") do
        render_tour_button
        render_export_button("png", "匯出 PNG")
        render_export_button("pdf", "匯出 PDF")
      end
    end
  end


  def render_tour_button
    exportable = @candidates.any?
    base  = "px-3 py-1.5 text-xs font-medium rounded-lg border transition-colors whitespace-nowrap"
    style = exportable ?
      "border-gray-300 bg-white text-gray-700 hover:bg-gray-50" :
      "border-gray-200 bg-gray-100 text-gray-400 cursor-not-allowed"
    button(id: "leaps-tour-btn", type: "button", disabled: !exportable,
           class: "#{base} #{style}") { plain "欄位導覽" }
  end


  def render_export_button(kind, label)
    exportable = @candidates.any?
    base  = "px-3 py-1.5 text-xs font-medium rounded-lg border transition-colors whitespace-nowrap"
    style = exportable ?
      "border-gray-300 bg-white text-gray-700 hover:bg-gray-50" :
      "border-gray-200 bg-gray-100 text-gray-400 cursor-not-allowed"
    button(
      id: "leaps-export-#{kind}", type: "button",
      data_leaps_export: kind, disabled: !exportable,
      data_track_action: "leaps_export_#{kind}",
      data_track_metadata: { symbol: @symbol }.to_json,
      class: "#{base} #{style}"
    ) { plain label }
  end


  def render_search_form
    form(id: "leaps-form", action: "/leaps", method: "get", class: "flex items-center gap-3 flex-wrap") do
      input(
        id: "leaps-symbol-input", type: "text", name: "symbol",
        value: @symbol.to_s, placeholder: "股票代號，例如 NOK",
        maxlength: "10",
        class: "w-40 px-4 py-2 rounded-lg border border-gray-300 text-sm font-mono uppercase " \
               "focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
      )
      div(class: "flex items-center gap-1.5") do
        label(for: "leaps-strike-input", class: "text-xs text-gray-500 whitespace-nowrap") { plain "履約價（選填）" }
        input(
          id: "leaps-strike-input", type: "number", name: "user_strike",
          value: @user_strike.to_s, placeholder: "自動",
          min: "0.01", step: "any",
          class: "w-24 px-3 py-2 rounded-lg border border-gray-300 text-sm " \
                 "focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
        )
      end
      button(
        id: "leaps-submit-btn", type: "submit",
        data_track_action: "leaps_filter",
        class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
      ) { plain "查詢" }
      div(id: "leaps-loading", class: "hidden items-center gap-2 text-sm text-gray-500") do
        div(class: "w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin")
        plain "抓取資料中，請稍候…（約 3–5 分鐘）"
      end
    end
    div(id: "leaps-strike-error",
        class: "hidden text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-3 py-2 mt-1")
  end


  def render_status_bar
    case @scrape_status
    when :session_expired
      render_alert("bg-orange-50 border border-orange-300 text-orange-800",
        "⚠️ 請先登入 Barchart 後重試。（Barchart 登入 Session 已過期）")
    when :partial_error
      expired_s  = partial_error_strike
      rec_strikes = recommendation_strikes
      if expired_s && rec_strikes.any? && !rec_strikes.any? { |s| s.to_f == expired_s }
        rec_list = rec_strikes.map { |s| "Strike #{fmt_strike_short(s)}" }.join("、")
        render_alert("bg-yellow-50 border border-yellow-300 text-yellow-800",
          "⚠️ Strike #{fmt_strike_short(expired_s)} 的 V&G 資料不完整，但不影響本次推薦（推薦候選為 #{rec_list}）")
      else
        msg = @scrape_errors.first || "抓取中途發生未預期錯誤，部分資料可能不完整，請重新查詢。"
        render_alert("bg-yellow-50 border border-yellow-300 text-yellow-800", "⚠️ #{msg}")
      end
    when :cdp_offline
      render_alert("bg-red-50 border border-red-300 text-red-800",
        "❌ CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動。若電腦曾經睡眠/喚醒，這通常是 WSL2 的 /mnt/c/ 掛載失效造成的，請在 Windows PowerShell 執行 wsl --shutdown 後等待 WSL2 重新啟動，再重試一次。")
    when :error
      msg = @scrape_errors.first.presence || "抓取時發生未知錯誤，請稍後重試。"
      render_alert("bg-red-50 border border-red-300 text-red-800", "❌ #{msg}")
    when :no_candidates
      msg = @user_strike.present? ?
        "這個履約價 #{@user_strike}（含緩衝檔）在所有到期日都沒有符合 Delta ≥ 0.60 的候選。請嘗試其他履約價，或留空讓系統自動偵測。" :
        "目前沒有符合篩選條件的候選，請嘗試調整 Delta 範圍或手動輸入履約價後重試。"
      render_alert("bg-orange-50 border border-orange-300 text-orange-800", "⚠️ #{msg}")
    when :invalid_strike
      msg = @scrape_errors.first.presence || "履約價不在有效範圍，請重新輸入。"
      render_alert("bg-red-50 border border-red-300 text-red-800", "❌ #{msg}")
    when :ready_to_fetch
      render_alert("bg-blue-50 border border-blue-300 text-blue-800",
        "ℹ️ 尚未取得 #{@symbol} 的 LEAPS 資料，請點「查詢」開始抓取。")
    end
  end


  def render_alert(class_str, msg)
    div(class: "px-4 py-3 rounded-lg text-sm #{class_str}") { plain msg }
  end


  def render_loading_script
    csrf = helpers.form_authenticity_token rescue ""
    # JavaScript 已搬到 app/frontend/behaviors/leapsLoading.js（稽核 H-3 Wave 2）。
    # 原本的 Ruby 插值改成 data attribute 傳入。
    div(data: { behavior: "leaps-loading", csrf: csrf })
  end


  def partial_error_strike
    return @_partial_error_strike if defined?(@_partial_error_strike)
    @_partial_error_strike = begin
      return nil unless @scrape_status == :partial_error
      msg = @scrape_errors.first.to_s
      m = msg.match(/Strike\s+(\d+(?:\.\d+)?)/)
      m ? m[1].to_f : nil
    end
  end


  def recommendation_strikes
    return [] unless @recommendation
    [
      @recommendation.dig(:near_term, :pick, :strike),
      @recommendation.dig(:far_term, :pick, :strike)
    ].compact
  end
end
