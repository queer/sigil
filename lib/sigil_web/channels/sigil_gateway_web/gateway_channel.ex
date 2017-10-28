defmodule SigilWeb.GatewayChannel do
  @moduledoc """
  Channel used for managing gateway connections

  Some general design notes:
  - We can't tag sockets etc. due to the distributed nature of the gateway, so
    we solve it by using etcd and redis
  - To handle fanouts, since we can't be lazy butts and assume everything is
    connected to one gateway, we:
  1. Take the fanout input request
  2. Send a pubsub over redis to fanout to all gateway nodes
  3. Gateway nodes fanout to clients
  The idea is that we can do a relatively-cheap backend fanout to reach all
  clients, and clients themselves can decide if theywant to do something with a
  given event, rather than trying to locate a specific client connected to a
  specific gateway.
  """

  use Phoenix.Channel
  require Logger

  alias Sigil.Discord.ShardManager, as: DiscordShardManager

  ## heartbeat stuff

  @heartbeat_interval 5000

  ## events

  @gateway_event "sigil:gateway"

  ## gateway opcodes

  @op_heartbeat 0
  @op_dispatch 1
  @op_broadcast_dispatch 2

  ## gateway dispatch types

  # Shard requests an available shard ID. Gateway responds if and only if a 
  # shard id is available AND the next shard is allowed to connect. 
  @dispatch_discord_shard "discord:shard"

  ## gateway error codes

  @error_generic 1000
  @error_unknown_op 1001
  @error_no_event_type 1002
  @error_missing_data 1003

  def join("sigil:gateway:discord", msg, socket) do
    # TODO: Extract this functionality out elsewhere?
    shard_id = msg["id"]
    bot_name = msg["bot_name"]
    Logger.metadata discord_id: shard_id
    Logger.info "Discord socket got join msg: #{inspect msg}"

    unless DiscordShardManager.is_shard_registered? bot_name, shard_id do
      Logger.info "Initializing #{bot_name} shard #{shard_id}"
      Violet.set DiscordShardManager.sigil_discord_etcd <> "/" <> shard_id, "null"
    end

    # Start heartbeat pings
    :timer.send_interval(@heartbeat_interval, {:heartbeat, shard_id})

    Logger.metadata discord_id: nil
    # TODO: Check if a shard's ID was re-assigned to someone else during the disconnection

    {:ok, socket}
  end

  def handle_info({:heartbeat, id}, socket) do
    Logger.info "Sending heartbeat", discord_id: id
    push_event socket, @op_heartbeat, %{
      id: id
    }

    {:noreply, socket}
  end

  def handle_in(@gateway_event, msg, socket) do
    unless is_nil msg["op"] do
      case msg["op"] do
        @op_heartbeat -> handle_heartbeat msg, socket
        @op_dispatch -> handle_dispatch msg, socket
        @op_broadcast_dispatch -> handle_broadcast msg, socket
      end
    else
      handle_unknown_op msg, socket
      {:noreply, socket}
    end
  end

  def handle_in(event, msg, socket) do
    Logger.warn "Unknown event: #{event} with msg #{inspect msg}"
    {:noreply, socket}
  end

  defp handle_unknown_op(msg, socket) do
    case msg["op"] do
      # @formatter:off
      nil -> push_event socket, @op_dispatch,
               error(@error_unknown_op, "no opcode specified")
      _ -> push_event socket, @op_dispatch,
             error(@error_unknown_op, "invalid opcode #{inspect msg["op"]}")
      # @formatter:on
    end
    {:noreply, socket}
  end

  defp handle_heartbeat(msg, socket) do
    # When we get a heartbeat, update the client's last heartbeat time
    # We don't just rely on tagging sockets or etc. so that a client can safely reconnect to any node
    # This means that the input message has to contain client id etc.
    # TODO: Actually back this with etcd
    # TODO: Sequence numbers?
    Logger.info "Got heartbeat from #{inspect msg["id"]}"
    {:noreply, socket}
  end

  defp handle_dispatch(msg, socket) do
    type = msg["t"]
    data = msg["d"]
    case type do
      # @formatter:off
      nil -> push_event socket, @op_dispatch,
               error(@error_no_event_type, "no event type specified")
      @dispatch_discord_shard -> handle_shard_request msg, socket
      _ -> Logger.info "dispatch data: #{inspect data}"
      # @formatter:on
    end
    {:noreply, socket}
  end


  defp handle_shard_request(msg, socket) do
    cond do
      is_nil msg["bot_name"] -> push_event socket, @op_dispatch, 
          error(@error_missing_data, "no bot name given")
      is_nil msg["shard_count"] -> push_event socket, @op_dispatch, 
          error(@error_missing_data, "no shard count given")
      true -> send_shard_data msg, socket
    end

    {:noreply, socket}
  end

  defp send_shard_data(msg, socket) do
    {res, data} = GenServer.call Sigil.Discord.ShardManager, 
        {:attempt_connect, msg["bot_name"], GenServer.call(Eden, :get_hash), 
            msg["shard_count"]}
    case res do
      :error -> push_event socket, @op_dispatch, error(@error_generic, data)
      :ok ->push_event socket, @op_dispatch, %{
        shard_id: data,
        shard_count: msg["shard_count"],
        bot_name: msg["bot_name"]
      }
    end
  end

  defp handle_broadcast(msg, socket) do
    Eden.fanout_exec Sigil.BroadcastTasks, Sigil.Cluster, :handle_broadcast, [msg]

    {:noreply, socket}
  end

  defp push_event(socket, op, data) do
    push socket, @gateway_event, %{
      op: op,
      d: data
    }
  end

  defp error(code, msg) do
    %{
      error_code: code,
      error: msg
    }
  end
end
