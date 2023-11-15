defmodule OrangeCheckr.ProxySocket do
  alias OrangeCheckr.ProxyClient

  defstruct [:client]

  @spec init([any()]) :: {:ok, ProxyClient.t()} | {:stop, {:error, term()}}
  def init(
        http_scheme: http_scheme,
        ws_scheme: ws_scheme,
        host: host,
        port: port,
        path: path
      ) do
    case ProxyClient.connect(http_scheme, ws_scheme, host, port, path) do
      {:ok, client} ->
        state = %__MODULE__{client: client}
        {:ok, state}

      {:error, reason} ->
        {:stop, {:error, reason}}
    end
  end

  defp try_send_text(text, %__MODULE__{client: %{websocket: nil}} = state) do
    Process.send_after(self(), {:retry_send, text}, 10)
    {:ok, state}
  end

  defp try_send_text(text, %__MODULE__{client: client} = state) do
    {:ok, client} = ProxyClient.send_text(client, text)
    {:ok, put_in(state.client, client)}
  end

  def handle_in({text, [opcode: :text]}, state) do
    try_send_text(text, state)
  end

  def handle_info({:retry_send, text}, state) do
    try_send_text(text, state)
  end

  def handle_info(message, state) do
    case ProxyClient.handle_message(state.client, message) do
      {:ok, %{text: text} = client} when text != nil ->
        state = %{state | client: client}
        {:push, {:text, text}, state}

      {:ok, client} ->
        state = %{state | client: client}
        {:ok, state}

      {:close} ->
        {:stop, :normal, state}

      {:error, reason} ->
        IO.inspect({:error, reason})
        {:stop, {:error, reason}}
    end
  end

  def terminate(reason, state) do
    IO.inspect({:terminate, reason})

    if state.client != nil && state.client.websocket != nil do
      ProxyClient.close(state.client)
    end
  end
end
