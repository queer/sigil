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

  @dispatch_gateway_info "gateway:info"

  @dispatch_error "gateway:error"

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
      Violet.set bot_name <> "/" <> shard_id, "null"
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
    Logger.info "Got gateway message: #{inspect msg}"
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
    data = msg["d"]
    Logger.info "Got heartbeat from #{inspect data["id"]}, shard #{inspect data["shard"]}"

    # This means:
    # - {"op": 0, "d": {"id": "11-22-33-44", "bot_name": "memes", shard": 5}}
    # - Just stuff it into etcd_dir/heartbeat_time/id => :os.system_time(:millisecond)
    # - When getting next shard id, simply check for things in 
    #   there that need pruning first
    bot_name = data["bot_name"]
    heartbeat_registry = Violet.list_dir bot_name <> "/heartbeat"
    if is_nil heartbeat_registry do
      Violet.make_dir bot_name <> "/heartbeat"
    end

    Violet.set bot_name <> "/heartbeat/" <> Integer.to_string(data["shard"]), :os.system_time(:millisecond) |> Integer.to_string

    {:noreply, socket}
  end

  defp handle_dispatch(msg, socket) do
    type = msg["t"]
    data = msg["d"]
    case type do
      nil -> push_event socket, @op_dispatch,
               error(@error_no_event_type, "no event type specified")
      @dispatch_discord_shard -> handle_shard_request msg, data, socket
      @dispatch_gateway_info -> handle_info_request msg, data, socket
      _ -> Logger.info "dispatch data: #{inspect data}"
    end
    {:noreply, socket}
  end

  defp handle_info_request(msg, d, socket) do
    version = Sigil.Application.version()
    etcd_stats = Violet.stats()

    push_dispatch socket, @dispatch_gateway_info, %{
      version: version,
      etcd: etcd_stats
    }

    {:noreply, socket}
  end

  defp handle_shard_request(msg, d, socket) do
    cond do
      is_nil d["bot_name"] -> push_event socket, @op_dispatch, 
          error(@error_missing_data, "no bot name given")
      is_nil d["shard_count"] -> push_event socket, @op_dispatch, 
          error(@error_missing_data, "no shard count given")
      true -> send_shard_data msg, d, socket
    end

    {:noreply, socket}
  end

  defp send_shard_data(msg, d, socket) do
    {res, data} = GenServer.call Sigil.Discord.ShardManager, 
        {:attempt_connect, GenServer.call(Eden, :get_hash), d["bot_name"], d["id"], d["shard_count"]},
        :infinity # Don't timeout waiting for response, as we might be waiting a while for the lock
    case res do
      :error -> push_dispatch socket, @dispatch_error, error(@error_generic, data)
      :ok -> push_dispatch socket, @dispatch_discord_shard, %{
        shard_id: data,
        shard_count: d["shard_count"],
        bot_name: d["bot_name"]
      }
    end
  end

  defp handle_broadcast(msg, socket) do
    Eden.fanout_exec Sigil.BroadcastTasks, Sigil.Cluster, :handle_broadcast, [msg]

    {:noreply, socket}
  end

  defp push_dispatch(socket, type, data) do
    push socket, @gateway_event, %{
      op: @op_dispatch,
      t: type,
      d: data
    }
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
