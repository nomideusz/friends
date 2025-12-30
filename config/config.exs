import Config

config :friends,
  ecto_repos: [Friends.Repo],
  generators: [timestamp_type: :utc_datetime],
  admin_usernames: ["nom", "rietarius"],
  admin_invite_code: "ADMIN"

config :friends, FriendsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FriendsWeb.ErrorHTML, json: FriendsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Friends.PubSub,
  live_view: [signing_salt: "friends_live_salt"]

config :tailwind,
  version: "4.0.0",
  friends: [
    args: ~w(
      -i css/app.css
      -o ../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :ex_aws,
  json_codec: Jason,
  # Default to S3 config for MinIO
  s3: [
    scheme: "http://",
    host: "localhost",
    port: 9000,
    region: "local"
  ]

import_config "#{config_env()}.exs"
