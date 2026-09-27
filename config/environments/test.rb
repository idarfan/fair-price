# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # 2026-09-27：User 的 totp_secret／backup_codes 用 Active Record encryption，金鑰原本只在
  # credentials.yml.enc（需要 gitignore 的 master.key）。CI 沒有 master.key，建立 User 就報
  # "Missing Active Record encryption credential"。test 環境改用這組測試專用金鑰：
  # 隨機產生、與正式環境無關，測試庫每次清空，不影響任何真實資料。
  config.active_record.encryption.primary_key = "kRol1d2UGQo8EjTgLfkwi0rypgCr3w0x"
  config.active_record.encryption.deterministic_key = "ucGkSfOpSQMBG44vvMGQlFMEolFuFNGZ"
  config.active_record.encryption.key_derivation_salt = "pNxf3tlTH01ScXrxUfgQJXx284MjNhAh"
end
