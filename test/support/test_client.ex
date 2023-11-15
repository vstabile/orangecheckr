defmodule TestClient do
  use WebSockex

  def start(url) do
    WebSockex.start(url, __MODULE__, %{caller: self()})
  end

  def send_message(client, message) do
    WebSockex.cast(client, {:send_message, message})
  end

  def receive_message(client) do
    receive do
      {:websocket, ^client, message} -> {:ok, message}
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

  def handle_connect(conn, state) do
    {:ok, Map.put(state, :conn, conn)}
  end

  def handle_cast({:send_message, message}, state) do
    {:reply, {:text, message}, state}
  end

  def handle_cast({:get_conn, client}, %{conn: conn} = state) do
    send(client, conn)
    {:ok, state}
  end

  def handle_cast(:close, state) do
    {:close, state}
  end

  def handle_frame({:text, message}, %{caller: caller} = state) do
    send(caller, {:websocket, self(), message})

    {:ok, state}
  end

  def terminate(reason, state) do
    send(state[:caller], {:client_closed, reason})
  end
end
