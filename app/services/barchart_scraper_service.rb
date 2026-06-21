require "open3"

# Scrapes Technical Analysis, Fundamentals, and Options Flow from Barchart
# using an existing Chrome CDP session (user must be logged in manually).
#
# Usage:
#   result = BarchartScraperService.new("MU").call
#   result[:status]  # => "success" | "barchart_session_expired" | "error"
class BarchartScraperService
  CDP_URL    = "http://localhost:9222"
  SCRIPT_DIR = Rails.root.join("lib", "barchart_scrapers")

  def initialize(symbol)
    @symbol = symbol.upcase
    @today  = Date.today
  end

  def call
    result = { symbol: @symbol, status: nil, errors: [] }

    unless cdp_available?
      result[:status] = "error"
      result[:errors] << "Chrome CDP not reachable at #{CDP_URL}"
      log_fetch("technical", "error", "CDP unavailable")
      return result
    end

    %w[technical fundamental options_flow].each do |type|
      fetch_result = run_scraper(type)
      if fetch_result[:status] == "barchart_session_expired"
        result[:status] = "barchart_session_expired"
        log_fetch(type, "barchart_session_expired", nil)
        return result
      elsif fetch_result[:status] == "success"
        persist(type, fetch_result[:data])
        log_fetch(type, "success", nil)
      else
        result[:errors] << "#{type}: #{fetch_result[:error]}"
        log_fetch(type, "error", fetch_result[:error])
      end

      sleep(rand(3.0..6.0)) unless type == "options_flow"
    end

    result[:status] = result[:errors].empty? ? "success" : "partial_error"
    result
  end

  private

  def cdp_available?
    uri = URI.parse("#{CDP_URL}/json/version")
    Net::HTTP.get_response(uri).is_a?(Net::HTTPSuccess)
  rescue
    false
  end

  def run_scraper(type)
    script = SCRIPT_DIR.join("#{type}_scraper.py")
    stdout, stderr, status = Open3.capture3(
      "python3", script.to_s, @symbol,
      chdir: Rails.root.to_s
    )

    if status.success?
      data = JSON.parse(stdout)
      if data["status"] == "barchart_session_expired"
        { status: "barchart_session_expired" }
      else
        { status: "success", data: data }
      end
    else
      { status: "error", error: stderr.strip.first(500) }
    end
  rescue JSON::ParserError => e
    { status: "error", error: "JSON parse error: #{e.message}" }
  end

  def persist(type, data)
    model = {
      "technical"    => TechnicalAnalysis,
      "fundamental"  => Fundamental,
      "options_flow" => OptionsFlow
    }[type]

    permitted = data.select { |k, _| model.column_names.include?(k.to_s) }
                    .transform_keys(&:to_sym)
    permitted[:fetched_at] = Time.current

    record = model.find_or_initialize_by(symbol: @symbol, snapshot_date: @today)
    record.assign_attributes(permitted)
    record.save!
  end

  def log_fetch(type, status, detail)
    FetchLog.create!(
      symbol:       @symbol,
      fetch_type:   type,
      status:       status,
      error_detail: detail,
      fetched_at:   Time.current
    )
  end
end
