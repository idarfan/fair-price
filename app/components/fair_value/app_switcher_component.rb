# frozen_string_literal: true

class FairValue::AppSwitcherComponent < ApplicationComponent
  APP_LINKS = [
    { icon: "📊", label: "FairPrice",      href: "/",         desc: "美股公允價值分析" },
    { icon: "📈", label: "Daily Momentum", href: "/momentum", desc: "每日動量報告" },
    { icon: "📁", label: "Portfolio",      href: "/portfolio", desc: "個人持股追蹤" },
    { icon: "🔔", label: "Watchlist",      href: "/watchlist",  desc: "自選股到價通知" },
    { icon: "📉", label: "Options",        href: "/options",    desc: "美股期權分析｜策略推薦｜IV Rank" },
    { icon: "🏦", label: "持股結構",       href: "/ownership",  desc: "Watchlist 持股結構變化圖表" },
    { icon: "💹", label: "融資試算",       href: "/margin",               desc: "美股融資交易獲利試算與持股管理" },
    { icon: "📍", label: "期權歷史價格",   href: "/option_price_tracker", desc: "期權 Premium 歷史價格追蹤與分析" }
  ].freeze

  def initialize(navbar: false)
    @dd_id  = "app-switcher"
    @navbar = navbar
  end

  def view_template
    @current_path = helpers.request.path
    div(class: "relative") do
      render_trigger
      render_panel
    end
    render_script
  end

  private

  def render_trigger
    if @navbar
      button(
        type: "button",
        id: "#{@dd_id}-btn",
        class: "flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm text-gray-600 hover:bg-gray-100 hover:text-gray-900 transition-colors",
        aria: { haspopup: "true", expanded: "false", controls: @dd_id }
      ) do
        span(class: "text-base") { plain("⚡") }
        span(class: "font-medium") { plain("切換工具") }
        span(id: "#{@dd_id}-chevron", class: "text-gray-400 text-xs ml-0.5 transition-transform duration-200") { plain("▼") }
      end
    else
      button(
        type: "button",
        id: "#{@dd_id}-btn",
        class: "w-full flex items-center justify-between gap-2 px-3 py-2.5 rounded-lg bg-white border border-gray-200 shadow-sm text-sm text-gray-700 hover:bg-gray-50 hover:border-gray-300 transition-colors",
        aria: { haspopup: "true", expanded: "false", controls: @dd_id }
      ) do
        div(class: "flex items-center gap-2") do
          span(class: "text-base") { plain("⚡") }
          span(class: "font-medium") { plain("切換工具") }
        end
        span(id: "#{@dd_id}-chevron", class: "text-gray-400 text-xs transition-transform duration-200") { plain("▼") }
      end
    end
  end

  def render_panel
    panel_class = if @navbar
                    "hidden absolute top-full left-0 mt-1 w-64 bg-white rounded-xl " \
                    "border border-gray-200 shadow-lg overflow-hidden z-50"
    else
                    "hidden mt-1 bg-white rounded-xl border border-gray-200 shadow-lg overflow-hidden"
    end
    div(
      id: @dd_id,
      class: panel_class,
      role: "menu"
    ) do
      # Header
      div(class: "px-3 py-2 bg-gray-50 border-b border-gray-100") do
        p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wider") { plain("我的工具") }
      end

      # App list
      div(class: "py-1") do
        APP_LINKS.each_with_index do |app, i|
          render_item(app)
          div(class: "mx-3 border-t border-gray-100") if i == APP_LINKS.length - 2
        end
      end

      # Footer
      div(class: "px-3 py-2 bg-gray-50 border-t border-gray-100") do
        p(class: "text-xs text-gray-400 text-center") { plain("更多工具即將推出…") }
      end
    end
  end

  def render_item(app)
    current  = app[:href] != "#" && @current_path.start_with?(app[:href] == "/" ? "/" : app[:href])
    current  = (@current_path == "/") if app[:href] == "/"
    upcoming = app[:href] == "#"

    if upcoming
      render_upcoming_item(app)
    else
      a(
        href: app[:href],
        class: "flex items-center gap-2.5 px-3 py-2 text-sm transition-colors #{current ? 'bg-blue-50 text-blue-700' : 'text-gray-700 hover:bg-gray-50'}",
        role: "menuitem"
      ) do
        span(class: "text-lg flex-shrink-0") { plain(app[:icon]) }
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-1.5") do
            span(class: "font-medium text-sm") { plain(app[:label]) }
            if current
              span(class: "text-xs bg-blue-100 text-blue-600 px-1.5 py-0.5 rounded-full leading-none") { plain("目前") }
            end
          end
          p(class: "text-xs truncate text-gray-400") { plain(app[:desc]) }
        end
      end
    end
  end

  def render_upcoming_item(app)
    div(class: "flex items-center gap-2.5 px-3 py-2 text-sm cursor-not-allowed opacity-50", role: "menuitem") do
      span(class: "text-lg flex-shrink-0") { plain(app[:icon]) }
      div(class: "flex-1 min-w-0") do
        div(class: "flex items-center gap-1.5") do
          span(class: "font-medium text-sm text-gray-500") { plain(app[:label]) }
          span(class: "text-xs bg-gray-100 text-gray-400 px-1.5 py-0.5 rounded-full leading-none") { plain("即將推出") }
        end
        p(class: "text-xs truncate text-gray-300") { plain(app[:desc]) }
      end
    end
  end

  def render_script
    script do
      raw <<~JS.html_safe
        (function() {
          var btn   = document.getElementById('#{@dd_id}-btn');
          var panel = document.getElementById('#{@dd_id}');
          var chev  = document.getElementById('#{@dd_id}-chevron');
          if (!btn || !panel) return;

          function open() {
            panel.classList.remove('hidden');
            btn.setAttribute('aria-expanded', 'true');
            chev.style.transform = 'rotate(180deg)';
          }
          function close() {
            panel.classList.add('hidden');
            btn.setAttribute('aria-expanded', 'false');
            chev.style.transform = '';
          }
          function toggle() { panel.classList.contains('hidden') ? open() : close(); }

          btn.addEventListener('click', function(e) { e.stopPropagation(); toggle(); });
          document.addEventListener('click', function(e) {
            if (!panel.contains(e.target) && e.target !== btn) close();
          });
          document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') close();
          });
        })();
      JS
    end
  end
end
