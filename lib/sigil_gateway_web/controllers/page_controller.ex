defmodule SigilGatewayWeb.PageController do
  use SigilGatewayWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
