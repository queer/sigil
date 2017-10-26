defmodule Sigil.Discord.ShardManager do
  @moduledoc false

  use GenServer

  require Logger

  ## GenServer API

  def start_link(args) do
    GenServer.start_link __MODULE__, args, name: __MODULE__
  end

  def init(shard_count, node_id) do
    # TODO: Should move a lot of this state to etcd...
    state = %{
      last_connect_time: -1,
      shard_count: shard_count,
      last_shard_manager: nil,
      node: node_id
    }

    {:ok, state}
  end

  def handle_cast({:connect_backoff, shard_id, node_id, last_connect_time}, state) do
    state[:last_connect_time] = last_connect_time
    state[:last_shard_manager] = node_id

    {:nreply, state}
  end

  def handle_cast({:connect_finish, last_connect_time}, state) do
    state[:last_connect_time] = last_connect_time
    state[:last_shard_manager] = nil
  end

  # {:whatever, data}, _from, state
  def handle_call({:attempt_connect, bot_name, shard_id}, _from, state) do
    # Attempt to connect the given shard uuid
    unless :os.system_time(:millisecond) - state[:last_connect_time] <= 5000 do
      if state[:last_shard_manager] == nil do
        # Tell other GenServers to not handle any connects
        for node <- Node.list do
          GenServer.cast {__MODULE__, node}, {:connect_backoff, shard_id, state[:node], :os.system_time(:millisecond)}
        end

        # TODO: Find available shards
        {_, next_id} = get_available_shard_id bot_name, state[:shard_count]
        response = case next_id do
          nil -> {:error, "No id available!"}
          _ -> {:ok, next_id}
        end

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
