# frozen_string_literal: true

module ApplicationHelper
  include MomentumThresholds

  def risk_level(vix)
    return :medium if vix.nil?

    if    vix < VIX_AGGRESSIVE_MAX   then :low
    elsif vix <= VIX_CONSERVATIVE_MAX then :medium
    else                                   :high
    end
  end

  def max_position_note(vix)
    return "5% 單筆上限" if vix.nil?

    if    vix < VIX_AGGRESSIVE_MAX   then "10% 單筆上限"
    elsif vix <= VIX_CONSERVATIVE_MAX then "5% 單筆上限"
    else                                   "2% 單筆上限，建議空倉觀望"
    end
  end
end
