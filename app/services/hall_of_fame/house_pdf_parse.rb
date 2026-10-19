# frozen_string_literal: true

require "digest"

module HallOfFame
  # P3：下載 pending 的 House filing PDF，交給 sidecar 解析，寫入 hof_transactions／hof_holdings。
  # - PDF 存 storage/hall_of_fame/house/{year}/{doc_id}.pdf，記 sha256；檔案已在就不重下載。
  # - sidecar 回 needs_review（掃描檔、列數不符、未知標籤…）照樣寫入解析到的列，原因記 parse_error（§1-5）。
  # - 下載失敗維持 pending 等下次重試；sidecar 執行失敗或其他程式／環境錯誤標 failed（逐筆隔離，不中斷整批）。
  # - 不寫 hof_sync_runs：source 只有 house／oge，寫一筆 house run 會蓋掉 P2 條件式請求的 validators。
  class HousePdfParse
    SOURCE      = HouseIndexSync::SOURCE
    STORAGE_DIR = Rails.root.join("storage/hall_of_fame/house")
    KINDS       = { "ptr" => "ptr", "annual" => "annual", "amendment" => "annual" }.freeze
    TRADE_KEYS   = %w[owner asset_name ticker asset_type_code tx_type tx_date notified_date
                      amount_label amount_min amount_max description].freeze
    HOLDING_KEYS = %w[owner asset_name ticker asset_type value_label value_min value_max].freeze

    Summary = Data.define(:counts, :errors)

    def initialize(fetcher: HouseIndexFetcher.new, sidecar: HouseParserSidecar.new,
                   storage_dir: self.class::STORAGE_DIR, pause_seconds: 0.5)
      @fetcher       = fetcher
      @storage_dir   = Pathname(storage_dir)
      @sidecar       = sidecar
      @pause_seconds = pause_seconds
    end

    # 常數一律經 self.class:: 取用，讓 OgePdfParse（Q2）沿用同一套下載／存檔／寫入流程。
    def pending_scope = Filing.where(source: self.class::SOURCE, parse_status: "pending")

    def call(scope = pending_scope)
      counts = Hash.new(0)
      errors = []
      scope.order(:id).each do |filing|
        status, error = process(filing)
        counts[status] += 1
        errors << "#{filing.doc_id}：#{error}" if error
      end
      Summary.new(counts: counts, errors: errors)
    end

    private

    # 回傳 [狀態, 錯誤訊息或 nil]。
    def process(filing)
      path   = store_pdf(filing)
      result = @sidecar.parse(path, self.class::KINDS.fetch(filing.filing_type))
      save_result(filing, path, result)
      [ result.fetch("status"), nil ]
    rescue HouseIndexFetcher::Error => e
      [ "pending", e.message ]
    rescue HouseParserSidecar::Error => e
      mark_failed(filing, e.message)
    rescue StandardError => e
      # 逐筆隔離：IO、未知 filing_type、未預期的網路例外等只讓這一筆 failed，其餘照常處理。
      mark_failed(filing, "#{e.class}: #{e.message}")
    end

    # failed＝程式或環境錯誤（不是 PDF 內容問題），修好後以 hall_of_fame:retry_failed_house_pdfs 重跑。
    def mark_failed(filing, message)
      filing.update!(parse_status: "failed", parse_error: message, parsed_at: Time.current)
      [ "failed", message ]
    end

    # 先寫 .part 再 rename：中斷時只會留下 .part，不會被當成完整檔重用。
    def store_pdf(filing)
      path = @storage_dir.join(filing.year.to_s, "#{filing.doc_id}.pdf")
      return path if path.exist?

      body = @fetcher.fetch(filing.pdf_url).body
      FileUtils.mkdir_p(path.dirname)
      partial = path.sub_ext(".pdf.part")
      partial.binwrite(body)
      File.rename(partial, path)
      sleep(@pause_seconds) if @pause_seconds.positive?
      path
    end

    def save_result(filing, path, result)
      rows = result.fetch("rows")
      Filing.transaction do
        # option_details 外鍵指向 trades（P3b）；先刪，重新解析後由 analyze_options 依 premium_ref IS NULL 重算。
        OptionDetail.where(transaction_id: filing.trades.select(:id)).delete_all
        filing.trades.delete_all
        filing.holdings.delete_all
        insert_rows(filing, rows)
        filing.update!(
          pdf_path:     path.relative_path_from(Rails.root).to_s,
          sha256:       Digest::SHA256.file(path).hexdigest,
          parse_status: result.fetch("status"),
          parse_error:  parse_error_for(result),
          parsed_at:    Time.current
        )
      end
    end

    def parse_error_for(result) = result.fetch("reasons").join("\n").presence

    def insert_rows(filing, rows)
      return if rows.empty?

      if self.class::KINDS.fetch(filing.filing_type) == "ptr"
        Trade.insert_all(rows.map { |row| row.slice(*TRADE_KEYS).merge("filing_id" => filing.id) })
      else
        Holding.insert_all(rows.map { |row| row.slice(*HOLDING_KEYS).merge("filing_id" => filing.id) })
      end
    end
  end
end
