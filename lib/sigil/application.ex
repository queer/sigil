defmodule Sigil.Application do
  use Application
  require Logger

  alias Eden.Platform

  @version Mix.Project.config[:version]

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    Logger.info "Starting sigil gateway..."
    Logger.info "etcd: #{inspect Violet.get_version()}"

    Logger.info "Platform info: #{inspect Platform.hostname_with_ip()}"
    Logger.info "Is docker?: #{inspect Platform.is_docker?()}"

    Logger.info "Is node already alive?: #{inspect Node.alive?()}"
    Logger.info "NODE_NAME: #{inspect System.get_env("NODE_NAME")}"

    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoint when the application starts
      supervisor(SigilWeb.Endpoint, []),
      
      worker(Eden, [], shutdown: 5000),
      worker(Sigil.Discord.ShardManager, [], name: Sigil.Discord.ShardManager),

      # Task supervisor
      {Task.Supervisor, name: Sigil.BroadcastTasks}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sigil.Supervisor]
    Logger.info "Done!"
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    SigilWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def version do
    @version
  end
end
