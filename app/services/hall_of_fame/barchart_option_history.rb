# frozen_string_literal: true

require "open3"

module HallOfFame
  # 呼叫 lib/hall_of_fame/barchart_option_history.py，讀 Barchart 期權合約 price-history 頁的 DOM
  # （絕對不呼叫 Barchart API）。同一批次內每個合約只開一次頁面。
  class BarchartOptionHistory
    PYTHON          = HouseParserSidecar::PYTHON
    SCRIPT          = Rails.root.join("lib/hall_of_fame/barchart_option_history.py").to_s
    TIMEOUT_SECONDS = 120

    # 'MSFT|20261016|340.00C'
    def self.contract_symbol(ticker, expiration, strike, right)
      "#{ticker}|#{expiration.strftime('%Y%m%d')}|#{format('%.2f', strike)}#{right == 'call' ? 'C' : 'P'}"
    end

    def initialize
      @cache = {}
    end

    # 回傳 sidecar 的 Hash（"status" 為 success／empty／wrong_page／barchart_session_expired／error）。
    def fetch(contract, screenshot: nil)
      @cache[contract] ||= run(contract, screenshot)
    end

    private

    def run(contract, screenshot)
      cmd = [ "timeout", TIMEOUT_SECONDS.to_s, PYTHON, "-I", SCRIPT, contract ]
      cmd += [ "--screenshot", screenshot.to_s ] if screenshot
      stdout, stderr, status = Open3.capture3(*cmd)
      return { "status" => "error", "error" => "結束碼 #{status.exitstatus}：#{stderr.strip.lines.last(2).join}" } unless status.success?

      JSON.parse(stdout)
    rescue Errno::ENOENT, JSON::ParserError => e
      { "status" => "error", "error" => "#{e.class}: #{e.message}" }
    end
  end
end
