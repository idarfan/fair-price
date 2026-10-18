# frozen_string_literal: true

module Api
  module V1
    module HallOfFame
      # 名人堂人物 API（P5）。模組名與 ::HallOfFame 同名，引用 model／service 一律寫完整路徑。
      class OfficialsController < BaseController
        CATEGORIES = ::HallOfFame::Official::CATEGORIES

        def index
          category = params[:category].to_s
          return render(json: { error: "category 必須是 #{CATEGORIES.join('／')}" }, status: :bad_request) unless CATEGORIES.include?(category)

          render json: { officials: directory.cards(category) }
        end

        def show
          official = ::HallOfFame::Official.find_by(slug: params[:slug].to_s, active: true)
          return render(json: { error: "找不到人物" }, status: :not_found) unless official

          render json: directory.profile(official)
        end

        private

        def directory = ::HallOfFame::OfficialDirectory.new
      end
    end
  end
end
