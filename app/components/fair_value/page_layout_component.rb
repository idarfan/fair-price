# frozen_string_literal: true

class FairValue::PageLayoutComponent < ApplicationComponent
  # @param title [String] Browser <title> and page heading
  # @param ticker [String, nil] Current ticker (shown in nav when present)
  # @param discount_rate [Float] Current discount rate percentage
  # @param show_search_in_nav [Boolean] Show compact search form in the navbar
  # @param bg_class [String] Background Tailwind class for the page body
  # @param max_width [String] Max-width Tailwind class for the content container
  # @param show_footer [Boolean] Render the footer
  def initialize(
    title: "FairPrice",
    ticker: nil,
    discount_rate: 10.0,
    show_search_in_nav: false,
    bg_class: "bg-gray-50",
    max_width: "max-w-5xl",
    show_footer: true
  )
    @title              = title
    @ticker             = ticker
    @discount_rate      = discount_rate
    @show_search_in_nav = show_search_in_nav
    @bg_class           = bg_class
    @max_width          = max_width
    @show_footer        = show_footer
  end

  def view_template
    doctype
    html(lang: "zh-TW") do
      head do
        meta(charset: "utf-8")
        meta(name: "viewport", content: "width=device-width,initial-scale=1")
        title { plain("#{@ticker ? "#{@ticker} | " : ""}#{@title}") }
        stylesheet_link_tag("tailwind")
      end
      body(class: "#{@bg_class} text-gray-900 min-h-screen flex flex-col") do
        render_navbar
        main(class: "flex-1 #{@max_width} mx-auto w-full px-4 py-6") do
          yield
        end
        render_footer if @show_footer
      end
    end
  end

  private

  def render_navbar
    nav(class: "bg-white border-b border-gray-200 shadow-sm") do
      div(class: "max-w-5xl mx-auto px-4 py-3 flex items-center justify-between gap-4") do
        a(href: root_path, class: "flex items-center gap-2 font-bold text-blue-600 text-lg flex-shrink-0") do
          span(class: "text-2xl") { plain("📊") }
          span { plain("FairPrice") }
        end
        if @show_search_in_nav
          div(class: "flex-1 max-w-md") do
            render FairValue::SearchBarComponent.new(
              ticker: @ticker.to_s,
              discount_rate: @discount_rate,
              compact: true,
              show_discount_rate: false
            )
          end
        end
        if Rails.env.development?
          a(href: "/lookbook", class: "text-xs text-gray-400 hover:text-gray-600") { plain("Lookbook") }
        end
      end
    end
  end

  def render_footer
    footer(class: "border-t border-gray-200 bg-white mt-8 py-4") do
      p(class: "text-center text-xs text-gray-400") do
        plain("FairPrice — 數據來源 Finnhub | 僅供參考，不構成投資建議")
      end
    end
  end
end
