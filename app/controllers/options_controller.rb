# frozen_string_literal: true

class OptionsController < ApplicationController
  def index
    render ::Options::PageComponent.new(symbol: nil)
  end

  def show
    symbol = sanitize_symbol(params[:symbol])
    render Options::PageComponent.new(symbol: symbol)
  end

  private

  def sanitize_symbol(raw)
    raw.to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").first(10)
  end
end
