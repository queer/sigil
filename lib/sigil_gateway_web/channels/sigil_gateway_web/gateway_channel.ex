defmodule SigilGatewayWeb.GatewayChannel do
  @moduledoc """
  Channel used for managing gateway connections
  """
  
  use Phoenix.Channel
  require Logger

  alias SigilGateway.Etcd
  alias Phoenix.Socket

  @sigil_discord_etcd "sigil-discord"
  @heartbeat_interval 15000

  #intercept ["new_msg"]

  def join("gateway:discord", msg, socket) do
    # TODO: Extract this functionality out elsewhere?
    Logger.info "Discord socket got join msg: #{inspect msg}"
    shard_id = msg["id"]

    # Enumerate sigil-discord, check if something with this id has been registered
    listing = Etcd.list_dir @sigil_discord_etcd
    if Etcd.is_error listing do
      # Getting an error code means that it doesn't exist, so we create it
      Logger.info "Creating #{inspect @sigil_discord_etcd} because it doesn't exist...", discord_id: shard_id
      Etcd.make_dir(@sigil_discord_etcd)
    end

    Logger.info "Grabbing node list...", discord_id: shard_id
    # Get the nodes
    nodes = listing["node"]["nodes"]

    unless is_nil nodes do
      for node <- nodes do
        name = node["key"]
        is_dir = not is_nil(node["dir"]) and node["dir"]
        Logger.info "Found node: #{inspect name} (is_dir: #{inspect is_dir})", discord_id: shard_id
      end
    else
      Logger.warn "No nodes found!", discord_id: shard_id
    end

    shard_key = @sigil_discord_etcd <> "/" <> shard_id

    # Set up the incoming node in etcd
    prev = Etcd.get shard_key
    if Etcd.is_error prev do
      # `null` is the default value, ie. not assigned to anything
      # When we assign it a shard ID or something, then we update this value to the "real" thing
      # But if it doesn't exist, we just null it out
      Etcd.set @sigil_discord_etcd <> "/" <> shard_id, "null"
    end
    # TODO: Handle "resuming" the shard's "session" here

    # Start heartbeat pings
    :timer.send_interval(@heartbeat_interval, :ping)

    # TODO: Check if a shard's ID was re-assigned to someone else during the disconnection

    {:ok, socket}
  end

  def handle_info(:ping, socket) do
    push socket, "sigil:heartbeat", %{}
    {:noreply, socket}
  end

  def handle_in("sigil:heartbeat", msg, socket) do
    # When we get a heartbeat, update the client's last heartbeat time
    # We don't just rely on tagging sockets or etc. so that a client can safely reconnect to any node
    # This means that the input message has to contain client id etc.
    # TODO: Sequence numbers?
  end
end
