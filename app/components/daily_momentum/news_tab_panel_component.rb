# frozen_string_literal: true

class DailyMomentum::NewsTabPanelComponent < ApplicationComponent
  def view_template
    div(id: "stock-news-panel", class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      render_header
      render_placeholder
      render_tab_bar
      render_tab_contents
    end
    render_script
  end

  private

  def render_header
    div(class: "px-5 py-4 border-b border-gray-100") do
      h2(class: "font-semibold text-gray-900") do
        span(class: "mr-2") { plain("📰") }
        plain("個股新聞")
      end
    end
  end

  def render_placeholder
    div(id: "news-placeholder", class: "px-5 py-10 text-center text-sm text-gray-400") do
      span(class: "block text-2xl mb-2") { plain("👆") }
      plain("點擊觀察名單中的股票代號，查看相關新聞")
    end
  end

  def render_tab_bar
    # Tab bar — hidden until first symbol is clicked
    div(
      id:    "news-tab-bar",
      class: "hidden border-b border-gray-200 px-4 flex items-center gap-0 flex-wrap"
    )
  end

  def render_tab_contents
    div(id: "news-tab-contents", class: "px-5")
  end

  # JavaScript 已搬到 app/frontend/behaviors/momentumNewsTabs.js（稽核 H-3）。
  # entrypoints/behaviors.ts 會依 data-behavior 動態載入該模組。
  def render_script
    div(data: { behavior: "momentum-news-tabs" })
  end
end
