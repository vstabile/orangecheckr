defmodule OrangeCheckr.ProxyServer do
  alias OrangeCheckr.ProxyClient

  defstruct [:client]

  @spec init([any()]) :: {:ok, ProxyClient.t()} | {:stop, {:error, term()}}
  def init(
        http_scheme: http_scheme,
        ws_scheme: ws_scheme,
        address: address,
        port: port,
        path: path
      ) do
    case ProxyClient.connect(http_scheme, ws_scheme, address, port, path) do
      {:ok, client} ->
        state = %__MODULE__{client: client}
        {:ok, state}

      {:error, reason} ->
        {:stop, {:error, reason}}
    end
  end

  def handle_in({data, [opcode: :text]}, state) do
    {:ok, client} = ProxyClient.send_text(state.client, data)
    {:ok, put_in(state.client, client)}
  end

  def handle_info(message, state) do
    case ProxyClient.handle_message(state.client, message) do
      {:ok, %{text: text} = client} when text != nil ->
        state = %{state | client: client}
        {:push, state, {:text, text}}

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
    ProxyClient.close(state.client)
  end
end
