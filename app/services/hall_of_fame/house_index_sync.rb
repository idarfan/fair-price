# frozen_string_literal: true

module HallOfFame
  # P2：同步 House 年度索引（當年＋前一年）進 hof_filings。
  # - 下載前做條件式請求（§1-10），304 即跳過該年；validators 存在本次 hof_sync_runs。
  # - 比對規則：Last 完全相同＋First 前綴相同；StateDst 不同只記警示、不丟棄。
  # - 已存在的 (source, doc_id) 不重寫（ON CONFLICT DO NOTHING），new_filings_count 只算真正新增的列。
  class HouseIndexSync
    SOURCE   = "house"
    BASE_URL = "https://disclosures-clerk.house.gov/public_disc"
    FILING_TYPES = { "P" => "ptr", "O" => "annual", "A" => "amendment" }.freeze
    PDF_DIRS     = { "ptr" => "ptr-pdfs", "annual" => "financial-pdfs", "amendment" => "financial-pdfs" }.freeze

    YearResult = Data.define(:url, :validators, :new_count, :errors, :warnings)

    def self.zip_url(year) = "#{BASE_URL}/financial-pdfs/#{year}FD.zip"

    def self.pdf_url(filing_type, year, doc_id) = "#{BASE_URL}/#{PDF_DIRS.fetch(filing_type)}/#{year}/#{doc_id}.pdf"

    def initialize(years: nil, fetcher: HouseIndexFetcher.new, parser: HouseIndexParser.new)
      this_year = Time.zone.today.year
      @years    = years || [ this_year, this_year - 1 ]
      @fetcher  = fetcher
      @parser   = parser
    end

    # 回傳本次的 SyncRun。
    def call
      run       = SyncRun.create!(source: SOURCE, kind: "index", started_at: Time.current)
      previous  = previous_validators
      officials = Official.where(source: SOURCE, active: true).to_a
      results   = @years.map { |year| sync_year(year, previous, officials) }
      finish(run, results)
    rescue StandardError => e
      run&.update!(finished_at: Time.current, error_count: run.error_count + 1,
                   error_log: [ run.error_log, "#{e.class}: #{e.message}" ].compact.join("\n"),
                   http_validators: previous || {})
      raise
    end

    private

    # 每次 run 都會把 validators 帶到下一次，所以取最近一筆已結束的索引 run 即可（期權等其他 kind 不帶 validators）。
    def previous_validators
      SyncRun.where(source: SOURCE, kind: "index").where.not(finished_at: nil)
             .order(started_at: :desc).limit(1).pick(:http_validators) || {}
    end

    def sync_year(year, previous, officials)
      url    = self.class.zip_url(year)
      result = @fetcher.fetch(url, previous[url])
      return YearResult.new(url:, validators: result.validators, new_count: 0, errors: [], warnings: []) if result.not_modified?

      members  = @parser.parse(result.body, year)
      matched  = match_members(members, officials)
      inserted = insert_filings(matched.map(&:first))
      YearResult.new(url:, validators: result.validators, new_count: inserted, errors: [],
                     warnings: matched.flat_map(&:last) + skipped_warnings(members, officials))
    rescue HouseIndexFetcher::Error, HouseIndexParser::Error => e
      # 失敗時保留舊 validators：下次仍以條件式請求重試，內容有變就會重新下載。
      YearResult.new(url:, validators: previous[url], new_count: 0, errors: [ "#{year}：#{e.message}" ], warnings: [])
    end

    # 回傳 [[filing_row, warnings], ...]，只含名單內且 FilingType 可對映的列。
    def match_members(members, officials)
      members.filter_map do |member|
        official = find_official(member, officials)
        filing_type = FILING_TYPES[member.filing_type]
        next unless official && filing_type

        [ filing_row(member, official, filing_type), member_warnings(member, official) ]
      end
    end

    def find_official(member, officials)
      officials.find { |o| o.last_name == member.last && member.first.start_with?(o.first_name) }
    end

    def member_warnings(member, official)
      warnings = []
      if official.district.present? && member.state_dst != official.district
        warnings << "[警示] #{official.slug} DocID #{member.doc_id} StateDst=#{member.state_dst}，名單為 #{official.district}"
      end
      warnings << "[警示] #{official.slug} DocID #{member.doc_id} FilingDate 無法解析" if member.filing_date.nil?
      warnings
    end

    def skipped_warnings(members, officials)
      members.filter_map do |member|
        official = find_official(member, officials)
        next unless official && !FILING_TYPES.key?(member.filing_type)

        "[略過] #{official.slug} DocID #{member.doc_id} FilingType=#{member.filing_type}"
      end
    end

    def filing_row(member, official, filing_type)
      {
        official_id: official.id,
        source:      SOURCE,
        doc_id:      member.doc_id,
        filing_type: filing_type,
        year:        member.year,
        filing_date: member.filing_date,
        pdf_url:     self.class.pdf_url(filing_type, member.year, member.doc_id)
      }
    end

    def insert_filings(rows)
      return 0 if rows.empty?

      Filing.insert_all(rows, unique_by: %i[source doc_id], returning: %i[id]).length
    end

    def finish(run, results)
      errors   = results.flat_map(&:errors)
      warnings = results.flat_map(&:warnings)
      run.update!(
        finished_at:       Time.current,
        new_filings_count: results.sum(&:new_count),
        error_count:       errors.size,
        error_log:         (errors + warnings).join("\n").presence,
        http_validators:   results.to_h { |r| [ r.url, r.validators ] }.compact
      )
      run
    end
  end
end
