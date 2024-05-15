defmodule OrangeCheckr.Router do
  import Plug.Conn
  alias Orangecheckr.Utils
  alias OrangeCheckr.ProxyServer

  def init(opts) do
    opts
  end

  def call(%{request_path: request_path} = conn, %{uri: uri, proxy_path: proxy_path})
      when request_path == proxy_path do
    case get_req_header(conn, "upgrade") do
      ["websocket" | _] ->
        upgrade(conn, uri)

      _ ->
        handle_http(conn, uri)
    end
  end

  def call(%{request_path: request_path} = conn, %{uri: uri, favicon_path: favicon_path})
      when request_path == favicon_path do
    http_scheme = Utils.ws_to_http_scheme(uri.scheme)

    http_url =
      "#{http_scheme}://#{uri.host}:#{uri.port}#{conn.request_path}"

    case HTTPoison.get(http_url, conn.req_headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, _} ->
        {:ok, file} = File.read("assets/favicon.ico")
        send_resp(conn, 200, file)

      {:error, _} ->
        send_resp(conn, 502, "Bad Gateway")
    end
  end

  def call(conn, %{proxy_path: proxy_path}) do
    send_resp(conn, 404, "Not found. Relay path is #{proxy_path}")
  end

  defp upgrade(conn, uri) do
    conn
    |> WebSockAdapter.upgrade(ProxyServer, uri, [])
    |> halt()
  end

  defp handle_http(conn, uri) do
    http_scheme = Utils.ws_to_http_scheme(uri.scheme)

    http_url =
      "#{http_scheme}://#{uri.host}:#{uri.port}#{conn.request_path}"

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
