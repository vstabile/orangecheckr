defmodule TestRelay do
  import Plug.Conn

  def init(_options), do: []

  def call(conn, options) do
    case get_req_header(conn, "upgrade") do
      ["websocket" | _] ->
        ws(conn, options)

      _ ->
        http(conn, options)
    end
  end

  def ws(conn, options) do
    conn
    |> WebSockAdapter.upgrade(TestSocket, options, [])
    |> halt()
  end

  def http(%{method: "GET", request_path: "/"} = conn, _options) do
    case get_req_header(conn, "accept") do
      ["application/nostr+json"] ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, File.read!("test/fixtures/relay_information.json"))

      _ ->
        conn
        |> send_resp(200, "Please use a Nostr client to connect.")
    end
  end

  def http(conn, _options) do
    conn
    |> send_resp(404, "Cannot GET /invalid")
  end

  def stop(pid) do
    Process.exit(pid, :normal)
  end

  def url(pid, scheme \\ :ws) do
    {:ok, {_host, port}} = ThousandIsland.listener_info(pid)
    "#{scheme}://localhost:#{port}/"
  end
end

defmodule TestSocket do
  def init(state) do
    {:ok, state}
  end

  def handle_in({data, [opcode: :text]}, state) do
    case Jason.decode(data) do
      {:ok, ["REQ", _, _]} ->
        response = File.read!("test/fixtures/subscription_response.json")
        {:push, {:text, response}, state}

      {:ok, ["EVENT", %{id: event_id}]} ->
        ["OK", event_id, true, ""]
        {:ok, state}

      {:ok, ["CLOSE", _]} ->
        {:ok, state}

      {:ok, ["TEST", "close", reason]} ->
        {:stop, String.to_atom(reason), state}

      {:error, _} ->
        message = ["NOTICE", "Invalid JSON"] |> Jason.encode!()
        {:push, {:text, message}, state}
    end
  end

  def terminate(reason, _state) do
    case Registry.lookup(TestRegistry, :test) do
      [{test, _}] -> send(test, {:relay_closed, reason})
      _ -> :ok
    end
  end
end
