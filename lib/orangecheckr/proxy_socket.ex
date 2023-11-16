defmodule OrangeCheckr.ProxySocket do
  alias NostrBasics.Event
  alias OrangeCheckr.ProxyClient

  defstruct [:host, :client, :auth?, :challenge]

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
        challenge = UUID.uuid4()
        state = %__MODULE__{host: host, client: client, auth?: false, challenge: challenge}
        {:push, {:text, ~s(["AUTH", "#{challenge}"])}, state}

      {:error, reason} ->
        {:stop, {:error, reason}}
    end
  end

  def handle_in({text, [opcode: :text]}, %{auth?: false} = state) do
    with {:ok, ["AUTH", raw_event]} <- Jason.decode(text),
         auth_event <- NostrBasics.Event.decode(raw_event),
         true <- authenticate(auth_event, state.challenge, state.host) do
      {:push, {:text, ~s(["NOTICE", "Authenticated"])}, put_in(state.auth?, true)}
    else
      {:error, _} ->
        {:push, {:text, ~s(["NOTICE", "Invalid event JSON"])}, state}

      false ->
        {:push, {:text, ~s(["NOTICE", "restricted: authentication failed"])}, state}

      _ ->
        {:push,
         {:text,
          ~s(["NOTICE", "restricted: we can't serve unauthenticated users, does your client implement NIP-42?"])},
         state}
    end
  end

  def handle_in({text, [opcode: :text]}, %{auth?: true} = state) do
    try_send({:text, text}, state)
  end

  def handle_control({payload, [opcode: opcode]}, state) do
    try_send({opcode, payload}, state)
    {:ok, state}
  end

  def handle_info({:retry_send, frame}, state) do
    try_send(frame, state)
  end

  def handle_info(message, state) do
    case ProxyClient.handle_message(state.client, message) do
      {:ok, %{frame: frame} = client} when frame != nil ->
        {:push, frame, put_in(state.client, client)}

      {:ok, client} ->
        {:ok, put_in(state.client, client)}

      {:close, client} ->
        {:stop, :normal, put_in(state.client, client)}

      {:error, reason} ->
        IO.inspect({:error, reason})
        {:stop, {:error, reason}}
    end
  end

  defp try_send(frame, %__MODULE__{client: %{websocket: nil}} = state) do
    Process.send_after(self(), {:retry_send, frame}, 10)
    {:ok, state}
  end

  defp try_send(frame, %__MODULE__{client: client} = state) do
    {:ok, client} = ProxyClient.send_frame(client, frame)
    {:ok, put_in(state.client, client)}
  end

  defp authenticate(%Event{} = event, challenge, host) do
    with :ok <- NostrBasics.Event.Validator.validate_event(event),
         22242 <- event.kind,
         true <- DateTime.diff(event.created_at, DateTime.utc_now()) |> abs < 10 * 60,
         [_, ^challenge] <- Enum.find(event.tags, fn [tag | _] -> tag == "challenge" end),
         [_, relay_url] <- Enum.find(event.tags, fn [tag | _] -> tag == "relay" end),
         %{host: ^host} <- URI.parse(relay_url) do
      true
    else
      _ -> false
    end
  end

  def terminate(_reason, %__MODULE__{client: %{websocket: websocket, conn: %{state: state}}})
      when websocket != nil or state == :closed do
  end

  def terminate(_reason, %__MODULE__{client: client}) do
    close_relay_connection(client)
  end

  defp close_relay_connection(%{websocket: nil} = client) do
    receive do
      message ->
        case ProxyClient.handle_message(client, message) do
          {:ok, client} -> close_relay_connection(client)
          _ -> close_relay_connection(client)
        end
    end
  end

  defp close_relay_connection(client), do: ProxyClient.close(client)
end
