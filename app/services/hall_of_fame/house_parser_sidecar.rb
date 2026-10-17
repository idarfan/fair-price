# frozen_string_literal: true

require "open3"

module HallOfFame
  # 呼叫 Python sidecar（lib/hall_of_fame/house_parser.py，名人堂專用 venv）解析一份 House PDF。
  # sidecar 只回 JSON（status／reasons／marker_count／rows），不碰資料庫。
  class HouseParserSidecar
    class Error < StandardError; end

    PYTHON          = Rails.root.join("lib/hall_of_fame/venv/bin/python").to_s
    SCRIPT          = Rails.root.join("lib/hall_of_fame/house_parser.py").to_s
    RANGES          = Rails.root.join("config/hall_of_fame_ranges.yml").to_s
    TIMEOUT_SECONDS = 300
    KINDS           = %w[ptr annual].freeze

    def parse(pdf_path, kind)
      raise ArgumentError, "kind 必須是 #{KINDS.join('/')}：#{kind}" unless KINDS.include?(kind)

      stdout, stderr, status = Open3.capture3(*command(pdf_path, kind))
      raise Error, "sidecar 結束碼 #{status.exitstatus}：#{stderr.strip.lines.last(3).join}" unless status.success?

      JSON.parse(stdout)
    rescue Errno::ENOENT => e
      raise Error, "sidecar 無法執行（venv 未建立？見 lib/hall_of_fame/requirements.txt）：#{e.message}"
    rescue JSON::ParserError => e
      raise Error, "sidecar 輸出不是 JSON：#{e.message}"
    end

    private

    # -I：隔離模式，不從 PDF 所在目錄或 cwd 載入模組。timeout：避免單一 PDF 卡死整批。
    def command(pdf_path, kind)
      [ "timeout", TIMEOUT_SECONDS.to_s, PYTHON, "-I", SCRIPT, "--kind", kind, "--ranges", RANGES, pdf_path.to_s ]
    end
  end
end
