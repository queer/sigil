defmodule Sigil.Cluster do
  require Logger

  def handle_broadcast(msg) do
    Logger.warn "Got broadcast: #{inspect msg}"
    :ok
  end
end