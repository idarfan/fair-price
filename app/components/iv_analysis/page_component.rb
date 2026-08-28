# frozen_string_literal: true

class IvAnalysis::PageComponent < ApplicationComponent
  def view_template
    div do
      div(class: "flex items-center justify-between mb-6") do
        div do
          h1(class: "text-xl font-bold text-gray-900") { plain "期權 IV 分析" }
          p(class: "text-sm text-gray-500 mt-0.5") { plain "IV Rank · IV Percentile · ATM IV 歷史追蹤" }
        end
      end

      render IvAnalysis::DashboardComponent.new
      render IvAnalysis::QueryFormComponent.new
      render IvAnalysis::ResultComponent.new
      render IvAnalysis::WatchlistComponent.new
      render IvAnalysis::EducationComponent.new
    end

    render_script
  end

  private

  # JavaScript 已搬到 app/frontend/behaviors/ivAnalysis.js（稽核 H-3）。
  # entrypoints/behaviors.ts 會依 data-behavior 動態載入該模組。
  def render_script
    div(data: { behavior: "iv-analysis" })
  end
end
