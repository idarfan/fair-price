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
  end

  private

  def render_header
    div do
      a(href: "/admin/users", class: "text-xs text-blue-600 hover:underline") { plain("← 返回帳戶管理") }
      h1(class: "text-xl font-bold text-gray-900 mt-1") { plain(@user.email) }
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

  def render_pageviews_panel
    div(id: "tab-panel-pageviews", class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      div(class: "overflow-x-auto") do
        table(class: "w-full text-sm") do
          thead(class: "bg-gray-50 border-b border-gray-100") do
            tr do
              header_cell("進入頁面")
              header_cell("從哪來")
              header_cell("停留時長")
              header_cell("下一步去哪")
            end
          end
          tbody do
            @page_views.each_with_index do |activity, index|
              next_activity = @page_views[index + 1]
              tr(class: STRIPED_ROW_CLASS) do
                td(class: "px-3 py-2.5 text-sm text-gray-700") { plain(activity.path.presence || "—") }
                td(class: "px-3 py-2.5 text-sm text-gray-500") { plain(referrer_label(activity.referrer_path)) }
                td(class: "px-3 py-2.5 text-sm text-gray-500") { plain(fmt_duration_ms(activity.duration_ms)) }
                td(class: "px-3 py-2.5 text-sm text-gray-500") do
                  plain(next_activity ? next_activity.path.presence || "—" : "（結束瀏覽）")
                end
              end
            end
          end
        end
      end
      empty_state("尚無瀏覽紀錄") if @page_views.empty?
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
    script do
      raw <<~JS.html_safe
        (function () {
          var buttons = document.querySelectorAll('.tab-btn');
          var panels = { pageviews: document.getElementById('tab-panel-pageviews'), commands: document.getElementById('tab-panel-commands') };

          buttons.forEach(function (btn) {
            btn.addEventListener('click', function () {
              var target = btn.getAttribute('data-tab-target');
              buttons.forEach(function (b) {
                var active = b === btn;
                b.classList.toggle('border-blue-600', active);
                b.classList.toggle('text-blue-600', active);
                b.classList.toggle('border-transparent', !active);
                b.classList.toggle('text-gray-500', !active);
              });
              Object.keys(panels).forEach(function (key) {
                if (panels[key]) panels[key].classList.toggle('hidden', key !== target);
              });
            });
          });
        })();
      JS
    end
  end
end
