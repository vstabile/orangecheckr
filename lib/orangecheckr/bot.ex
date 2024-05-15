defmodule OrangeCheckr.Bot do
  use GenServer
  alias NostrBasics.Event
  alias NostrBasics.Models.EncryptedDirectMessage
  alias OrangeCheckr.Types
  alias OrangeCheckr.ProxyClient

  defstruct [:relay_uri, :private_key, :client]

  @type t :: %__MODULE__{
          relay_uri: Types.relay_uri(),
          private_key: <<_::256>>,
          client: ProxyClient.t()
        }

  @max_retries 7

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def ask_for_collateral(pubkey) do
    GenServer.cast(__MODULE__, {:ask_for_collateral, pubkey})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      relay_uri: opts.relay_uri,
      private_key: opts.private_key
    }

    case ProxyClient.connect(state.relay_uri) do
      {:ok, client} ->
        {:ok, put_in(state.client, client)}

      {:error, _reason, _client} ->
        {:stop, "The bot was unable to connect to the relay."}
    end
  end

  @impl true
  def handle_info({:retry_send, frame, attempt}, state) do
    try_send(frame, state, attempt + 1)
  end

  @impl true
  def handle_info(message, state) do
    case ProxyClient.handle_message(state.client, message) do
      {:ok, %{frame: frame} = client} when frame != nil ->
        {:noreply, put_in(state.client, client)}

      {:ok, client} ->
        {:noreply, put_in(state.client, client)}

      {:close, _code, _client} ->
        {:stop, :normal, state}

      {:error, reason, _client} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:ask_for_collateral, pubkey}, state) do
    {:ok, collateral_request_event} =
      %EncryptedDirectMessage{
        content: "Gimme some collateral!!!",
        remote_pubkey: pubkey
      }
      |> EncryptedDirectMessage.to_event(state.private_key)

    {:ok, collateral_request_event} =
      put_in(collateral_request_event.created_at, DateTime.utc_now())
      |> Event.add_id()
      |> Event.Signer.sign_event(state.private_key)

    message = ~s(["EVENT", #{Jason.encode!(collateral_request_event)}])

    try_send({:text, message}, state)
  end

  defp try_send(frame, state, attempt \\ 0)

  defp try_send(_frame, %__MODULE__{client: %{websocket: nil}} = state, attempt)
       when attempt == @max_retries do
    {:noreply, state}
  end

  defp try_send(frame, %__MODULE__{client: %{websocket: nil}} = state, attempt) do
    Process.send_after(self(), {:retry_send, frame, attempt}, 10 * 2 ** attempt)
    {:noreply, state}
  end

  defp try_send(frame, %__MODULE__{client: client} = state, _attempt) do
    {:ok, client} = ProxyClient.send_frame(client, frame)
    {:noreply, put_in(state.client, client)}
  end
end
