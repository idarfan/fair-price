# frozen_string_literal: true

class DailyMomentum::RiskAlertComponent < ApplicationComponent
  LEVELS = {
    low:    { label: "低波動",   color: "bg-green-50 border-green-200",  badge: "bg-green-100 text-green-700",  emoji: "🟢" },
    medium: { label: "中波動",   color: "bg-yellow-50 border-yellow-200", badge: "bg-yellow-100 text-yellow-700", emoji: "🟡" },
    high:   { label: "高波動",   color: "bg-red-50 border-red-200",      badge: "bg-red-100 text-red-700",      emoji: "🔴" }
  }.freeze

  # @param vix          [Float, nil]   Current VIX
  # @param level        [Symbol]       :low, :medium, :high
  # @param earnings     [Array<Hash>]  Upcoming earnings [{symbol:, date:}]
  # @param max_position [String, nil]  Max position size recommendation
  def initialize(vix: nil, level: :medium, earnings: [], max_position: nil)
    @vix          = vix
    @level        = level
    @earnings     = earnings
    @max_position = max_position
  end

  def view_template
    info = LEVELS.fetch(@level, LEVELS[:medium])
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm p-5") do
      div(class: "flex items-center gap-2 mb-4") do
        span(class: "text-lg") { plain("⚠️") }
        h2(class: "font-semibold text-gray-900") { plain("風險提示") }
        span(class: "ml-auto text-xs font-medium px-2 py-1 rounded-full #{info[:badge]}") do
          plain("#{info[:emoji]} #{info[:label]}")
        end
      end

      div(class: "grid grid-cols-1 gap-3") do
        render_vix_row(info)
        render_earnings_row unless @earnings.empty?
        render_position_row if @max_position
      end
    end
  end

  private

  def render_vix_row(info)
    div(class: "flex items-center gap-3 p-3 rounded-lg #{info[:color]} border") do
      span(class: "text-sm font-medium text-gray-700 w-20 flex-shrink-0") { plain("VIX 指數") }
      span(class: "text-sm font-bold text-gray-900") { plain(@vix ? sprintf("%.2f", @vix) : "—") }
      span(class: "text-xs text-gray-500 ml-auto") { plain(vix_note) }
    end
  end

  def render_earnings_row
    div(class: "p-3 rounded-lg bg-orange-50 border border-orange-200") do
      p(class: "text-sm font-medium text-gray-700 mb-1.5") { plain("📅 本週財報雷區") }
      div(class: "flex flex-wrap gap-1.5") do
        @earnings.each do |e|
          span(class: "text-xs bg-orange-100 text-orange-700 px-2 py-0.5 rounded font-mono") do
            plain("#{e[:symbol]} #{e[:date]}")
          end
        end
      end
    end
  end

  def render_position_row
    div(class: "flex items-center gap-3 p-3 rounded-lg bg-blue-50 border border-blue-200") do
      span(class: "text-sm font-medium text-gray-700 w-20 flex-shrink-0") { plain("最大倉位") }
      span(class: "text-sm font-bold text-blue-700") { plain(@max_position) }
    end
  end

  def vix_note
    return "無資料" if @vix.nil?

    if    @vix < MomentumThresholds::VIX_AGGRESSIVE_MAX   then "市場平靜，可積極操作"
    elsif @vix <= MomentumThresholds::VIX_CONSERVATIVE_MAX then "中度波動，謹慎為宜"
    else                                                         "高度恐慌，建議觀望"
    end
  end
end
