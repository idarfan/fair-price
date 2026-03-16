# frozen_string_literal: true

# @label Time Segment Badge
class DailyMomentum::TimeSegmentBadgeComponentPreview < Lookbook::Preview
  # @label 盤前
  def pre_market
    render DailyMomentum::TimeSegmentBadgeComponent.new(segment: :pre_market, et_time: "08:45")
  end

  # @label 盤中
  def market_hours
    render DailyMomentum::TimeSegmentBadgeComponent.new(segment: :market_hours, et_time: "10:30")
  end

  # @label 盤後
  def after_hours
    render DailyMomentum::TimeSegmentBadgeComponent.new(segment: :after_hours, et_time: "17:15")
  end

  # @label 休市
  def closed
    render DailyMomentum::TimeSegmentBadgeComponent.new(segment: :closed, et_time: "02:00")
  end
end
