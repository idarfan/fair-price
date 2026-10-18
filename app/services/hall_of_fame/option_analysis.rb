# frozen_string_literal: true

module HallOfFame
  # P3b：期權列解析＋口數／權利金反推，寫入 hof_option_details（數值一律區間）。
  # - 對象：期權列中尚未有 option_detail，或 premium_ref 仍為 NULL 的列（CDP 離線待重試、履約、無法解析）。
  # - 批次開始前預檢一次 CDP（CdpPrecheckable，唯讀引用）；離線時不開 Barchart、不走 bs_model，
  #   需要參考價的列維持 needs_review，error_log 寫 CDP_OFFLINE_MESSAGE 原文。
  # - 期權造成的 needs_review 原因以「[期權] 」開頭寫進 filing.parse_error，每次重算時整批替換，
  #   不動 PDF 解析留下的其他原因。
  class OptionAnalysis
    include CdpPrecheckable

    SOURCE        = HouseIndexSync::SOURCE
    REASON_PREFIX = "[期權] "
    OPTION_SQL    = "hof_transactions.asset_type_code = 'OP' OR hof_transactions.description ~* '\\m(call|put) options?\\M'"

    def initialize(parser: OptionDescriptionParser.new, reference: PremiumReference.new)
      @parser    = parser
      @reference = reference
    end

    def call
      run    = SyncRun.create!(source: SOURCE, kind: "options", started_at: Time.current)
      online = cdp_online?
      reasons = Hash.new { |h, k| h[k] = [] }
      candidates.each do |trade|
        attrs, reason = analyze(trade, online)
        save_detail(trade, attrs)
        reasons[trade.filing] << "#{REASON_PREFIX}#{trade.asset_name}（#{trade.tx_date}）：#{reason}" if reason
        reasons[trade.filing] # 沒有原因也要登記，才會清掉上次留下的期權原因
      end
      reasons.each { |filing, lines| update_filing(filing, lines) }
      finish(run, online, reasons)
    rescue StandardError => e
      # 同 HouseIndexSync：留下 finished_at 與例外訊息，不讓排程留下沒結束的 run。
      run&.update!(finished_at: Time.current, error_count: run.error_count + 1,
                   error_log: [ run.error_log, "#{e.class}: #{e.message}" ].compact.join("\n"))
      raise
    end

    private

    def candidates
      Trade.joins(:filing).where(hof_filings: { source: SOURCE }).where(OPTION_SQL)
           .eager_load(:option_detail)
           .where(hof_option_details: { premium_ref: nil })
           .includes(:filing).order(:id)
    end

    # 回傳 [option_detail 屬性, needs_review 原因或 nil]。
    def analyze(trade, online)
      parsed = @parser.parse(trade.description)
      return [ { calc_note: "期權描述無法解析：#{trade.description.inspect}" }, "期權描述無法解析" ] unless parsed

      base = { option_right: parsed.option_right, strike: parsed.strike, expiration: parsed.expiration,
               contracts_stated: parsed.contracts_stated }
      return [ base.merge(calc_note: "履約交易：金額為取得股票的價值，不反推權利金（#{parsed.pattern}）"), nil ] if parsed.exercise?
      return [ base.merge(calc_note: "缺 ticker 或金額下限，無法反推"), "缺 ticker 或金額下限" ] if trade.ticker.blank? || trade.amount_min.nil?

      ref = @reference.resolve(ticker: trade.ticker, parsed:, tx_date: trade.tx_date, cdp_online: online)
      parsed.contracts_stated ? stated(trade, parsed, base, ref) : estimated(trade, base, ref)
    end

    # A：申報口數 → 每股權利金區間；參考價只做交叉檢查，不改數值。
    def stated(trade, parsed, base, ref)
      shares = parsed.contracts_stated * 100
      low    = (trade.amount_min.to_d / shares).round(4)
      high   = trade.amount_max && (trade.amount_max.to_d / shares).round(4)
      note   = "申報 #{parsed.contracts_stated} 口；每股權利金 = 金額區間 ÷ (#{parsed.contracts_stated} × 100) = #{low}～#{high || '無上限'}"
      attrs  = base.merge(premium_source: "stated_contracts", premium_implied_min: low, premium_implied_max: high)
      return [ attrs.merge(calc_note: "#{note}。交叉檢查：#{ref.note}"), ref.note ] unless ref.ok?

      outside = ref.value < low || (high && ref.value > high)
      check   = "交叉檢查參考價（#{ref.source}）#{ref.value.round(4)}#{outside ? '，申報口數與市價不符' : '，落在區間內'}"
      [ attrs.merge(premium_ref: ref.value, underlying_close: ref.underlying, calc_note: "#{note}。#{check}。#{ref.note}"), nil ]
    end

    # B：未申報口數 → 以參考價反推口數區間（下限無條件進位、上限無條件捨去）。
    def estimated(trade, base, ref)
      return [ base.merge(calc_note: ref.note), ref.note ] unless ref.ok?

      per_contract = ref.value * 100
      low  = (trade.amount_min.to_d / per_contract).ceil
      high = trade.amount_max && (trade.amount_max.to_d / per_contract).floor
      note = "口數 = 金額區間 ÷ (#{ref.value.round(4)} × 100) = #{low}～#{high || '無上限'}。#{ref.note}"
      [ base.merge(premium_source: ref.source, premium_ref: ref.value, underlying_close: ref.underlying,
                   contracts_est_min: low, contracts_est_max: high, calc_note: note), nil ]
    end

    def save_detail(trade, attrs)
      detail = trade.option_detail || trade.build_option_detail
      detail.assign_attributes(OptionDetail.column_names.excluding("id", "transaction_id", "created_at", "updated_at")
                                           .index_with(nil).merge(attrs.stringify_keys))
      detail.save!
    end

    def update_filing(filing, option_lines)
      kept  = filing.parse_error.to_s.lines(chomp: true).reject { |l| l.start_with?(REASON_PREFIX) }
      lines = kept + option_lines
      filing.update!(parse_status: lines.any? ? "needs_review" : "parsed", parse_error: lines.join("\n").presence)
    end

    def finish(run, online, reasons)
      log = reasons.values.flatten
      log.unshift(CDP_OFFLINE_MESSAGE) unless online
      run.update!(finished_at: Time.current, error_count: log.size, error_log: log.join("\n").presence)
      run
    end
  end
end
