# frozen_string_literal: true

class DailyMomentum::NewsCardComponent < ApplicationComponent
  # @param headline [String]      Article headline
  # @param source   [String, nil] Source name
  # @param url      [String, nil] Article URL
  # @param datetime [String, nil] Published datetime string
  def initialize(headline:, source: nil, url: nil, datetime: nil)
    @headline = headline
    @source   = source
    @url      = url
    @datetime = datetime
  end

  def view_template
    div(class: "py-3 border-b border-gray-100 last:border-0") do
      if @url.present?
        a(href: @url, target: "_blank", rel: "noopener noreferrer",
          class: "text-sm text-gray-800 hover:text-blue-600 font-medium leading-snug line-clamp-2 block") do
          plain(@headline)
        end
      else
        p(class: "text-sm text-gray-800 font-medium leading-snug line-clamp-2") { plain(@headline) }
      end
      div(class: "flex items-center gap-2 mt-1") do
        span(class: "text-xs text-gray-400") { plain(@source) } if @source
        span(class: "text-xs text-gray-300") { plain("·") } if @source && @datetime
        span(class: "text-xs text-gray-400") { plain(@datetime) } if @datetime
      end
    end
  end
end
