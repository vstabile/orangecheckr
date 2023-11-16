defmodule TestClient do
  use WebSockex

  defstruct [:caller, :url, :private_key]

  def start(url) do
    private_key = NostrBasics.Keys.PrivateKey.create()
    state = %__MODULE__{caller: self(), url: url, private_key: private_key}
    WebSockex.start(url, __MODULE__, state)
  end

  def send_message(client, message) do
    WebSockex.cast(client, {:send_message, message})
  end

  def ping(client, payload \\ "") do
    WebSockex.cast(client, {:ping, payload})
  end

  def authenticate(client) do
    {:ok, message} = receive_message(client)
    ["AUTH", challenge] = Jason.decode!(message)
    WebSockex.cast(client, {:authenticate, challenge})
    receive_message(client)
  end

  def ignore_authentication(client) do
    receive do
      {:websocket, ^client, {:text, message}} ->
        case Jason.decode!(message) do
          ["AUTH", _] -> :ok
          _ -> raise "Expected an authentication message"
        end
    after
      100 -> {:error, :timeout}
    end
  end

  def receive_message(client) do
    receive do
      {:websocket, ^client, {:text, message}} -> {:ok, message}
    after
      100 -> {:error, :timeout}
    end
  end

  def ping_received?(client, payload \\ "") do
    receive do
      {:websocket, ^client, {:ping, ^payload}} -> :ok
    after
      100 -> {:error, :timeout}
    end
  end

  def pong_received?(client, payload \\ "") do
    receive do
      {:websocket, ^client, {:pong, ^payload}} -> :ok
    after
      100 -> {:error, :timeout}
    end
  end

  def get_conn(client) do
    WebSockex.cast(client, {:get_conn, self()})

    receive do
      conn = %WebSockex.Conn{} -> conn
    after
      500 -> raise "Didn't receive a Conn"
    end
  end

  def close(client) do
    WebSockex.cast(client, :close)
  end

  # Server callbacks

  def handle_connect(conn, state) do
    {:ok, Map.put(state, :conn, conn)}
  end

  def handle_cast({:send_message, message}, state) do
    {:reply, {:text, message}, state}
  end

  def handle_cast({:ping, payload}, state) do
    {:reply, {:ping, payload}, state}
  end

  def handle_cast({:authenticate, challenge}, state) do
    {:ok, signed_event} =
      %NostrBasics.Event{
        pubkey: NostrBasics.Keys.PublicKey.from_private_key!(state.private_key),
        created_at: DateTime.utc_now(),
        kind: 22242,
        tags: [
          ["relay", state.url],
          ["challenge", challenge]
        ],
        content: ""
      }
      |> NostrBasics.Event.add_id()
      |> NostrBasics.Event.Signer.sign_event(state.private_key)

    message = ~s(["AUTH", #{Jason.encode!(signed_event)}])

    {:reply, {:text, message}, state}
  end

  def handle_cast({:get_conn, client}, %{conn: conn} = state) do
    send(client, conn)
    {:ok, state}
  end

  def handle_cast(:close, state) do
    {:close, state}
  end

  def handle_frame(frame, %{caller: caller} = state) do
    send(caller, {:websocket, self(), frame})

    {:ok, state}
  end

  def terminate(reason, state) do
    send(state.caller, {:client_closed, reason})
  end
end
