# frozen_string_literal: true

class Admin::Users::ShowComponent < ApplicationComponent
  STRIPED_ROW_CLASS = "odd:bg-green-50 even:bg-blue-50 hover:bg-purple-100 transition-colors"

  # @param user [User]
  # @param page_views [Array<UserActivity>] kind: page_view, ordered by started_at asc
  # @param commands [Array<UserActivity>] kind: command, ordered by started_at desc
  def initialize(user:, page_views:, commands:)
    @user       = user
    @page_views = page_views
    @commands   = commands
  end

  def view_template
    div(class: "space-y-5") do
      render_header
      render_tabs
      render_pageviews_panel
      render_commands_panel
    end
    render_script
    render_export_script
  end

  private

  def render_header
    div(class: "flex items-start justify-between gap-4") do
      div do
        a(href: "/admin/users", class: "text-xs text-blue-600 hover:underline") { plain("← 返回帳戶管理") }
        h1(class: "text-xl font-bold text-gray-900 mt-1") { plain(@user.email) }
      end
      button(
        type: "button", id: "pageviews-export-pdf-btn",
        disabled: @page_views.empty?,
        class: "text-xs px-3 py-1.5 rounded-lg border font-medium transition-colors " \
               "#{@page_views.empty? ? 'border-gray-200 text-gray-300 cursor-not-allowed' : 'border-gray-300 text-gray-600 hover:bg-gray-50'}"
      ) { plain("匯出 PDF") }
    end
  end

  def render_tabs
    div(class: "flex gap-2 border-b border-gray-200") do
      button(
        type: "button", data: { tab_target: "pageviews" },
        class: "tab-btn px-4 py-2 text-sm font-medium border-b-2 border-blue-600 text-blue-600"
      ) { plain("瀏覽軌跡") }
      button(
        type: "button", data: { tab_target: "commands" },
        class: "tab-btn px-4 py-2 text-sm font-medium border-b-2 border-transparent text-gray-500"
      ) { plain("指令記錄") }
    end
  end

  WEEKDAY_LABELS = %w[日 一 二 三 四 五 六].freeze

  # 依日期分組、最近日期排最前面（月份自然含在日期標題裡：例如
  # 「2026年08月06日（三）」）；每組內維持原本的 進入→下一步 時序推導
  # （組內仍是舊→新，不然「下一步去哪」會反過來指向更早的頁面）；
  # 跨組（換日）不推導下一步，避免把「今天最後一頁」誤標成「明天第一頁」。
  # 每組用 <details>/<summary> 做成可收摺（Phlex 2.x 禁用 onclick，這是
  # 唯一允許的原生互動元件），只展開最近一天，避免久了資料一次全展開。
  def render_pageviews_panel
    div(id: "tab-panel-pageviews", class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      div(class: "p-3 space-y-3") do
        grouped_page_views.each_with_index do |(date, activities), index|
          render_pageviews_day_group(date, activities, expanded: index.zero?)
        end
      end
      empty_state("尚無瀏覽紀錄") if @page_views.empty?
    end
  end

  def grouped_page_views
    @page_views.group_by { |activity| activity.started_at.to_date }.sort_by { |date, _| date }.reverse
  end

  def total_dwell_ms(activities)
    activities.sum { |activity| activity.duration_ms || 0 }
  end

  def render_pageviews_day_group(date, activities, expanded:)
    details(open: expanded, class: "border border-orange-300 rounded-lg overflow-hidden group") do
      summary(
        class: "px-3 py-2 bg-green-50 border-b border-orange-300 cursor-pointer select-none " \
               "list-none flex items-center gap-2 hover:bg-green-100 transition-colors"
      ) do
        span(class: "text-orange-500 text-xs transition-transform group-open:rotate-90") { plain("▶") }
        span(class: "text-sm font-semibold text-gray-700") do
          plain("#{date.strftime('%Y年%m月%d日')}（#{WEEKDAY_LABELS[date.wday]}）")
        end
        span(class: "text-xs text-gray-500") { plain("合計停留 #{fmt_duration_ms(total_dwell_ms(activities))}") }
        span(class: "text-xs text-gray-400") { plain("#{activities.size} 筆") }
      end
      div(class: "overflow-x-auto") do
        table(class: "w-full text-sm") do
          thead(class: "bg-gray-50 border-b border-gray-100") do
            tr do
              header_cell("時間")
              header_cell("進入頁面")
              header_cell("從哪來")
              header_cell("停留時長")
              header_cell("下一步去哪")
            end
          end
          tbody do
            activities.each_with_index do |activity, index|
              next_activity = activities[index + 1]
              tr(class: STRIPED_ROW_CLASS) do
                td(class: "px-3 py-2.5 text-sm text-gray-400 whitespace-nowrap") { plain(activity.started_at.strftime("%H:%M:%S")) }
                td(class: "px-3 py-2.5 text-sm text-gray-700") { plain(activity.path.presence || "—") }
                td(class: "px-3 py-2.5 text-sm text-gray-500") { plain(referrer_label(activity.referrer_path)) }
                td(class: "px-3 py-2.5 text-sm text-gray-500") { plain(fmt_duration_ms(activity.duration_ms)) }
                td(class: "px-3 py-2.5 text-sm text-gray-500") do
                  plain(next_activity ? next_activity.path.presence || "—" : "（當日結束瀏覽）")
                end
              end
            end
          end
        end
      end
    end
  end

  def render_commands_panel
    div(id: "tab-panel-commands", class: "hidden bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      div(class: "overflow-x-auto") do
        table(class: "w-full text-sm") do
          thead(class: "bg-gray-50 border-b border-gray-100") do
            tr do
              header_cell("時間")
              header_cell("指令")
              header_cell("完整參數")
            end
          end
          tbody do
            @commands.each do |activity|
              tr(class: STRIPED_ROW_CLASS) do
                td(class: "px-3 py-2.5 text-sm text-gray-500 whitespace-nowrap") { plain(activity.started_at.strftime("%Y-%m-%d %H:%M:%S")) }
                td(class: "px-3 py-2.5 text-sm text-gray-700") { plain(activity.action_name) }
                td(class: "px-3 py-2.5 text-sm text-gray-600") { render_metadata(activity.metadata) }
              end
            end
          end
        end
      end
      empty_state("尚無指令紀錄") if @commands.empty?
    end
  end

  def render_metadata(metadata)
    return plain("—") if metadata.blank?

    div(class: "space-y-0.5") do
      metadata.each do |key, value|
        div(class: "text-xs") do
          span(class: "text-gray-400") { plain("#{key}: ") }
          span { plain(value.to_s) }
        end
      end
    end
  end

  def referrer_label(referrer_path)
    return "直接進入" if referrer_path.nil?

    referrer_path == "external" ? "外部連結" : referrer_path
  end

  def header_cell(label)
    th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain(label) }
  end

  def empty_state(message)
    p(class: "text-sm text-gray-400 text-center py-6") { plain(message) }
  end

  def render_script
    # JavaScript 已搬到 app/frontend/behaviors/adminUserActivity.js（稽核 H-3 Wave 2）。
    # 原本的 Ruby 插值改成 data attribute 傳入。
    div(data: { behavior: "admin-user-activity" })
  end

  # 匯出 PDF：先把所有 <details> 暫時展開（不然收摺的日期組不會被拍進圖），
  # 用 html-to-image 把整個瀏覽軌跡面板拍成一張長圖，再用 jsPDF 依 A4 高度
  # 切成多頁嵌進 PDF（長圖直接分頁嵌入，不是逐頁重新排版）。拍完無論成功
  # 失敗都要還原原本的展開/收摺狀態，不能讓使用者匯出完發現畫面被打亂。
  def render_export_script
    # JavaScript 已搬到 app/frontend/behaviors/adminUserExport.js（稽核 H-3 Wave 2）。
    # 原本的 Ruby 插值改成 data attribute 傳入。
    div(data: { behavior: "admin-user-export", email: @user.email })
  end
end
