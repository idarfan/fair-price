# frozen_string_literal: true

module ApplicationHelper
  def risk_level(vix)
    return :medium if vix.nil?

    if    vix < 16  then :low
    elsif vix <= 22 then :medium
    else                 :high
    end
  end

  def max_position_note(vix)
    return "5% 單筆上限" if vix.nil?

    if    vix < 16  then "10% 單筆上限"
    elsif vix <= 22 then "5% 單筆上限"
    else                 "2% 單筆上限，建議空倉觀望"
    end
  end
end
