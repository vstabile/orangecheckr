defmodule OrangeCheckr.TestRelay.Router do
  import Plug.Conn

  def init(options), do: options

  def call(%{request_path: "/"} = conn, options) do
    case get_req_header(conn, "upgrade") do
      ["websocket" | _] ->
        upgrade(conn, options)

      _ ->
        handle_http(conn)
    end
  end

  def call(conn, _), do: send_resp(conn, 404, "Not found.")

  def upgrade(conn, options) do
    conn
    |> delay(options)
    |> WebSockAdapter.upgrade(TestRelay.Server, [], [])
    |> halt()
  end

  def handle_http(conn) do
    case get_req_header(conn, "accept") do
      ["application/nostr+json"] ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, File.read!("test/fixtures/relay_information.json"))

      _ ->
        send_resp(conn, 200, "Please use a Nostr client to connect.")
    end
  end

  # Simulate a delay when the proxy is connecting to the relay
  def delay(conn, delay: delay) do
    Process.sleep(delay)
    conn
  end

  def delay(conn, _), do: conn

  def url(pid, scheme \\ :ws) do
    {:ok, {_host, port}} = ThousandIsland.listener_info(pid)
    "#{scheme}://localhost:#{port}/"
  end
end

defmodule TestRelay.Server do
  def init(_state) do
    test =
      case Registry.lookup(OrangeCheckr.TestRegistry, :test) do
        [{test, _}] ->
          # Enable tests to send messages to the socket
          send(test, {:relay_connected, self()})
          test

        [] ->
          nil
      end

    {:ok, test}
  end

  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, ["REQ", _, _]} ->
        response = File.read!("test/fixtures/subscription_response.json")
        {:push, {:text, response}, state}

      {:ok, ["EVENT", %{"id" => event_id}]} ->
        response = Jason.encode!(["OK", event_id, true, ""])
        {:push, {:text, response}, state}

      {:ok, ["CLOSE", _]} ->
        {:ok, state}

      {:error, _} ->
        message = ~s(["NOTICE", "Invalid JSON"])
        {:push, {:text, message}, state}
    end
  end

  def handle_control(_frame, nil), do: {:ok, nil}

  def handle_control(frame, test) do
    case frame do
      {_, [opcode: :ping]} -> send(test, :relay_ping_received)
      {_, [opcode: :pong]} -> send(test, :relay_pong_received)
      _ -> :ok
    end

    {:ok, test}
  end

  def terminate(reason, test) do
    send(test, {:relay_closed, reason})
  end

  # Process testing commandas

  def handle_info({:test, :ping, payload}, state) do
    {:push, {:ping, payload}, state}
  end

  def handle_info({:test, :close, code, reason}, state) do
    {:stop, reason, code, state}
  end
end
