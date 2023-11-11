defmodule OrangeCheckr.Proxy do
  import Plug.Conn
  alias OrangeCheckr.ProxyServer

  def init(_options) do
    [http_scheme: :http, ws_scheme: :ws, address: "localhost", port: 8008, path: "/"]
  end

  def call(conn, options) do
    case get_req_header(conn, "upgrade") do
      ["websocket" | _] ->
        conn
        |> WebSockAdapter.upgrade(ProxyServer, options, [])
        |> halt()

      _ ->
        target_url =
          to_string(options[:http_scheme]) <>
            "://" <> options[:address] <> ":" <> to_string(options[:port]) <> conn.request_path

        case HTTPoison.get(target_url) do
          {:ok, %HTTPoison.Response{status_code: status_code, body: body, headers: headers}} ->
            conn
            |> put_resp_content_type(get_resp_content_type(headers))
            |> send_resp(status_code, body)

          {:error, _} ->
            send_resp(conn, 502, "Bad Gateway")
        end
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
