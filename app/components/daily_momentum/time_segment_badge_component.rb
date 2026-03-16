# frozen_string_literal: true

class DailyMomentum::TimeSegmentBadgeComponent < ApplicationComponent
  SEGMENTS = {
    pre_market:   { label: "盤前",   emoji: "📊", color: "bg-yellow-100 text-yellow-700 border-yellow-200" },
    market_hours: { label: "盤中",   emoji: "🔔", color: "bg-green-100 text-green-700 border-green-200" },
    after_hours:  { label: "盤後",   emoji: "🌆", color: "bg-orange-100 text-orange-700 border-orange-200" },
    closed:       { label: "休市",   emoji: "🌙", color: "bg-gray-100 text-gray-600 border-gray-200" }
  }.freeze

  # @param segment [Symbol] :pre_market, :market_hours, :after_hours, :closed
  # @param et_time [String] Eastern Time string shown alongside
  def initialize(segment:, et_time: nil)
    @segment = segment
    @et_time = et_time
  end

  def view_template
    info = SEGMENTS.fetch(@segment, SEGMENTS[:closed])
    div(class: "inline-flex items-center gap-1.5 px-3 py-1 rounded-full border text-sm font-medium #{info[:color]}") do
      span { plain(info[:emoji]) }
      span { plain(info[:label]) }
      if @et_time
        span(class: "opacity-60 text-xs font-normal") { plain("ET #{@et_time}") }
      end
    end
  end
end
