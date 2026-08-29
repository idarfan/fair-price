# frozen_string_literal: true

class OptionsController < ApplicationController
  def index
    render ::Options::PageComponent.new(symbol: nil)
  end

  def show
    symbol = sanitize_symbol(params[:symbol])
    # 前綴 `::` 不可省略：controller 內的 `Options` 會先解析到
    # ActionController::ParamsWrapper::Options，導致 NameError 而整頁 500。
    # index 一直有寫 `::`，show 漏了，所以 /options 正常但 /options/:symbol 全掛。
    render ::Options::PageComponent.new(symbol: symbol)
  end

  private

  def sanitize_symbol(raw)
    raw.to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").first(10)
  end
end
