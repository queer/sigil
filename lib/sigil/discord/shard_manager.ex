defmodule Sigil.Discord.ShardManager do
  @moduledoc false

  use GenServer

  require Logger

  ## GenServer API

  def start_link(initial_state) do
    GenServer.start_link __MODULE__, initial_state, name: __MODULE__
  end

  def init(initial_state) do
    # TODO: Should move a lot of this state to etcd...
    Logger.info "Initial state: #{inspect initial_state}"
    state = %{
      last_connect_time: -1,
      shard_count: nil,
      last_shard_manager: nil,
      node: nil
    }

    {:ok, state}
  end

  def handle_cast({:connect_backoff, node_id, last_connect_time}, state) do
    Map.replace(state, :last_connect_time, last_connect_time)
    Map.replace(state, :last_shard_manager, node_id)

    {:noreply, state}
  end

  def handle_cast({:connect_finish, last_connect_time}, state) do
    Map.replace(state, :last_connect_time, last_connect_time)
    Map.replace(state, :last_shard_manager, nil)
  end

  # {:whatever, data}, _from, state
  def handle_call({:attempt_connect, bot_name, node_id, shard_count}, _from, state) do
    if is_nil state[:node] do
      Logger.info "Updating shard manager with node id #{inspect node_id}"
      Map.replace(state, :node, node_id)
    end
    if is_nil state[:shard_count] or state[:shard_count] != shard_count do
      Logger.info "Updating shard manager with node id #{inspect shard_count}"
      Map.replace(state, :shard_count, shard_count)
    end
    # Attempt to connect the given shard uuid
    unless :os.system_time(:millisecond) - state[:last_connect_time] <= 5000 do
      if state[:last_shard_manager] == nil do
        # Tell other GenServers to not handle any connects
        for node <- Node.list do
          GenServer.cast {__MODULE__, node}, {:connect_backoff, state[:node], :os.system_time(:millisecond)}
        end

        {_, next_id} = get_available_shard_id bot_name, state[:shard_count]
        response = case next_id do
          nil -> {:error, "No id available!"}
          _ -> {:ok, next_id}
        end
        Logger.info "Connecting #{bot_name} shard #{inspect next_id}"

        # Free up other connected GenServers
        for node <- Node.list do
          GenServer.cast {__MODULE__, node}, {:connect_finish, :os.system_time(:millisecond)}
        end

        {:reply, response, state}
      else
        {:error, "Other shard manager connecting"}
      end
    else
      {:error, "Can't connect yet (too soon)"}
    end
  end

  ## Non-GenServer API starts here
  
  ## etcd stuff
  @sigil_discord_etcd "sigil-discord"

  def sigil_discord_etcd do
    @sigil_discord_etcd
  end

  defp get_available_shard_id(bot_name, shard_count) do
    # TODO: Work out resharding
    shard_info = get_all_shard_info bot_name
    all_ids = Enum.to_list 0..shard_count
    unless shard_info == nil do
      for shard <- shard_info do
        registered_id = shard["value"]
        unless registered_id == "null" do
          all_ids |> List.delete(registered_id)
        end
      end
      next_id = List.first all_ids
      case next_id do
        nil -> {:error, "No available ids"}
        _ -> {:ok, next_id}
      end
    else
      {:error, "No available ids"}
    end
      
  end

  defp get_all_shard_info(bot_name) do
    # Conveniently, each node has both the key AND the value.
    # This data structure looks something like
    # "nodes": [
    #   {
    #     "key": "/foo_dir",
    #     "dir": true,
    #     "modifiedIndex": 2,
    #     "createdIndex": 2
    #   },
    #   {
    #     "key": "/foo",
    #     "value": "two",
    #     "modifiedIndex": 1,
    #     "createdIndex": 1
    #   }
    # ]
    etcd_dir = @sigil_discord_etcd <> "/" <> bot_name

    # Enumerate sigil-discord, check if something with this id has been registered
    listing = Violet.list_dir etcd_dir
    if Violet.is_error? listing do
      # Getting an error code means that it doesn't exist, so we create it
      Logger.info "Creating #{inspect etcd_dir} because it doesn't exist..."
      Violet.make_dir(etcd_dir)
      nil
    else
      listing["node"]["nodes"]
    end
  end

  def is_shard_registered?(bot_name, id) do
    all_shards = get_all_shard_info bot_name
    case all_shards do
      nil -> false
      _ -> case find_registered_shard all_shards, id do
        nil -> false
        _ -> true
      end
    end
  end

  defp find_registered_shard(all_shards, id) do
    matches = Enum.filter(all_shards, fn(shard) -> String.ends_with? shard["key"], id end)
    case length matches do
      0 -> nil
      _ -> hd matches
    end
  end
end
