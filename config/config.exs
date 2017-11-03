use Mix.Config

config :sigil, SigilWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "XobaN0rnyoTlAaiwu3ziCIqo2x567nQhhYCj75W/2lBKOO7x8yH207YrCsh1FxEX",
  render_errors: [view: SigilWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Sigil.PubSub,
           adapter: Phoenix.PubSub.PG2]

config :logger, :console,
  format: "[$time] $metadata[$level] $message\n",
  metadata: [:request_id, :discord_id]

config :logger, level: :info

import_config "#{Mix.env}.exs"
