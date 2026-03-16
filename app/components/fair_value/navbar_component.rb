# frozen_string_literal: true

class FairValue::NavbarComponent < ApplicationComponent
  # @param ticker [String, nil] Current ticker shown in nav
  # @param discount_rate [Float] Current discount rate percentage
  # @param show_search [Boolean] Show compact search in navbar
  # @param show_lookbook [Boolean] Show Lookbook link (dev only)
  def initialize(ticker: nil, discount_rate: 10.0, show_search: false, show_lookbook: Rails.env.development?)
    @ticker        = ticker
    @discount_rate = discount_rate
    @show_search   = show_search
    @show_lookbook = show_lookbook
  end

  def view_template
    nav(class: "bg-white border-b border-gray-200 shadow-sm") do
      div(class: "px-4 py-3 flex items-center justify-between gap-4") do
        div(class: "flex items-center gap-2 flex-shrink-0") do
          a(href: root_path, class: "flex items-center gap-2 font-bold text-blue-600 text-lg") do
            span(class: "text-2xl") { plain("📊") }
            span { plain("FairPrice") }
          end
          div(class: "w-px h-5 bg-gray-200 mx-1")
          render FairValue::AppSwitcherComponent.new(navbar: true)
        end
        if @show_search
          div(class: "flex-1 max-w-md") do
            render FairValue::SearchBarComponent.new(
              ticker:             @ticker.to_s,
              discount_rate:      @discount_rate,
              compact:            true,
              show_discount_rate: false
            )
          end
        end
        if @show_lookbook
          a(href: "/lookbook", class: "text-xs text-gray-400 hover:text-gray-600 flex-shrink-0") { plain("Lookbook") }
        end
      end
    end
  end
end
