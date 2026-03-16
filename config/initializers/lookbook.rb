# frozen_string_literal: true

if defined?(Lookbook)
  Lookbook.configure do |config|
    config.project_name   = "FairPrice Components"
    config.preview_paths  = config.preview_paths + [ Rails.root.join("test/components/previews") ]
    config.preview_layout = "component_preview"
  end
end
