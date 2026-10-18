# frozen_string_literal: true

module HallOfFame
  # Q1：同步 OGE 行政高層的公開申報清單進 hof_filings（source = oge）。
  # 探勘結果與裁示（2026-10-18，見規格 Q1「探勘結果」）：
  # - 關卡：先對 Domino view `Presiden.nsf/Index?ReadViewEntries` 發條件式請求（§1-10），304 即結束；
  #   view 本身沒有 PDF 檔名，所以有變動時改用 OGE 搜尋頁的資料源 REST API（API.xsp/v3/rest）依姓查詢。
  # - Annual／Nominee 278／Termination／New Entrant → oge_278e；278 Transaction → oge_278t；其餘文件忽略。
  # - 沒有 PDF（只能書面申請）的 278 類報告不寫入，列在 error_log 警示。
  # - 比對規則同 House：Last 完全相同＋First 前綴相同（Doug → Douglas J）。
  class OgeIndexSync
    SOURCE    = "oge"
    BASE      = "https://extapps2.oge.gov/201/Presiden.nsf"
    GATE_URL  = "#{BASE}/Index?ReadViewEntries&OutputFormat=JSON&Count=1".freeze
    API_URL   = "#{BASE}/API.xsp/v3/rest".freeze
    PAGE_SIZE = 100
    FILING_TYPES = [
      [ /\AAnnual\b/,          "oge_278e" ],
      [ /\ANominee 278\b/,     "oge_278e" ],
      [ /\ATermination\b/,     "oge_278e" ],
      [ /\ANew Entrant\b/,     "oge_278e" ],
      [ /\A278 Transaction\b/, "oge_278t" ]
    ].freeze
    ERROR_PREFIX = "錯誤："
    PDF_LINK = %r{href='(?<url>[^']*/(?<unid>[0-9A-F]{32})/\$FILE/[^']+)'>(?<label>[^<]+)</a>}i

    def initialize(fetcher: HouseIndexFetcher.new)
      @fetcher = fetcher
    end

    # 回傳本次的 SyncRun。
    def call
      run      = SyncRun.create!(source: SOURCE, kind: "index", started_at: Time.current)
      previous = previous_validators
      gate     = @fetcher.fetch(GATE_URL, previous[GATE_URL])
      return finish(run, validators: previous, new_count: 0, log: []) if gate.not_modified?

      rows, log = collect(Official.where(source: SOURCE, active: true).order(:id).to_a)
      # 有人查詢失敗時保留舊 validators：下一次關卡不會回 304，失敗的人一定會重查（Q1 r1 問題 1）。
      validators = log.any? { |l| l.start_with?(ERROR_PREFIX) } ? previous : { GATE_URL => gate.validators }
      finish(run, validators: validators, new_count: insert_filings(rows), log: log)
    rescue StandardError => e
      run&.update!(finished_at: Time.current, error_count: run.error_count + 1,
                   error_log: [ run.error_log, "#{e.class}: #{e.message}" ].compact.join("\n"),
                   http_validators: previous || {})
      raise
    end

    private

    def previous_validators
      SyncRun.where(source: SOURCE, kind: "index").where.not(finished_at: nil)
             .order(started_at: :desc).limit(1).pick(:http_validators) || {}
    end

    # 回傳 [filing 列, 錯誤與警示行]。單一人物查詢失敗只記錄，不影響其他人。
    def collect(officials)
      log = []
      rows = officials.flat_map do |official|
        records = search(official.last_name).select { |r| match?(r["name"], official) }
        records.filter_map { |r| filing_row(official, r, log) }
      rescue HouseIndexFetcher::Error, JSON::ParserError => e
        log << "#{ERROR_PREFIX}#{official.slug} 查詢失敗：#{e.message}"
        []
      end
      [ rows, log ]
    end

    def search(last_name)
      records = []
      loop do
        page = JSON.parse(@fetcher.fetch(api_url(last_name, records.size)).body)
        batch = Array(page["data"])
        records.concat(batch)
        break if batch.empty? || records.size >= page["recordsFiltered"].to_i
      end
      records
    end

    def api_url(last_name, start)
      "#{API_URL}?#{URI.encode_www_form('draw' => 1, 'start' => start, 'length' => PAGE_SIZE, 'search[value]' => last_name)}"
    end

    def match?(name, official)
      last, first = name.to_s.split(",", 2).map(&:strip)
      last.to_s.casecmp?(official.last_name) && first.to_s.downcase.start_with?(official.first_name.downcase)
    end

    def filing_row(official, record, log)
      link  = record["type"].to_s.match(PDF_LINK)
      label = link ? link[:label] : record["type"].to_s.sub(/\s*\(?<a .*\z/m, "").strip
      type  = FILING_TYPES.find { |re, _| label.match?(re) }&.last
      return nil unless type

      date = parse_date(record["docDate"])
      unless link
        log << "警示：#{official.slug} #{label}（#{date}）沒有線上 PDF，需書面申請，未寫入"
        return nil
      end

      { official_id: official.id, source: SOURCE, doc_id: link[:unid].upcase, filing_type: type,
        year: label[/\((\d{4})\)/, 1]&.to_i || date&.year, filing_date: date, pdf_url: link[:url] }
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def insert_filings(rows)
      return 0 if rows.empty?

      Filing.insert_all(rows.uniq { |r| r[:doc_id] }, unique_by: %i[source doc_id], returning: %i[id]).length
    end

    def finish(run, validators:, new_count:, log:)
      run.update!(finished_at: Time.current, new_filings_count: new_count,
                  error_count: log.count { |l| l.start_with?(ERROR_PREFIX) },
                  error_log: log.join("\n").presence, http_validators: validators)
      run
    end
  end
end
