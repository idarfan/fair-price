# frozen_string_literal: true

class StockAlert::AlertFormComponent < ApplicationComponent
  # @param alert  [PriceAlert]
  # @param action [String]  form action URL
  # @param method [String]  HTTP method for _method override (patch/post)
  def initialize(alert:, action:, method: "post")
    @alert  = alert
    @action = action
    @method = method
  end

  def view_template
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm p-6 max-w-lg") do
      h1(class: "text-lg font-semibold text-gray-900 mb-5") do
        plain(@method == "patch" ? "編輯到價通知" : "新增到價通知")
      end

      render_errors if @alert.errors.any?

      form(action: @action, method: "post", class: "space-y-4") do
        input(type: "hidden", name: "_method", value: @method) if @method != "post"
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

        render_field("股票代號", "price_alert[symbol]", "pa_symbol") do
          input(
            type: "text", id: "pa_symbol", name: "price_alert[symbol]",
            value: @alert.symbol.to_s, required: true, placeholder: "AAPL",
            class: "w-full px-3 py-2 border border-gray-200 rounded-lg font-mono uppercase text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
          )
        end

        render_field("目標價 (USD)", "price_alert[target_price]", "pa_target") do
          input(
            type: "number", id: "pa_target", name: "price_alert[target_price]",
            value: @alert.target_price.to_s, required: true,
            step: "0.01", min: "0.01", placeholder: "150.00",
            class: "w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
          )
        end

        render_field("觸發條件", "price_alert[condition]", "pa_condition") do
          select(
            id: "pa_condition", name: "price_alert[condition]",
            class: "w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
          ) do
            option(value: "above", selected: @alert.condition == "above" ? "selected" : nil) { plain("高於目標價 ▲") }
            option(value: "below", selected: @alert.condition == "below" ? "selected" : nil) { plain("低於目標價 ▼") }
          end
        end

        render_field("備註（選填）", "price_alert[notes]", "pa_notes") do
          textarea(
            id: "pa_notes", name: "price_alert[notes]",
            rows: 2, placeholder: "備忘事項…",
            class: "w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
          ) { plain(@alert.notes.to_s) }
        end

        div(class: "flex gap-3 pt-2") do
          button(
            type: "submit",
            class: "px-5 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
          ) { plain("儲存") }
          a(
            href: watchlist_alerts_path,
            class: "px-5 py-2 border border-gray-200 text-gray-500 text-sm rounded-lg hover:bg-gray-50 transition-colors"
          ) { plain("取消") }
        end
      end
    end
  end

  private

  def render_errors
    div(class: "mb-4 px-4 py-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg") do
      ul(class: "list-disc list-inside space-y-1") do
        @alert.errors.full_messages.each do |msg|
          li { plain(msg) }
        end
      end
    end
  end

  def render_field(label_text, _field_name, field_id, &block)
    div do
      label(for: field_id, class: "block text-sm font-medium text-gray-600 mb-1") { plain(label_text) }
      yield block
    end
  end
end
