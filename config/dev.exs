use Mix.Config

config :sigil, SigilWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: []

config :sigil, SigilWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/sigil_gateway_web/views/.*(ex)$},
      ~r{lib/sigil_gateway_web/templates/.*(eex)$}
    ]
  ]

config :phoenix, :stacktrace_depth, 20
