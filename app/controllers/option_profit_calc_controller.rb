# frozen_string_literal: true

class OptionProfitCalcController < ApplicationController
  def index
    render OptionProfitCalc::PageComponent.new
  end
end
