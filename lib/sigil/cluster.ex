defmodule Sigil.Cluster do
  require Logger

  def handle_broadcast(msg) do
    Logger.warn "Got broadcast: #{inspect msg}"
    case msg[:t] do
      "discord:reshard" -> handle_reshard()
      _ -> Logger.warn "Ignoring #{inspect msg}"
    end
    :ok
  end

  defp handle_reshard do
    Logger.warn "Doing a full reshard!"
    SigilWeb.Endpoint.broadcast "sigil:gateway:discord", "sigil:gateway", %{op: 1, t: "discord:reshard", d: %{}}
  end
end