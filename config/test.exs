use Mix.Config

config :sigil, SigilWeb.Endpoint,
  http: [port: 4001],
  server: false

config :logger, level: :warn
