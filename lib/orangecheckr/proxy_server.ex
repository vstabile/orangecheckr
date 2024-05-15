defmodule OrangeCheckr.ProxyServer do
  alias OrangeCheckr.Types
  alias NostrBasics.Event
  alias OrangeCheckr.Bot
  alias OrangeCheckr.ProxyClient

  defstruct [:relay_uri, :client, :challenge, :pubkey, :collateral?]

  @type t :: %__MODULE__{
          relay_uri: Types.relay_uri(),
          client: ProxyClient.t(),
          challenge: String.t(),
          pubkey: <<_::256>> | nil,
          collateral?: boolean()
        }

  @max_retries 7
  @bad_gateway_code 1014
  @closing_relay_connection_timeout 100
  @proxy_host Application.compile_env(:orangecheckr, :proxy_host, "localhost")

  @spec init(Types.relay_uri()) ::
          {:push, {:text, String.t()}, ProxyClient.t()}
          | {:ok, t()}
          | {:stop, term(), integer(), t()}
  def init(uri) do
    state = %__MODULE__{
      relay_uri: uri,
      challenge: UUID.uuid4(),
      pubkey: nil,
      collateral?: false
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

  defp maybe_send_authentication_message(%__MODULE__{pubkey: nil} = state) do
    {:push, {:text, ~s(["AUTH", "#{state.challenge}"])}, state}
  end

  defp maybe_send_authentication_message(state), do: {:ok, state}

  def handle_in({text, [opcode: :text]}, %{pubkey: nil} = state) do
    with {:ok, ["AUTH", raw_event]} <- Jason.decode(text),
         auth_event <- NostrBasics.Event.decode(raw_event),
         true <- authenticate(auth_event, state) do
      pubkey = auth_event.pubkey
      Bot.ask_for_collateral(pubkey)
      {:push, {:text, ~s(["OK", "#{auth_event.id}", true, ""])}, put_in(state.pubkey, pubkey)}
    else
      {:error, _} ->
        {:push, {:text, ~s(["NOTICE", "Invalid event JSON"])}, state}

      false ->
        {:push, {:text, ~s(["NOTICE", "auth-required: authentication failed"])}, state}

      _ ->
        message = Jason.decode(text)

        case message do
          {:ok, ["REQ", id | _]} ->
            {:push,
             {:text,
              ~s(["CLOSED", "#{id}", "auth-required: we can't serve unauthenticated users"])},
             state}

          {:ok, ["EVENT", raw_event]} ->
            event = NostrBasics.Event.decode(raw_event)

            {:push,
             {:text,
              ~s(["OK", "#{event.id}", false, "auth-required: we only accept events from registered users"])},
             state}

          _ ->
            {:push,
             {:text, ~s(["NOTICE", "auth-required: we can't serve unauthenticated users"])},
             state}
        end
    end
  end

  def handle_in({text, [opcode: :text]}, state) do
    try_send({:text, text}, state)
  end

  def handle_control({payload, [opcode: opcode]}, state) do
    try_send({opcode, payload}, state)
    {:ok, state}
  end

  def handle_info({:retry_send, frame, attempt}, state) do
    try_send(frame, state, attempt + 1)
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
    Process.send_after(self(), {:retry_send, frame, attempt}, 10 * 2 ** attempt)
    {:ok, state}
  end

  defp try_send(frame, %__MODULE__{client: client} = state, _attempt) do
    {:ok, client} = ProxyClient.send_frame(client, frame)
    {:ok, put_in(state.client, client)}
  end

  defp authenticate(%Event{} = event, state) do
    challenge = state.challenge

    with :ok <- NostrBasics.Event.Validator.validate_event(event),
         22242 <- event.kind,
         true <- DateTime.diff(event.created_at, DateTime.utc_now()) |> abs < 10 * 60,
         [_, ^challenge] <- Enum.find(event.tags, fn [tag | _] -> tag == "challenge" end),
         [_, relay_url] <- Enum.find(event.tags, fn [tag | _] -> tag == "relay" end),
         %{host: @proxy_host} <- URI.parse(relay_url) do
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
