# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :sigil_gateway, SigilGatewayWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "XobaN0rnyoTlAaiwu3ziCIqo2x567nQhhYCj75W/2lBKOO7x8yH207YrCsh1FxEX",
  render_errors: [view: SigilGatewayWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: SigilGateway.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "[$time] $metadata[$level] $message\n",
  metadata: [:request_id, :discord_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
