# frozen_string_literal: true

class ReportsController < ApplicationController
  include ActionController::Live
  def index
    @watchlist_items = WatchlistItem.ordered
    symbols          = @watchlist_items.map(&:symbol)
    @report          = MomentumReportService.new(symbols: symbols).call
    @vix             = @report[:vix]
    @stance          = derive_stance(@vix)
  end

  def analysis
    symbol = params[:symbol].to_s.upcase.strip
    return render(json: { error: "請提供股票代號" }, status: :bad_request) if symbol.blank?

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    stream_analysis(symbol)
  end

  def company_news
    symbol    = params.require(:symbol).upcase.strip
    from_date = (Date.current - 7).to_s
    to_date   = Date.current.to_s
    items     = FinnhubService.new.company_news(symbol, from_date: from_date, to_date: to_date)
    translator = TranslationService.new

    threads = items.map do |item|
      Thread.new do
        md = translator.translate_as_markdown(item["summary"].to_s)
        {
          headline:     translator.translate(item["headline"].to_s),
          content_html: md.present? ? render_gfm(md) : "",
          source:       item["source"],
          url:          item["url"],
          datetime:     format_epoch(item["datetime"])
        }
      end
    end

    render json: { symbol: symbol, news: threads.map(&:value) }
  rescue ActionController::ParameterMissing
    render json: { error: "missing symbol" }, status: :bad_request
  end

  def render_markdown
    html = render_gfm(params[:text].to_s)
    render json: { html: html }
  end

  private

  def stream_analysis(symbol)
    OuouAnalysisService.new(symbol: symbol).call do |chunk|
      response.stream.write("data: #{chunk.to_json}\n\n")
    end
  rescue ActionController::Live::ClientDisconnected, IOError
    nil
  rescue StandardError => e
    Rails.logger.error("[OuouAnalysis] #{e.class}: #{e.message}")
    response.stream.write("data: #{("[分析失敗] #{e.message}").to_json}\n\n")
  ensure
    response.stream.write("data: [DONE]\n\n")
    response.stream.close
  end

  # ── Markdown helpers ────────────────────────────────────────────────────────
  def render_gfm(text)
    Kramdown::Document.new(normalize_md_tables(text), input: "GFM").to_html
  end

  # Robust GFM table normalizer.
  #
  # Two-pass approach:
  # 1. Replace every separator row in-place (derive col count from pipe count — no
  #    look-ahead required, handles all non-ASCII dash variants).
  # 2. Drop blank lines that appear immediately before a separator row (Claude
  #    sometimes inserts a blank line between the header row and the separator).
  def normalize_md_tables(text) # rubocop:disable Metrics/MethodLength
    # Pass 1: rebuild every separator row with ASCII hyphens.
    lines = text.each_line.map do |line|
      if separator_row?(line)
        col_count = line.count("|") - 1
        "|#{"---|" * col_count}\n"
      else
        line
      end
    end

    # Pass 2: discard blank lines immediately preceding a separator row.
    result = []
    lines.each_with_index do |line, idx|
      next if line.strip.empty? && idx + 1 < lines.length && separator_row?(lines[idx + 1])

      result << line
    end

    result.join
  end

  # A separator row has no Unicode letters or digits — covers every dash variant.
  def separator_row?(line)
    s = line.strip
    s.start_with?("|") && s.end_with?("|") && s.length > 2 &&
      !s.match?(/[\p{L}\p{N}]/)
  end

  def format_epoch(epoch)
    return nil unless epoch

    Time.at(epoch.to_i).in_time_zone("Taipei").strftime("%m/%d %H:%M")
  end

  def derive_stance(vix)
    return :cash if vix.nil?

    if    vix < 16  then :aggressive
    elsif vix <= 22 then :conservative
    else                 :cash
    end
  end
end
