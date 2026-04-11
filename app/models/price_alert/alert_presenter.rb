# frozen_string_literal: true

class PriceAlert
  # Wraps a PriceAlert record + current market price and exposes display values.
  # Keeps conditional display logic out of the view component.
  class AlertPresenter
    def initialize(alert:, current_price: nil)
      @alert         = alert
      @current_price = current_price&.to_f
    end

    def condition_label
      @alert.condition == "above" ? "高於 ▲" : "低於 ▼"
    end

    def condition_button_class
      base = "text-xs px-2 py-0.5 rounded-full font-medium transition-colors cursor-pointer "
      base + (@alert.condition == "above" ? "bg-green-50 text-green-600 hover:bg-green-100" : "bg-red-50 text-red-500 hover:bg-red-100")
    end

    def status_label
      if @alert.triggered?
        "已觸發"
      elsif @alert.active?
        "監控中"
      else
        "已停用"
      end
    end

    def status_button_class
      base = "text-xs px-2 py-0.5 rounded-full font-medium transition-colors cursor-pointer "
      if @alert.triggered?
        base + "bg-purple-50 text-purple-500"
      elsif @alert.active?
        base + "bg-blue-50 text-blue-600 hover:bg-blue-100"
      else
        base + "bg-gray-100 text-gray-400 hover:bg-gray-200"
      end
    end

    def price_color
      return "text-gray-700" unless @current_price&.positive?

      target = @alert.target_price.to_f
      return "text-gray-700" if target.zero?

      if @alert.condition == "above"
        @current_price >= target ? "text-green-600" : "text-gray-700"
      else
        @current_price <= target ? "text-red-500" : "text-gray-700"
      end
    end

    def current_price_display
      @current_price&.positive? ? @current_price : nil
    end
  end
end
