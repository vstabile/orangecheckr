defmodule OrangeCheckr.ProxyServer do
  import Plug.Conn
  alias OrangeCheckr.ProxySocket

  def init(_options) do
    relay_uri = Application.get_env(:orangecheckr, :relay_uri)
    %{scheme: scheme, host: host, port: port, path: path} = URI.parse(relay_uri)

    {http_scheme, ws_scheme} =
      case scheme do
        "http" -> {:http, :ws}
        "ws" -> {:http, :ws}
        "https" -> {:https, :wss}
        "wss" -> {:https, :wss}
        _ -> raise "Invalid scheme: #{inspect(scheme)}"
      end

    [http_scheme: http_scheme, ws_scheme: ws_scheme, host: host, port: port, path: path || "/"]
  end

  def call(conn, options) do
    case get_req_header(conn, "upgrade") do
      ["websocket" | _] ->
        upgrade(conn, options)

      _ ->
        bypass(conn, options)
    end
  end

  defp upgrade(conn, options) do
    conn
    |> WebSockAdapter.upgrade(ProxySocket, options, [])
    |> halt()
  end

  defp bypass(conn, options) do
    target_url =
      to_string(options[:http_scheme]) <>
        "://" <> options[:host] <> ":" <> to_string(options[:port]) <> conn.request_path

    case HTTPoison.get(target_url, conn.req_headers) do
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
