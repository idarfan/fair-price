# frozen_string_literal: true

class IvAnalysisController < ApplicationController
  def index
    render IvAnalysis::PageComponent.new
  end
end
