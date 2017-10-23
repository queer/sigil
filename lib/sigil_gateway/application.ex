defmodule SigilGateway.Application do
  use Application
  require Logger

  alias SigilGateway.Platform

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    Logger.info "Starting sigil gateway..."
    Logger.info "etcd: #{inspect Violet.get_version()}"

    Logger.info "Platform info: #{inspect Platform.hostname_with_ip()}"
    Logger.info "Is docker?: #{inspect Platform.is_docker?()}"

    # TODO: Should be able to search for other gateway nodes

    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoint when the application starts
      supervisor(SigilGatewayWeb.Endpoint, []),
      # Start your own worker by calling: SigilGateway.Worker.start_link(arg1, arg2, arg3)
      # worker(SigilGateway.Worker, [arg1, arg2, arg3]),
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SigilGateway.Supervisor]
    Logger.info "Done!"
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    SigilGatewayWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
