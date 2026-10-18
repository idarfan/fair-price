# frozen_string_literal: true

module HallOfFame
  # P4 每日排程：P2 索引同步 → P3 解析 pending PDF → P3b 期權分析（使用者裁示加入，排在最後）。
  # 每一步各寫自己的 hof_sync_runs（kind = index／pdf_parse／options）；某一步拋例外只記錄並繼續下一步，
  # 例外訊息收進 failures，由 rake 以非零結束碼回報給 pm2。
  class HouseDailySync
    SOURCE = HouseIndexSync::SOURCE

    Result = Data.define(:runs, :failures) do
      def ok? = failures.empty?
    end

    def initialize(index: HouseIndexSync.new, parser: HousePdfParse.new, options: OptionAnalysis.new)
      @index   = index
      @parser  = parser
      @options = options
    end

    def call
      failures = []
      runs = {
        "index"     => step("index", failures) { @index.call },
        "pdf_parse" => step("pdf_parse", failures) { parse_pending },
        "options"   => step("options", failures) { @options.call }
      }
      Result.new(runs: runs.compact, failures: failures)
    end

    private

    def step(kind, failures)
      yield
    rescue StandardError => e
      failures << "#{kind}：#{e.class}: #{e.message}"
      Rails.logger.error("[hall_of_fame:sync_house] #{kind} 失敗：#{e.class}: #{e.message}")
      nil
    end

    # HousePdfParse 本身不寫 hof_sync_runs（P3），由這裡包一筆 pdf_parse 紀錄。
    def parse_pending
      run = SyncRun.create!(source: SOURCE, kind: "pdf_parse", started_at: Time.current)
      summary = @parser.call
      run.update!(finished_at: Time.current, error_count: summary.errors.size,
                  error_log: [ counts_line(summary), *summary.errors ].join("\n"))
      run
    rescue StandardError => e
      run&.update!(finished_at: Time.current, error_count: run.error_count + 1, error_log: "#{e.class}: #{e.message}")
      raise
    end

    def counts_line(summary)
      counts = summary.counts.sort.map { |status, n| "#{status} #{n}" }.join("、")
      "本次處理：#{counts.presence || '無 pending'}"
    end
  end
end
