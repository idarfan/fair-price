source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
gem "httparty",         "~> 0.22"
gem "phlex-rails",      "~> 2.0"
gem "pg",               "~> 1.5"
gem "kramdown",            "~> 2.4"
gem "kramdown-parser-gfm", "~> 1.1"
gem "tailwindcss-rails", "~> 4.0"
gem "vite_rails",        "~> 3.0"

# Auth: Google OAuth 登入 + TOTP 雙因子
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "rotp"
gem "rqrcode"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

group :development, :test do
  gem "dotenv-rails"
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Testing
  gem "rspec-rails",  "~> 7.0"
  gem "factory_bot_rails"
  gem "faker"
  gem "simplecov", require: false          # 覆蓋率（bin/audit coverage）

  # 稽核工具
  # spec 本身的 lint（EmptyExampleGroup、重複 describe、未使用的 let…）
  gem "rubocop-rspec", require: false
  # schema 稽核：缺索引、缺 FK、validation 與 NOT NULL 不一致
  gem "database_consistency", require: false
end

group :development do
  gem "web-console"
  gem "lookbook", ">= 2.3"

  # N+1 查詢偵測（只記錄不拋錯，設定見 config/initializers/bullet.rb）
  gem "bullet"
end

gem "ruby-lsp", "~> 0.26.8", group: :development
