# frozen_string_literal: true

class Ownership::PageComponent < ApplicationComponent
  def initialize(symbols:, selected:)
    @symbols  = symbols
    @selected = selected
  end

  def view_template
    div(
      id:    "ownership-root",
      class: "h-full",
      data:  { symbols: @symbols.to_json }
    )
  end
end
