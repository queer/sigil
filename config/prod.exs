use Mix.Config

config :sigil, SigilWeb.Endpoint,
  load_from_system_env: true,
  http: [host: "0.0.0.0", port: 4000]

config :logger, level: :info
