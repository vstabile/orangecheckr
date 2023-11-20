defmodule OrangeCheckr.ProxySocket do
  alias OrangeCheckr.Types
  alias NostrBasics.Event
  alias OrangeCheckr.ProxyClient

  defstruct [:relay_uri, :client, :auth?, :challenge]

  @type t :: %__MODULE__{
          relay_uri: Types.relay_uri(),
          client: ProxyClient.t(),
          auth?: boolean(),
          challenge: String.t()
        }

  @max_retries 7
  @bad_gateway_code 1014
  @closing_relay_connection_timeout 100

  @spec init(Types.relay_uri()) ::
          {:push, {:text, String.t()}, ProxyClient.t()}
          | {:ok, t()}
          | {:stop, term(), integer(), t()}
  def init(relay_uri) do
    state = %__MODULE__{
      relay_uri: relay_uri,
      auth?: false,
      challenge: UUID.uuid4()
    }

    connect_to_relay(state)
  end

  def connect_to_relay(state) do
    case ProxyClient.connect(state.relay_uri) do
      {:ok, client} ->
        state = put_in(state.client, client)
        maybe_send_authentication_message(state)

      {:error, _reason, client} ->
        {:stop, :shutdown, @bad_gateway_code, put_in(state.client, client)}
    end
  end

  defp maybe_send_authentication_message(%__MODULE__{auth?: false} = state) do
    {:push, {:text, ~s(["AUTH", "#{state.challenge}"])}, state}
  end

  defp maybe_send_authentication_message(state), do: {:ok, state}

  def handle_in({text, [opcode: :text]}, %{auth?: false} = state) do
    with {:ok, ["AUTH", raw_event]} <- Jason.decode(text),
         auth_event <- NostrBasics.Event.decode(raw_event),
         true <- authenticate(auth_event, state) do
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

      {:close, code, client} ->
        state = put_in(state.client, client)
        reconnect_or_close(code, state)

      {:error, reason, client} ->
        {:stop, {:error, reason}, @bad_gateway_code, put_in(state.client, client)}
    end
  end

  defp try_send(frame, state, attempt \\ 0)

  defp try_send(_frame, %__MODULE__{client: %{websocket: nil}} = state, attempt)
       when attempt == @max_retries do
    {:stop, :normal, @bad_gateway_code, state}
  end

  defp try_send(frame, %__MODULE__{client: %{websocket: nil}} = state, attempt) do
    Process.send_after(self(), {:retry_send, frame}, 10 * 2 ** attempt)
    {:ok, state}
  end

  defp try_send(frame, %__MODULE__{client: client} = state, _attempt) do
    {:ok, client} = ProxyClient.send_frame(client, frame)
    {:ok, put_in(state.client, client)}
  end

  defp authenticate(%Event{} = event, state) do
    challenge = state.challenge
    host = state.relay_uri.host

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

  def terminate(_reason, %__MODULE__{client: %{conn: nil}}), do: nil

  def terminate(_reason, %__MODULE__{client: %{conn: %{state: :closed}}}), do: nil

  def terminate(_reason, %__MODULE__{client: client}), do: close_relay_connection(client)

  defp reconnect_or_close(4000, state) do
    # Do not try to reconnect (NIP-01)
    {:stop, :normal, 4000, state}
  end

  defp reconnect_or_close(_code, state) do
    connect_to_relay(state)
  end

  defp close_relay_connection(%{websocket: nil, conn: %{state: :open}} = client) do
    receive do
      message ->
        case ProxyClient.handle_message(client, message) do
          {:ok, client} -> close_relay_connection(client)
          _ -> close_relay_connection(client)
        end
    after
      @closing_relay_connection_timeout ->
        IO.inspect("Relay connection timed out")
    end
  end

  defp close_relay_connection(client), do: ProxyClient.close(client)
end
