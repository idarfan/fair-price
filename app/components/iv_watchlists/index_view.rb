# frozen_string_literal: true

class IvWatchlists::IndexView < ApplicationComponent
  GROUP_COLORS = {
    "index"     => "bg-blue-500/10 text-blue-300 border-blue-500/30",
    "leveraged" => "bg-orange-500/10 text-orange-300 border-orange-500/30",
    "macro"     => "bg-purple-500/10 text-purple-300 border-purple-500/30",
    "general"   => "bg-gray-500/10 text-gray-300 border-gray-500/30"
  }.freeze

  def initialize(grouped:, new_item:)
    @grouped  = grouped
    @new_item = new_item
  end

  def view_template
    div(class: "px-4 py-6") do
      div(class: "mb-8") do
        h1(class: "text-2xl font-semibold text-gray-900") { "IV Skew 追蹤清單" }
        p(class: "text-gray-600 text-sm mt-1") { "管理每日自動抓取 IV Skew 的美股標的" }
      end

      render IvSkewExplainer.new
      render AddSymbolForm.new

      if @grouped.empty?
        div(class: "text-center text-gray-500 py-12") { "清單為空，請先加入標的" }
      else
        div(class: "space-y-6 mt-8") do
          @grouped.each { |group_tag, items| render GroupSection.new(group_tag:, items:) }
        end
      end

      render StrategyGuide.new
    end
    render_scripts
  end

  private

  # JavaScript 已搬到 app/frontend/behaviors/ivWatchlists.js（稽核 H-3）。
  # entrypoints/behaviors.ts 會依 data-behavior 動態載入該模組。
  def render_scripts
    div(data: { behavior: "iv-watchlists" })
  end
end
