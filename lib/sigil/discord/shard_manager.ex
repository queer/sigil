defmodule Sigil.Discord.ShardManager do
  @moduledoc false

  use GenServer

  require Logger

  # Time allowed between shard connects
  @shard_connect_limit 7500
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
      shard_count: nil,
      node: nil
    }

    {:ok, state}
  end

  def handle_call({:handle_reshard, bot_name}, _from, state) do
    Violet.recursive_delete bot_name <> "/heartbeat"
    free_shard_ids Range.new(0, state[:shard_count] - 1) |> Enum.to_list, bot_name

    {:noreply, state}
  end

  def handle_call({:attempt_connect, node_id, bot_name, shard_hash, shard_count}, _from, state) do
    new_state = %{
      node: node_id,
      shard_count: shard_count,
    }
    Logger.info "#{inspect new_state}"

    # If shard count is different, broadcast a full reboot
    if shard_count != state[:shard_count] do
      if state[:shard_count] != nil do
        Logger.info "New shard count, invalidating old shards..."
      for node <- Node.list do
        GenServer.cast {__MODULE__, node}, {:handle_reshard, bot_name}
      end
      handle_call {:handle_reshard, bot_name}, self(), state
      Eden.fanout_exec Sigil.BroadcastTasks, Sigil.Cluster, :handle_broadcast, [%{"t": "discord:reshard"}]
      end
    end

    # Attempt to connect the shard
    unless Violet.is_error?(Violet.get "discord_shard_connecting") do
      Violet.set "discord_shard_connecting", "yes"
      last_shard_connect = Violet.get "discord_last_shard_connect"
      Logger.warn "#{inspect Violet.is_error?(last_shard_connect)}"
      last_connect_time = unless is_nil last_shard_connect or Violet.is_error?(last_shard_connect) do
        last_shard_connect["value"] |> String.to_integer
      else
        -1
      end
      unless :os.system_time(:millisecond) - last_connect_time <= @shard_connect_limit do
        heartbeat_registry = Violet.list_dir bot_name <> "/heartbeat"

        unless is_nil heartbeat_registry do
          now = :os.system_time(:millisecond)
          for shard <- heartbeat_registry do
            heartbeat_shard_id = shard["key"] |> String.split("/") |> List.last
            heartbeat_time = shard["value"] |> String.to_integer
            if now - heartbeat_time >= @shard_free_limit do
              Violet.delete shard["key"]
              free_shard_ids [heartbeat_shard_id], bot_name
              Logger.info "Freed shard id #{inspect heartbeat_shard_id}"
            end
          end
        else
          Logger.warn "No heartbeat registry!?"
          free_shard_ids Range.new(0, shard_count - 1) |> Enum.to_list, bot_name
        end

        # TODO: Check if the incoming id is actually registered

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
        Violet.set "discord_last_shard_connect", end_time |> Integer.to_string

        Violet.delete "/discord_shard_connecting"
        {:reply, {:ok, response}, new_state}
      else
        Violet.delete "/discord_shard_connecting"
        Logger.warn "Shards connecting too fast!"
        {:reply, {:error, "Can't connect yet (too soon)"}, new_state}
      end
    else
      {:reply, {:error, "Other shard manager connecting"}, new_state}
    end
  end

  ## Non-GenServer API starts here

  defp free_shard_ids(id_list, bot_name) do
    shard_info = get_all_shard_info bot_name

    check_ids = id_list
                |> Enum.map(fn(x) ->
                        if is_integer x do
                          Integer.to_string x
                        else
                          x
                        end
                      end)
                |> Enum.to_list

    unless shard_info == nil do
      for shard <- shard_info do
        unless shard["value"] == "null" do
          Logger.info "#{inspect shard}"
          value = unless is_binary shard["value"] do
            Integer.to_string shard["value"]
          else
            shard["value"]
          end

          if check_ids |> Enum.member?(value) do
            Logger.info "Freeing shard #{inspect value}"
            Violet.delete shard["key"]
          else
            Logger.info "Ignoring safe shard #{inspect value}"
          end
        end
      end
    end
    :ok
  end

  defp get_available_shard_id(bot_name, shard_count) do
    shard_info = get_all_shard_info bot_name
    all_ids = Enum.to_list Range.new(0, shard_count - 1)

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
      unless is_nil listing do
        listing
        |> Enum.filter(fn(x) -> is_nil x["dir"] end)
        |> Enum.to_list
      else
        nil
      end
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
