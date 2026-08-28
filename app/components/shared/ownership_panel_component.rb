# frozen_string_literal: true

# Shared draggable ownership breakdown panel.
# Renders the HTML modal + all ownership-related JavaScript.
# Trigger by clicking any element with `data-ownership-symbol="AAPL"`.
# Used by HoldingListComponent and AlertListComponent.
class Shared::OwnershipPanelComponent < ApplicationComponent
  def view_template
    render_panel
    render_script
  end

  private

  def render_panel
    div(id:    "ownership-panel",
        style: "display:none; position:fixed; left:50%; top:50%; " \
               "transform:translate(-50%,-50%); z-index:50; " \
               "min-width:28rem; width:max-content; max-width:min(56rem,92vw); " \
               "max-height:82vh; overflow-y:auto;",
        class: "bg-white rounded-2xl shadow-2xl border-2 border-orange-200") do
      div(id:    "ownership-titlebar",
          class: "flex items-center justify-between px-4 py-3 border-b border-gray-100 " \
                 "cursor-move select-none sticky top-0 bg-white rounded-t-2xl") do
        div(class: "flex items-center gap-2 min-w-0") do
          img(id:    "ownership-logo-img",
              src:   "",
              alt:   "",
              class: "flex-shrink-0 w-6 h-6 rounded-full object-contain border border-gray-100 bg-white")
          span(id:    "ownership-title",
               class: "text-sm font-bold text-gray-900 truncate") { plain("持股結構") }
        end
        button(id:    "ownership-close-btn",
               type:  "button",
               class: "flex-shrink-0 ml-2 text-gray-400 hover:text-gray-600 text-xl " \
                      "leading-none transition-colors") { plain("×") }
      end

      div(class: "p-4") do
        div(id: "ownership-loading", style: "display:none",
            class: "py-6 text-center text-sm text-gray-400 animate-pulse") { plain("載入中…") }
        div(id: "ownership-error", style: "display:none",
            class: "py-4 text-center text-sm text-red-400")
        div(id: "ownership-body", style: "display:none", class: "space-y-4") do
          div(id: "ownership-summary", class: "grid grid-cols-2 gap-2")
          div do
            p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2") { plain("主要機構持有人") }
            div(class: "overflow-x-auto") do
              table(class: "w-full text-xs") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-2 py-1.5 text-left text-gray-400 font-semibold")  { plain("機構") }
                    th(class: "px-2 py-1.5 text-right text-gray-400 font-semibold") { plain("持股 %") }
                    th(class: "px-2 py-1.5 text-right text-gray-400 font-semibold") { plain("市值") }
                    th(class: "px-2 py-1.5 text-right text-gray-400 font-semibold") { plain("申報日") }
                  end
                end
                tbody(id: "ownership-holders-body")
              end
            end
          end
        end
      end
    end
  end

  # JavaScript 已搬到 app/frontend/behaviors/ownershipPanel.js（稽核 H-3）。
  # entrypoints/behaviors.ts 會依 data-behavior 動態載入該模組。
  def render_script
    div(data: { behavior: "ownership-panel" })
  end
end
