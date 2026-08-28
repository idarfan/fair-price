# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      include JsonAuthGate
    end
  end
end
