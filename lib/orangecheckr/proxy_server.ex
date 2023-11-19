defmodule OrangeCheckr.ProxyServer do
  import Plug.Conn
  alias Orangecheckr.Utils
  alias OrangeCheckr.ProxySocket
  alias OrangeCheckr.Types

  @spec init(any()) :: Types.relay_uri()
  def init(_options) do
    Application.get_env(:orangecheckr, :relay_uri)
    |> URI.parse()
    |> Map.from_struct()
    |> Map.drop([:authority, :query, :fragment, :userinfo])
    |> Map.update(:scheme, :wss, &String.to_atom/1)
    |> Map.update(:path, "/", fn path -> path || "/" end)
  end

  def call(conn, uri) do
    case get_req_header(conn, "upgrade") do
      ["websocket" | _] ->
        upgrade(conn, uri)

      _ ->
        http(conn, uri)
    end
  end

  defp upgrade(conn, uri) do
    conn
    |> WebSockAdapter.upgrade(ProxySocket, uri, [])
    |> halt()
  end

  defp http(conn, uri) do
    http_scheme = Utils.ws_to_http_scheme(uri.scheme)
    http_url = "#{http_scheme}://#{uri.host}:#{uri.port}#{conn.request_path}"

    case HTTPoison.get(http_url, conn.req_headers) do
      {:ok, %HTTPoison.Response{status_code: status_code, body: body, headers: headers}} ->
        conn
        |> put_resp_content_type(get_resp_content_type(headers))
        |> send_resp(status_code, body)

      {:error, _} ->
        send_resp(conn, 502, "Bad Gateway")
    end
  end

  defp get_resp_content_type(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "content-type" end)
    |> case do
      nil -> "application/octet-stream"
      {_, content_type} -> content_type
    end
  end
end
