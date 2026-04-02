# frozen_string_literal: true

# Firstrade margin interest calculation service.
# RATE_TIERS must stay in sync with app/frontend/margin/utils/interestCalc.ts
class MarginInterestService
  RATE_TIERS = [
    { min: 1_000_000, rate: 0.08 },
    { min:   500_000, rate: 0.086 },
    { min:   250_000, rate: 0.105 },
    { min:   100_000, rate: 0.1075 },
    { min:    25_000, rate: 0.1125 },
    { min:    10_000, rate: 0.1175 },
    { min:         0, rate: 0.12 }
  ].freeze

  def self.rate_for(balance)
    tier = RATE_TIERS.find { |t| balance >= t[:min] }
    tier ? tier[:rate] : 0.12
  end

  # Returns accrued interest from opened_on to today (or closed_on if closed)
  def self.accrued_interest(position)
    days = days_held(position)
    balance = position.balance
    rate = rate_for(balance)
    (balance * rate * days / 360.0).round(2)
  end

  # Day 15 = opened_on + 14; subsequent: +30 each
  def self.first_charge_date(position)
    position.opened_on + 14
  end

  def self.next_charge_date(position)
    first = first_charge_date(position)
    today = Date.current
    return first if first > today

    # Find the smallest first + 30k > today
    k = ((today - first).to_i / 30) + 1
    first + (k * 30)
  end

  # Interest for the current 30-day period only
  def self.current_period_interest(position)
    balance = position.balance
    rate = rate_for(balance)
    first = first_charge_date(position)
    today = Date.current

    period_days = if today < first
                    (today - position.opened_on).to_i
    else
                    k = ((today - first).to_i / 30)
                    period_start = first + (k * 30)
                    (today - period_start).to_i
    end

    (balance * rate * period_days / 360.0).round(2)
  end

  def self.days_held(position)
    end_date = position.closed_on || Date.current
    (end_date - position.opened_on).to_i
  end

  def self.decorate(position)
    balance = position.balance
    rate    = rate_for(balance)
    days    = days_held(position)

    {
      id:                       position.id,
      symbol:                   position.symbol,
      buy_price:                position.buy_price,
      shares:                   position.shares,
      sell_price:               position.sell_price,
      opened_on:                position.opened_on,
      closed_on:                position.closed_on,
      status:                   position.status,
      balance:                  balance.round(2),
      annual_rate:              rate,
      days_held:                days,
      accrued_interest:         accrued_interest(position),
      next_charge_date:         next_charge_date(position),
      current_period_interest:  current_period_interest(position)
    }
  end
end
