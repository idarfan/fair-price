# frozen_string_literal: true

class DailyMomentum::AnalysisPanelComponent < ApplicationComponent
  def view_template
    div(id: "analysis-panel", class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      render_header
      render_placeholder
      render_tab_bar
      render_tab_contents
    end
    render_script
  end

  private

  def render_header
    div(class: "px-5 py-4 border-b border-gray-100 flex items-center justify-between") do
      h2(class: "font-semibold text-gray-900") do
        span(class: "mr-2") { plain("🐱") }
        plain("歐歐投資分析")
      end
      span(class: "text-xs text-indigo-400 font-medium") { plain("Powered by Groq / GPT-OSS 120B") }
    end
  end

  def render_placeholder
    div(id: "analysis-placeholder", class: "px-5 py-10 text-center text-sm text-gray-400") do
      span(class: "block text-2xl mb-2") { plain("🐾") }
      plain("點擊觀察名單中的 🐱 按鈕，獲取個股 AI 投資分析")
    end
  end

  def render_tab_bar
    div(
      id:    "analysis-tab-bar",
      class: "hidden bg-gray-50 border-b border-gray-100 px-4 py-2 flex items-center gap-1 flex-wrap"
    )
  end

  def render_tab_contents
    div(id: "analysis-tab-contents", class: "px-5 py-4")
  end

  # JavaScript 已搬到 app/frontend/behaviors/momentumAnalysisPanel.js（稽核 H-3）。
  # entrypoints/behaviors.ts 會依 data-behavior 動態載入該模組。
  def render_script
    div(data: { behavior: "momentum-analysis-panel" })
  end
end
