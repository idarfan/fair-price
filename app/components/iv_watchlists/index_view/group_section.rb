# frozen_string_literal: true

class IvWatchlists::IndexView::GroupSection < ApplicationComponent
  def initialize(group_tag:, items:)
    @group_tag = group_tag
    @items     = items
  end

  def view_template
    div(class: "bg-gray-900 border border-gray-700 rounded-xl overflow-hidden") do
      div(class: "flex items-center gap-3 px-5 py-3 border-b border-gray-700") do
        span(
          class: "text-xs font-medium px-2 py-0.5 rounded border #{IvWatchlists::IndexView::GROUP_COLORS.fetch(@group_tag, IvWatchlists::IndexView::GROUP_COLORS['general'])}"
        ) { @group_tag.upcase }
        span(class: "text-gray-400 text-sm") { "#{@items.size} 個標的" }
      end
      div(class: "divide-y divide-gray-800") do
        @items.each { |item| render IvWatchlists::IndexView::SymbolRow.new(item:) }
      end
    end
  end
end

