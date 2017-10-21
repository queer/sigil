defmodule SigilGateway.Etcd do
  @moduledoc """
  See https://coreos.com/etcd/docs/latest/v2/api.html
  """
  
  @etcd_url Application.get_env(:sigil_gateway, "ETCD_URL", "http://localhost:2379")
  @etcd_api @etcd_url <> "/v2"

  def is_error(body) do
    body["errorCode"] == nil
  end

  def get_version do
    etcd_res = @etcd_url <> "/version"
               |> HTTPotion.get
    Poison.decode!(etcd_res.body)
  end

  def make_dir(dir) do
    res = HTTPotion.put @etcd_api <> "/keys/" <> dir, [body: "dir=true"]
    Poison.decode! res.body
  end

  def list_dir(dir) do
    res = HTTPotion.get @etcd_api <> "/keys/" <> dir
    Poison.decode! res.body
  end

  defp handle_encode(data) do
    unless is_binary data do
      Poison.encode! data
    else
      data
    end
  end

  def set(key, value) do
    HTTPotion.put @etcd_api <> "/keys/" <> key, [body: "value=#{inspect handle_encode(value)}"]
  end

  def get(key) do
    res = HTTPotion.get @etcd_api <> "/keys/" <> key
    Poison.decode! res.body
  end

  def get_value(key) do
    get(key)["node"]["value"]
  end
end
