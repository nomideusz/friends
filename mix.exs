defmodule Friends.MixProject do
  use Mix.Project

  def project do
    [
      app: :friends,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Friends.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:live_svelte, "~> 0.16.0"},
      {:pigeon, "~> 2.0.0"},
      {:goth, "~> 1.4"},
      # WebAuthn/FIDO2 support
      {:cbor, "~> 1.0"},
      # MinIO / S3 Storage
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.20"},
      {:sweet_xml, "~> 0.7"},
      # Caching for performance optimization
      {:cachex, "~> 3.6"},
      # NOTE: For thumbnail generation on Linux production, add:
      {:image, "~> 0.54", only: :prod},
      # This doesn't work on Windows due to libvips/vix not supporting Windows.
      # The ImageProcessor module gracefully falls back to using originals.
      
      # LiveView Native for iOS/Android
      # NOTE: Commented out - requires Phoenix ~> 1.7.0 and LiveView ~> 1.0.2
      # We have Phoenix 1.8.1 and LiveView 1.1.x
      # Wait for LiveView Native 0.5+ for compatibility
      # {:live_view_native, "~> 0.4.0-rc.1"},
      # {:live_view_native_swiftui, "~> 0.4.0-rc.1"},
      # {:live_view_native_stylesheet, "~> 0.4.0-rc.1"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "cmd --cd assets npm install"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "cmd --cd assets npm install"],
      "assets.build": ["tailwind friends", "cmd --cd assets node build.js"],
      "assets.deploy": [
        "tailwind friends --minify",
        "cmd --cd assets node build.js --deploy",
        "phx.digest"
      ]
    ]
  end
end
