import Config

# Load .env file if it exists (for local development)
if File.exists?(".env") do
  File.stream!(".env")
  |> Stream.map(&String.trim/1)
  |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] -> System.put_env(key, String.trim(value))
      _ -> :ok
    end
  end)
end

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
      nil ->
        ["https://#{host}"]

      "" ->
        ["https://#{host}"]

      "false" ->
        false

      "0" ->
        false

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

  # Android APK key hash origins for passkey authentication
  # Parse comma-separated list from env, or use debug key fallback for testing
  android_origins_env = System.get_env("WEBAUTHN_ANDROID_ORIGINS")
  android_origins = case android_origins_env do
    nil -> 
      # Default: include debug key for testing against production from Android Studio
      ["android:apk-key-hash:oFxUkld1AklP1_IHBdfiyxkUtILhDpBjhwyDsAS3hm4"]
    "" -> 
      []
    value -> 
      value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end
  config :friends, :webauthn_android_origins, android_origins

end

# MinIO / S3 Configuration
# MinIO / S3 Configuration
if System.get_env("MINIO_ENDPOINT") do
  endpoint = System.get_env("MINIO_ENDPOINT")
  scheme = if String.starts_with?(endpoint, "https://") or System.get_env("MINIO_PORT") == "443", do: "https://", else: "http://"
  host = endpoint |> String.replace("http://", "") |> String.replace("https://", "")
  port = String.to_integer(System.get_env("MINIO_PORT") || "9000")

  # If using HTTPS and no explicit port, default to 443
  port = if scheme == "https://" and System.get_env("MINIO_PORT") == nil, do: 443, else: port

  config :ex_aws,
    access_key_id: System.get_env("MINIO_ROOT_USER"),
    secret_access_key: System.get_env("MINIO_ROOT_PASSWORD"),
    s3: [
      scheme: scheme,
      host: host,
      port: port,
      region: "local"
    ]

  config :friends, :media_bucket, System.get_env("MINIO_BUCKET_NAME") || "friends-images"
end
