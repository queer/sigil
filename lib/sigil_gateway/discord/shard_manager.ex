defmodule SigilGateway.Discord.ShardManager do
  @moduledoc false

  require Logger
  
  ## etcd stuff
  @sigil_discord_etcd "sigil-discord"

  def sigil_discord_etcd do
    @sigil_discord_etcd
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
