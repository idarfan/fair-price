# frozen_string_literal: true

# Reads today's Barchart scrape results from DB and computes three INDEPENDENT scores.
# Never merges them into a single composite number — divergences are the key insight.
class CompositeSignalService
  SCORE_LABELS = {
    bullish:  "偏多",
    neutral:  "中性",
    bearish:  "偏空",
    watching: "觀察中"
  }.freeze

  def initialize(symbol, date: Date.today)
    @symbol = symbol.upcase
    @today  = date
  end

  def call
    tech = TechnicalAnalysis.find_by(symbol: @symbol, snapshot_date: @today)
    fund = Fundamental.find_by(symbol: @symbol, snapshot_date: @today)
    flow = OptionsFlow.find_by(symbol: @symbol, snapshot_date: @today)
    mp   = MaxPainSnapshot.find_by(symbol: @symbol, snapshot_date: @today)

    ts = technical_score(tech)
    fs = fundamental_score(fund)
    os = options_flow_score(flow)

    {
      symbol:       @symbol,
      technical:    ts,
      fundamental:  fs,
      options_flow: os,
      divergences:  compute_divergences(ts, fs, os, fund),
      max_pain:     max_pain_data(mp),
      fetched_at:   [ tech&.fetched_at, fund&.fetched_at, flow&.fetched_at, mp&.fetched_at ].compact.max
    }
  end

  private

  # ---------------------------------------------------------------------------
  # Technical score: MA alignment, ADX+DI, Stochastic
  # ---------------------------------------------------------------------------
  def technical_score(tech)
    return { score: :neutral, signals: [], missing: true } unless tech

    signals = []
    points  = 0

    # MA position — ma_pct_chg_Xd > 0 means price is ABOVE the X-day MA
    {
      "20日均線" => [ tech.ma_pct_chg_20d,  1 ],
      "50日均線" => [ tech.ma_pct_chg_50d,  1 ],
      "200日均線" => [ tech.ma_pct_chg_200d, 2 ]
    }.each do |label, (pct, weight)|
      next unless pct
      if pct > 0
        points += weight
        signals << { text: "股價高於#{label} (+#{pct.round(2)}%)", sentiment: :bullish }
      else
        points -= weight
        signals << { text: "股價低於#{label} (#{pct.round(2)}%)", sentiment: :bearish }
      end
    end

    # ADX + DI direction (14d)
    adx      = tech.adx_14d
    di_plus  = tech.di_plus_14d
    di_minus = tech.di_minus_14d
    if adx && di_plus && di_minus
      if adx > 25
        if di_plus > di_minus
          points += 2
          signals << { text: "ADX #{adx.round(1)}（趨勢強），+DI#{di_plus.round(1)} > -DI#{di_minus.round(1)}（多頭）", sentiment: :bullish }
        else
          points -= 2
          signals << { text: "ADX #{adx.round(1)}（趨勢強），-DI#{di_minus.round(1)} > +DI#{di_plus.round(1)}（空頭）", sentiment: :bearish }
        end
      elsif adx > 20
        signals << { text: "ADX #{adx.round(1)}（趨勢中等，方向待確認）", sentiment: :neutral }
      else
        signals << { text: "ADX #{adx.round(1)}（盤整，趨勢不明）", sentiment: :neutral }
      end
    end

    # Stochastic 14d
    stoch_k = tech.stoch_k_14d
    if stoch_k
      if stoch_k > 80
        points -= 1
        signals << { text: "Stochastic %K #{stoch_k.round(1)}（超買）", sentiment: :bearish }
      elsif stoch_k < 20
        points += 1
        signals << { text: "Stochastic %K #{stoch_k.round(1)}（超賣，可能反彈）", sentiment: :bullish }
      else
        signals << { text: "Stochastic %K #{stoch_k.round(1)}（中性）", sentiment: :neutral }
      end
    end

    score = if points >= 4
              :bullish
    elsif points <= -3
              :bearish
    else
              :neutral
    end

    { score: score, signals: signals, points: points }
  end

  # ---------------------------------------------------------------------------
  # Fundamental score: analyst consensus, EPS, PE, pre-earnings flag
  # ---------------------------------------------------------------------------
  def fundamental_score(fund)
    return { score: :neutral, signals: [], missing: true } unless fund

    signals = []

    # Pre-earnings: override all other signals → :watching
    if fund.next_earnings_date && fund.pre_earnings?
      days = fund.days_to_earnings
      signals << {
        text:      "財報即將於 #{fund.next_earnings_date}（#{fund.earnings_time}）公布，#{days} 天後",
        sentiment: :watching
      }
      return { score: :watching, signals: signals }
    end

    points = 0

    # Analyst consensus
    strong_buy    = fund.analyst_strong_buy    || 0
    moderate_buy  = fund.analyst_moderate_buy  || 0
    hold          = fund.analyst_hold          || 0
    sell          = fund.analyst_sell          || 0
    total_bull    = strong_buy + moderate_buy
    total         = total_bull + hold + sell

    if total > 0
      ratio = total_bull.to_f / total
      label = "分析師 #{total_bull}/#{total} 看多 (#{(ratio * 100).round}%)"
      if ratio > 0.7
        points += 2
        signals << { text: label, sentiment: :bullish }
      elsif ratio > 0.5
        points += 1
        signals << { text: label, sentiment: :bullish }
      elsif ratio < 0.3
        points -= 2
        signals << { text: label, sentiment: :bearish }
      else
        signals << { text: label, sentiment: :neutral }
      end
    end

    # EPS profitability
    if fund.eps_ttm
      if fund.eps_ttm > 0
        points += 1
        signals << { text: "EPS(TTM) $#{fund.eps_ttm.round(2)}（盈利中）", sentiment: :bullish }
      else
        points -= 2
        signals << { text: "EPS(TTM) $#{fund.eps_ttm.round(2)}（虧損）", sentiment: :bearish }
      end
    end

    # PE ratio
    if fund.pe_ttm
      if fund.pe_ttm > 0 && fund.pe_ttm < 20
        points += 1
        signals << { text: "P/E #{fund.pe_ttm.round(1)}（估值合理）", sentiment: :bullish }
      elsif fund.pe_ttm > 40
        points -= 1
        signals << { text: "P/E #{fund.pe_ttm.round(1)}（估值偏高）", sentiment: :bearish }
      elsif fund.pe_ttm > 0
        signals << { text: "P/E #{fund.pe_ttm.round(1)}（估值中等）", sentiment: :neutral }
      end
    end

    # Next earnings (not pre-earnings, just informational)
    if fund.next_earnings_date
      signals << {
        text:      "下次財報：#{fund.next_earnings_date}（#{fund.earnings_time}）",
        sentiment: :neutral
      }
    end

    score = if points >= 3
              :bullish
    elsif points <= -2
              :bearish
    else
              :neutral
    end

    { score: score, signals: signals, points: points }
  end

  # ---------------------------------------------------------------------------
  # Options Flow score: Net Trade Sentiment + Delta Imbalance + detailed metrics
  # ---------------------------------------------------------------------------
  def options_flow_score(flow)
    return { score: :neutral, signals: [], missing: true } unless flow

    signals = []
    points  = 0

    net   = flow.net_sentiment
    delta = flow.delta_imbalance

    if net
      amt = "$#{sprintf("%.1f", net.abs / 1_000_000.0)}M"
      if net > 0
        points += 1
        signals << { text: "淨交易情緒 +#{amt}（買方主導）", sentiment: :bullish }
      else
        points -= 1
        signals << { text: "淨交易情緒 -#{amt}（賣方主導）", sentiment: :bearish }
      end
    end

    if delta
      if delta > 0
        points += 1
        signals << { text: "Delta Imbalance +#{delta.abs.to_i}（買權 Delta 過剩）", sentiment: :bullish }
      else
        points -= 1
        signals << { text: "Delta Imbalance #{delta.to_i}（賣權 Delta 過剩）", sentiment: :bearish }
      end
    end

    # Ask-side C/P ratio (directional — excludes bid/mid noise)
    ask_ratio = flow.ask_call_put_ratio&.to_f
    ask_call  = flow.ask_call_premium&.to_i || 0
    ask_put   = flow.ask_put_premium&.to_i  || 0
    if ask_ratio
      if ask_ratio >= 2.0
        points += 2
        signals << { text: "主動買 C/P #{sprintf("%.2f", ask_ratio)}（Ask-side Call $#{sprintf("%.1f", ask_call / 1_000_000.0)}M 強力主導）", sentiment: :bullish }
      elsif ask_ratio >= 1.5
        points += 1
        signals << { text: "主動買 C/P #{sprintf("%.2f", ask_ratio)}（Ask-side 偏多）", sentiment: :bullish }
      elsif ask_ratio <= 0.5
        points -= 2
        signals << { text: "主動買 C/P #{sprintf("%.2f", ask_ratio)}（Ask-side Put 強力主導）", sentiment: :bearish }
      elsif ask_ratio <= 0.67
        points -= 1
        signals << { text: "主動買 C/P #{sprintf("%.2f", ask_ratio)}（Ask-side 偏空）", sentiment: :bearish }
      else
        signals << { text: "主動買 C/P #{sprintf("%.2f", ask_ratio)}（Ask-side 中性）", sentiment: :neutral }
      end
    end

    # Large orders (premium >= $500K)
    large_call = flow.large_call_count || 0
    large_put  = flow.large_put_count  || 0
    if large_call > 0 || large_put > 0
      if large_call > large_put
        points += 1
        signals << { text: "機構大單 Call #{large_call} 筆 vs Put #{large_put} 筆（≥$500K）", sentiment: :bullish }
      elsif large_put > large_call
        points -= 1
        signals << { text: "機構大單 Put #{large_put} 筆 vs Call #{large_call} 筆（≥$500K）", sentiment: :bearish }
      else
        signals << { text: "機構大單 Call #{large_call} = Put #{large_put} 筆（方向均衡）", sentiment: :neutral }
      end
    end

    # High-delta call (ask-side, delta >= 0.70) — strong directional conviction
    high_delta = flow.high_delta_call_count || 0
    if high_delta >= 2
      points += 1
      signals << { text: "高 Delta Call（≥0.70）#{high_delta} 筆主動買入（強確信方向押注）", sentiment: :bullish }
    elsif high_delta == 1
      signals << { text: "高 Delta Call（≥0.70）#{high_delta} 筆主動買入", sentiment: :bullish }
    end

    # Long DTE institutional vs short DTE hedging
    long_dte_prem  = flow.long_dte_call_premium&.to_i || 0
    short_dte_prem = flow.short_dte_put_premium&.to_i || 0
    if long_dte_prem >= 500_000
      signals << { text: "長 DTE Call（>180天）$#{sprintf("%.1f", long_dte_prem / 1_000_000.0)}M（機構長線佈局）", sentiment: :bullish }
    end
    if short_dte_prem >= 500_000
      signals << { text: "短 DTE Put（<30天）$#{sprintf("%.1f", short_dte_prem / 1_000_000.0)}M（短線對沖壓力）", sentiment: :bearish }
    end

    score = if points >= 2
              :bullish
    elsif points <= -2
              :bearish
    else
              :neutral
    end

    { score:              score,
      signals:            signals,
      points:             points,
      call_premium_total: flow.call_premium_total,
      put_premium_total:  flow.put_premium_total,
      call_put_ratio:     flow.call_put_ratio&.to_f,
      ask_call_put_ratio: ask_ratio,
      large_call_count:   large_call,
      large_put_count:    large_put,
      ask_call_premium:   ask_call,
      ask_put_premium:    ask_put,
      high_delta_call:    high_delta,
      long_dte_call_prem: long_dte_prem,
      short_dte_put_prem: short_dte_prem,
      top_large_orders:   Array(flow.top_large_orders),
      total_trades:       flow.total_trades_loaded }
  end

  # ---------------------------------------------------------------------------
  # Divergence analysis
  # ---------------------------------------------------------------------------
  def compute_divergences(ts, fs, os, fund)
    divs = []

    tech_score = ts[:score]
    fund_score = fs[:score]
    flow_score = os[:score]
    pre_earn   = fund&.pre_earnings?

    # Technical vs Options Flow
    if opposite?(tech_score, flow_score)
      if tech_score == :bullish && flow_score == :bearish
        msg = pre_earn \
          ? "財報前 Options Flow 偏空，技術面偏多 — 機構可能用 Put 避險而非方向性押注，不宜追多" \
          : "Options Flow 偏空但技術面偏多 — 機構可能在做對沖，請謹慎追多"
        divs << { level: :warning, message: msg }
      else
        divs << { level: :caution, message: "Options Flow 偏多但技術面偏空 — 期權情緒未獲技術面確認，宜觀望" }
      end
    end

    # Technical vs Fundamental
    if opposite?(tech_score, fund_score)
      if tech_score == :bullish && fund_score == :bearish
        divs << { level: :caution, message: "技術面偏多但基本面偏空 — 短線動能強，但估值與獲利能力仍有疑慮" }
      else
        divs << { level: :caution, message: "基本面偏多但技術面偏空 — 價值股可能仍在下跌趨勢，等待技術面確認" }
      end
    end

    # All aligned
    active_scores = [ tech_score, fund_score, flow_score ].reject { |s| s == :watching }
    if active_scores.length >= 2
      if active_scores.all? { |s| s == :bullish }
        divs << { level: :confirm_bull, message: "三維度一致看多 — 訊號高度對齊，注意短期是否已過熱" }
      elsif active_scores.all? { |s| s == :bearish }
        divs << { level: :confirm_bear, message: "三維度一致看空 — 訊號高度對齊，短中長期均承壓" }
      end
    end

    divs
  end

  def opposite?(a, b)
    return false if [ :neutral, :watching ].include?(a) || [ :neutral, :watching ].include?(b)
    (a == :bullish) != (b == :bullish)
  end

  def max_pain_data(mp)
    return nil unless mp

    {
      expiration:         mp.expiration,
      dte:                mp.dte,
      last_price:         mp.last_price&.to_f,
      max_pain_strike:    mp.max_pain_strike&.to_f,
      strikes:            mp.strikes,
      call_pain:          mp.call_pain,
      put_pain:           mp.put_pain,
      call_oi:            mp.call_oi,
      put_oi:             mp.put_oi,
      iv_combined:        mp.iv_combined,
      max_pain_by_expiry: mp.max_pain_by_expiry
    }
  end
end
