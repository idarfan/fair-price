# frozen_string_literal: true

class FairValue::AlertComponent < ApplicationComponent
  STYLES = {
    error:   { bg: "bg-red-50",     border: "border-red-400",    text: "text-red-800",    icon: "⛔" },
    warning: { bg: "bg-yellow-50",  border: "border-yellow-400", text: "text-yellow-800", icon: "⚠️" },
    info:    { bg: "bg-blue-50",    border: "border-blue-400",   text: "text-blue-800",   icon: "ℹ️" },
    success: { bg: "bg-green-50",   border: "border-green-400",  text: "text-green-800",  icon: "✅" }
  }.freeze

  # @param message [String] Main message content
  # @param type [Symbol] Alert type: :error, :warning, :info, :success
  # @param title [String, nil] Optional bold title above message
  # @param dismissible [Boolean] Show a close button (requires JS)
  # @param icon [String, nil] Override the default emoji icon
  def initialize(message:, type: :error, title: nil, dismissible: false, icon: nil)
    @message     = message
    @type        = type.to_sym
    @title       = title
    @dismissible = dismissible
    @icon        = icon
  end

  def view_template
    style = STYLES.fetch(@type, STYLES[:info])
    div(class: "border-l-4 p-4 rounded-md #{style[:bg]} #{style[:border]}", data: { alert: true }) do
      div(class: "flex items-start gap-3") do
        span(class: "text-xl flex-shrink-0 leading-none mt-0.5") { plain(@icon || style[:icon]) }
        div(class: "flex-1 min-w-0") do
          p(class: "font-semibold text-sm #{style[:text]}") { plain(@title) } if @title
          p(class: "text-sm #{style[:text]} #{@title ? 'mt-1' : ''}") { plain(@message) }
        end
        if @dismissible
          button(
            type: "button",
            class: "flex-shrink-0 #{style[:text]} hover:opacity-70",
            data: { dismiss: "alert" }
          ) { plain("✕") }
          script do
            raw "document.querySelectorAll('[data-dismiss=\"alert\"]').forEach(function(btn){btn.addEventListener('click',function(){btn.closest('[data-alert]').remove();});});".html_safe
          end
        end
      end
    end
  end
end
