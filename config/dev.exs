import Config

# Configure database - using existing rzeczywiscie database
config :friends, Friends.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "rzeczywiscie_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 20

config :friends, FriendsWeb.Endpoint,
  # Bind to all interfaces so Android emulator can connect via 10.0.2.2
  http: [ip: {0, 0, 0, 0}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dev_secret_key_base_for_friends_app_must_be_at_least_64_bytes_long_1234567890",
  watchers: [
    tailwind: {Tailwind, :install_and_run, [:friends, ~w(--watch)]},
    node: ["build.js", "--watch", cd: Path.expand("../assets", __DIR__)]
  ]

config :friends, FriendsWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/friends_web/(controllers|live|components)/.*(ex|heex)$",
      ~r"assets/svelte/.*(svelte)$"
    ]
  ]

config :friends, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true

# WebAuthn RPID for development
config :friends, :webauthn_rp_id, "localhost"
# WebAuthn origin for dev server (matches Bandit on port 4001)
config :friends, :webauthn_origin, "http://localhost:4001"

# Android APK key hash origins for passkey authentication
# These are the SHA-256 fingerprints of the Android signing certificates
config :friends, :webauthn_android_origins, [
  # Android debug key (for local development with Android Studio)
  "android:apk-key-hash:oFxUkld1AklP1_IHBdfiyxkUtILhDpBjhwyDsAS3hm4"
  # Production key should be added to runtime.exs via environment variable
]

# Disable image processing on Windows (Image/vix doesn't support Windows)
# On Linux production, this defaults to true
config :friends, :enable_image_processing, false

# MinIO configuration for development
config :ex_aws,
  access_key_id: "minioadmin",
  secret_access_key: "minioadmin"

config :friends, :media_bucket, "friends-images"

# Import secret configuration for development (gitignored)
if File.exists?(Path.join(__DIR__, "dev.secret.exs")) do
  import_config "dev.secret.exs"
end

