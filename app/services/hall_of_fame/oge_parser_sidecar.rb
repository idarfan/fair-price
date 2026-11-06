# frozen_string_literal: true

require "open3"

module HallOfFame
  # 呼叫 Python sidecar（lib/hall_of_fame/oge_parser.py）解析一份 OGE 278e。只回 JSON，不碰資料庫。
  # 介面與 HouseParserSidecar 相同（parse(path, kind)），讓 OgePdfParse 沿用 HousePdfParse 的流程。
  class OgeParserSidecar
    Error = HouseParserSidecar::Error

    PYTHON          = HouseParserSidecar::PYTHON
    SCRIPT          = Rails.root.join("lib/hall_of_fame/oge_parser.py").to_s
    RANGES          = HouseParserSidecar::RANGES
    TIMEOUT_SECONDS = 1800 # Trump 2026 年報 927 頁
    KINDS           = %w[annual].freeze

    def parse(pdf_path, kind)
      raise ArgumentError, "kind 必須是 #{KINDS.join('/')}：#{kind}" unless KINDS.include?(kind)

      stdout, stderr, status = Open3.capture3(*command(pdf_path))
      raise Error, "sidecar 結束碼 #{status.exitstatus}：#{stderr.strip.lines.last(3).join}" unless status.success?

      JSON.parse(stdout)
    rescue Errno::ENOENT => e
      raise Error, "sidecar 無法執行（venv 未建立？見 lib/hall_of_fame/requirements.txt）：#{e.message}"
    rescue JSON::ParserError => e
      raise Error, "sidecar 輸出不是 JSON：#{e.message}"
    end

    private

    def command(pdf_path)
      [ "timeout", TIMEOUT_SECONDS.to_s, PYTHON, "-I", SCRIPT, "--ranges", RANGES, pdf_path.to_s ]
    end
  end
end
