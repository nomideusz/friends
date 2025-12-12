import Config

if System.get_env("PHX_SERVER") do
  config :friends, FriendsWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :friends, Friends.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :friends, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  origin_env = System.get_env("ORIGIN_CHECK")

  check_origin =
    case origin_env do
      nil -> ["https://#{host}"]
      "" -> ["https://#{host}"]
      "false" -> false
      "0" -> false
      value ->
        # allow comma-separated list; otherwise single origin
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> case do
          [single] -> [single]
          list -> list
        end
    end

  config :friends, FriendsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: check_origin

  # WebAuthn Relying Party ID - must match the domain
  # For "friends.zaur.app", we can use either "zaur.app" or "friends.zaur.app"
  # Using the full subdomain is more specific and secure
  webauthn_rp_id = System.get_env("WEBAUTHN_RP_ID") || host
  webauthn_origin = System.get_env("WEBAUTHN_ORIGIN") || "https://#{host}"

  config :friends, :webauthn_rp_id, webauthn_rp_id
  config :friends, :webauthn_origin, webauthn_origin
end

