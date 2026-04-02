# frozen_string_literal: true

class MarginController < ApplicationController
  def index
    render Margin::PageComponent.new
  end
end
