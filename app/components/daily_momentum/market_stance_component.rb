# frozen_string_literal: true

class DailyMomentum::MarketStanceComponent < ApplicationComponent
  # @param vix   [Float, nil]  Current VIX value
  # @param es    [Float, nil]  ES futures change %
  # @param nq    [Float, nil]  NQ futures change %
  # @param stance [Symbol]    :aggressive, :conservative, :cash
  def initialize(vix: nil, es: nil, nq: nil, stance: nil)
    @vix    = vix
    @es     = es
    @nq     = nq
    @stance = stance || derive_stance(vix)
  end

  def view_template
    info = stance_info
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm p-5") do
      div(class: "flex items-start justify-between gap-4") do
        div do
          p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1") { plain("🐱 歐歐立場") }
          div(class: "flex items-center gap-2") do
            span(class: "text-2xl") { plain(info[:emoji]) }
            span(class: "text-xl font-bold #{info[:color]}") { plain(info[:label]) }
          end
          p(class: "text-sm text-gray-500 mt-1") { plain(info[:desc]) }
        end
        div(class: "flex gap-3 flex-shrink-0") do
          render_metric("VIX", @vix, :number)
          render_metric("ES", @es, :percent_change)
          render_metric("NQ", @nq, :percent_change)
        end
      end
    end
  end

  private

  def derive_stance(vix)
    return :cash if vix.nil?

    if    vix < MomentumThresholds::VIX_AGGRESSIVE_MAX   then :aggressive
    elsif vix <= MomentumThresholds::VIX_CONSERVATIVE_MAX then :conservative
    else                                                        :cash
    end
  end

  def stance_info
    case @stance
    when :aggressive
      { emoji: "🟢", label: "激進買入", color: "text-green-600",
        desc: "市場情緒樂觀，低波動適合進場" }
    when :conservative
      { emoji: "🟡", label: "保守買入", color: "text-yellow-600",
        desc: "中性波動，謹慎選股分批進場" }
    else
      { emoji: "🔴", label: "持幣觀望", color: "text-red-600",
        desc: "高波動市場，建議保留現金等待機會" }
    end
  end

  def render_metric(label, value, type)
    div(class: "text-center") do
      p(class: "text-xs text-gray-400 font-medium") { plain(label) }
      if value.nil?
        span(class: "text-sm font-bold text-gray-400") { plain("—") }
      elsif type == :percent_change
        sign  = value >= 0 ? "+" : ""
        color = change_color(value)
        span(class: "text-sm font-bold #{color}") { plain("#{sign}#{sprintf("%.2f", value)}%") }
      else
        span(class: "text-sm font-bold text-gray-900") { plain(sprintf("%.2f", value)) }
      end
    end
  end
end
