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

    render json: {
      symbol: symbol,
      news: threads.map do |t|
        t.value
      rescue => e
        Rails.logger.warn("[ReportsController#company_news] thread error: #{e.class} #{e.message}")
        { error: "translation failed" }
      end
    }
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
    Kramdown::Document.new(normalize_md_tables(normalize_llama_output(text)), input: "GFM").to_html
  end

  # Fix Llama-specific markdown issues before passing to normalize_md_tables.
  #
  # Handles four Llama output problems:
  #   A) mid-line heading WITHOUT space  ("text##2. Title")  → split + add space
  #   B) mid-line heading WITH space     ("text## Title")    → split
  #   C) heading-start without space     ("##Title")         → add space
  #   D) table or blockquote glued to heading on same line   → split
  #   E) line-by-line: ensure blank line after every heading
  def normalize_llama_output(text) # rubocop:disable Metrics/MethodLength
    # Pass A: mid-line heading WITHOUT space after # ("text##2. Title")
    text = text.gsub(/([^\n])\n?(#+)([^#\s\n])/) { $1 + "\n\n" + $2 + " " + $3 }

    # Pass B: mid-line heading WITH space after # ("text## Title")
    text = text.gsub(/([^\n])(#+\s)/) { $1 + "\n\n" + $2 }

    # Pass C: heading-start without space ("##Title" → "## Title")
    text = text.gsub(/^(#+)([^#\s\n])/) { $1 + " " + $2 }

    # Pass D1: table row glued to end of heading line ("### Heading| col1 |")
    text = text.gsub(/^(#+\s[^|\n]+)\|/) { $1 + "\n\n|" }

    # Pass D2: blockquote glued to non-blank content ("text> quote")
    text = text.gsub(/([^\n])\n?(>\s)/) { $1 + "\n\n" + $2 }

    # Pass E: ensure blank line after every heading line.
    lines  = text.split("\n", -1)
    result = []
    lines.each_with_index do |line, i|
      result << line
      next_line = lines[i + 1]
      if line.match?(/^#+\s/) && next_line && !next_line.strip.empty?
        result << ""
      end
    end
    result.join("\n")
  end

  # Robust GFM table normalizer.
  #
  # Two-pass approach:
  # 1. Replace every separator row in-place (derive col count from pipe count — no
  #    look-ahead required, handles all non-ASCII dash variants).
  # 2. Drop blank lines that appear immediately before a separator row.
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

    if    vix < MomentumThresholds::VIX_AGGRESSIVE_MAX   then :aggressive
    elsif vix <= MomentumThresholds::VIX_CONSERVATIVE_MAX then :conservative
    else                                                        :cash
    end
  end
end
