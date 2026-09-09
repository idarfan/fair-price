# frozen_string_literal: true

# Price-In 反推工具。
#
# 情境狀態一律走 query string（不建資料表），因此 #index 沒有任何寫入行為，
# 整頁可以靠 URL 完整重現。
class PriceInController < ApplicationController
  def index
    @form = PriceIn::ScenarioForm.from_params(params)

    # 參數不合法時照樣回 200 並顯示錯誤——500 或轉址會把使用者辛苦填的
    # query string 丟掉，而那正是他要拿來重現這張圖的東西。
    @chart_a = build_chart_a if @form.valid?
    @chart_b = build_chart_b if @form.valid? && @form.chart_b_ready?

    render PriceIn::PageComponent.new(
      form: @form, chart_a: @chart_a, chart_b: @chart_b,
      audit: build_audit, valuation: cached_valuation, logo: company_logo
    )
  end

  # 帶入現價。頁面載入時不自動抓價，一律由使用者主動觸發——
  # 這是估值工具不是報價看板，自動抓價會讓使用者誤以為圖表隨行情更新。
  def quote
    ticker = params[:ticker].to_s.strip.upcase

    unless ticker.match?(PriceIn::ScenarioForm::TICKER_FORMAT)
      return render json: { ok: false, error_code: "invalid_ticker", message: "代號格式不正確" },
                    status: :unprocessable_content
    end

    result = PriceIn::QuoteFetcher.call(ticker)
    # 順便暖 logo 快取：使用者已經明確要求連線，多這一次往返不會讓人意外，
    # 而且換來的是之後每次開圖都有 logo 且零上游請求。
    PriceIn::CompanyLogoService.call(ticker) if result.ok?

    if result.ok?
      render json: {
        ok: true, ticker: ticker, price: result.price,
        as_of: result.as_of.iso8601,
        # 以下皆可能為 nil（虧損公司、上游未提供、同業樣本不足）。
        # 前端顯示破折號，不當成錯誤。
        eps_ttm:     result.eps_ttm,
        pe:          result.pe.to_h,
        forward_pe:  result.forward_pe.to_h,
        peer_low:    result.peer_low,
        peer_high:   result.peer_high,
        peer_sample: result.peer_sample,
        eps_estimate:      result.eps_estimate.to_h,
        eps_estimate_next: result.eps_estimate_next.to_h
      }
    else
      # 上游失敗回 200 而非 5xx：這是一個「可以失敗」的輔助功能，
      # 圖表照常以現有價格重繪，前端不該把它當成頁面壞掉。
      render json: { ok: false, error_code: result.error_code.to_s, message: result.error_message }
    end
  end

  private

  # 公司 logo。頁面載入只讀快取，不打上游——快取由 #quote（使用者按
  # 「帶入現價」）順便暖起來。沒有就退回 📈 emoji，logo 是裝飾不該卡流程。
  def company_logo
    return nil unless @form.valid?

    PriceIn::CompanyLogoService.cached(@form.ticker)
  end

  # 使用者按過「帶入現價」（price_as_of 有值）才嘗試從快取還原估值對照。
  # 只讀快取、不打上游——「重新出圖」不該變成一次隱形的報價請求。
  def cached_valuation
    return nil if @form.price_as_of.blank?

    PriceIn::QuoteFetcher.cached(@form.ticker)
  end

  # 匯出前的歸屬稽核（§S8.3）。掃描的是「會被寫進成品圖」的使用者輸入——
  # 年度標籤、色帶來源、買入價標籤。機構名一旦標錯，看圖的人沒有辦法從圖上
  # 察覺，所以在按下匯出之前先問一次。
  def build_audit
    return {} unless @form.valid?

    text = [
      @form.fiscal_year_label, @form.chart_b_fiscal_year_label,
      @form.eps_band_label, @form.entry_a_label, @form.entry_b_label
    ].compact.join(" ")

    hits = PriceIn::AttributionAuditor.new(text: text, sources: @form.attribution_sources).hits
    { "chart_a" => hits, "chart_b" => hits }
  end

  def build_chart_a
    PriceIn::RequiredEpsCalculator.call(
      price:     @form.price,
      multiples: @form.chart_a_multiples,
      band_low:  @form.eps_band_low,
      band_high: @form.eps_band_high
    )
  end

  def build_chart_b
    PriceIn::EntryReturnCalculator.call(
      eps:           @form.eps,
      multiples:     @form.chart_b_multiples,
      entry_prices:  [ @form.entry_a_price, @form.entry_b_price ],
      holding_years: @form.holding_years
    )
  end
end
