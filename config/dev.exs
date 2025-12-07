import Config

# Configure database - using existing rzeczywiscie database
config :friends, Friends.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "rzeczywiscie_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :friends, FriendsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_for_friends_app_must_be_at_least_64_bytes_long_1234567890",
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

