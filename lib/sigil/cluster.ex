defmodule Sigil.Cluster do
  require Logger

  def handle_broadcast(msg) do
    Logger.info "Got broadcast: #{inspect msg}"
    :ok
  end
end