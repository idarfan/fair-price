Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"]
end

OmniAuth.config.on_failure = ->(env) { SessionsController.action(:failure).call(env) }
