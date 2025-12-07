import Config

config :friends, Friends.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "friends_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :friends, FriendsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_for_friends_app_must_be_at_least_64_bytes_long_1234567890",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view, :enable_expensive_runtime_checks, true

