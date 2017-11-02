defmodule Sigil.Discord.ShardManager do
  @moduledoc false

  use GenServer

  require Logger

  # Time allowed between shard connects
  @shard_connect_limit 5000
  # Time allowed before a shard id is freed up
  @shard_free_limit 15000

  ## GenServer API

  def start_link() do
    GenServer.start_link __MODULE__, :ok, name: __MODULE__
  end

  def init(:ok) do
    Logger.info "(re)starting discord shard manager..."
    # TODO: Should move a lot of this state to etcd...
    Logger.info "Starting shard manager..."
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
  def handle_call({:attempt_connect, node_id, bot_name, shard_hash, shard_count}, _from, state) do
    new_state = %{
      last_connect_time: state[:last_connect_time],
      node: node_id,
      shard_count: shard_count,
      last_shard_manager: nil
    }
    Logger.info "#{inspect new_state}"
    
    # TODO: If shard count is different, broadcast a full reboot

    # Attempt to connect the given shard uuid
    unless :os.system_time(:millisecond) - new_state[:last_connect_time] <= @shard_connect_limit do
      if new_state[:last_shard_manager] == nil do
        # TODO: Prune shard heartbeat mappings
        heartbeat_registry = Violet.list_dir bot_name <> "/heartbeat"

        unless is_nil heartbeat_registry do
          now = :os.system_time(:millisecond)
          for shard <- heartbeat_registry do
            heartbeat_shard_id = shard["key"] |> String.split("/") |> List.last
            heartbeat_time = shard["value"] |> String.to_integer
            if now - heartbeat_time >= @shard_free_limit do
              Violet.delete shard["key"]
              Logger.info "Freed shard id #{inspect heartbeat_shard_id}"
            end
          end
        else
          Logger.warn "No heartbeat registry!?"
        end

        # Tell other GenServers to not handle any connects
        for node <- Node.list do
          GenServer.cast {__MODULE__, node}, {:connect_backoff, new_state[:node], :os.system_time(:millisecond)}
        end

        {shard_status, next_id} = get_available_shard_id bot_name, new_state[:shard_count]
        # TODO: Maintain state in etcd?

        response = case shard_status do
          :ok -> next_id
          :error -> nil
        end

        unless is_nil response do
          Logger.info "Connecting #{bot_name} shard #{inspect next_id}"
          Violet.set bot_name <> "/" <> shard_hash, next_id
        else
          msg = next_id
          Logger.warn "Couldn't connect: #{msg}"
        end

        end_time = :os.system_time(:millisecond)
        # Free up other connected GenServers
        for node <- Node.list do
          GenServer.cast {__MODULE__, node}, {:connect_finish, end_time}
        end

        {:reply, {:ok, response}, %{new_state | last_connect_time: end_time}}
      else
        Logger.warn "Other shard manager connecting!"
        {:reply, {:error, "Other shard manager connecting"}, new_state}
      end
    else
      Logger.warn "Shards connecting too fast!"
      {:reply, {:error, "Can't connect yet (too soon)"}, new_state}
    end
  end

  ## Non-GenServer API starts here

  defp free_shard_ids(id_list) do
    shard_info = get_all_shard_info bot_name
    all_ids = Enum.to_list 0..shard_count


    unless shard_info == nil do
      registered_ids = shard_info
                       |> Enum.map(fn(x) -> x["value"] end)
                       |> Enum.filter(fn(x) -> x != "null" end)
                       |> Enum.filter(fn(x) -> x != -1 end)
                       |> Enum.filter(fn(x) -> not is_nil x end)
                       |> Enum.map(fn(x) -> unless is_integer x do String.to_integer x else x end end)
                       |> Enum.to_list

      available_ids = all_ids
                      |> Enum.reject(fn(x) -> x in registered_ids end)
                      |> Enum.to_list 
      Logger.info "All:        #{inspect all_ids}"
      Logger.info "Registered: #{inspect registered_ids}"
      Logger.info "Available:  #{inspect available_ids}"

      next_id = List.first available_ids
      case next_id do
        nil -> {:error, "No available ids"}
        _ -> {:ok, next_id}
      end
    else
      # If there is no available data, give back shard id 0
      {:ok, 0}
    end
    :ok
  end

  defp get_available_shard_id(bot_name, shard_count) do
    # TODO: Work out resharding
    shard_info = get_all_shard_info bot_name
    all_ids = Enum.to_list 0..shard_count


    unless shard_info == nil do
      registered_ids = shard_info
                       |> Enum.map(fn(x) -> x["value"] end)
                       |> Enum.filter(fn(x) -> x != "null" end)
                       |> Enum.filter(fn(x) -> x != -1 end)
                       |> Enum.filter(fn(x) -> not is_nil x end)
                       |> Enum.map(fn(x) -> unless is_integer x do String.to_integer x else x end end)
                       |> Enum.to_list

      available_ids = all_ids
                      |> Enum.reject(fn(x) -> x in registered_ids end)
                      |> Enum.to_list 
      Logger.info "All:        #{inspect all_ids}"
      Logger.info "Registered: #{inspect registered_ids}"
      Logger.info "Available:  #{inspect available_ids}"

      next_id = List.first available_ids
      case next_id do
        nil -> {:error, "No available ids"}
        _ -> {:ok, next_id}
      end
    else
      # If there is no available data, give back shard id 0
      {:ok, 0}
    end
  end

  defp get_all_shard_info(bot_name) do
    etcd_dir = bot_name

    # Enumerate sigil-discord, check if something with this id has been registered
    listing = Violet.list_dir etcd_dir
    if Violet.is_error? listing do
      # Getting an error code means that it doesn't exist, so we create it
      Logger.info "Creating #{inspect etcd_dir} because it doesn't exist..."
      Violet.make_dir(etcd_dir)
      nil
    else
      listing
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
