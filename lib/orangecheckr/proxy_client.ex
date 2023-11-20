defmodule OrangeCheckr.ProxyClient do
  alias OrangeCheckr.Types
  alias Orangecheckr.Utils
  require Logger

  @type frame :: Mint.WebSocket.frame() | Mint.WebSocket.short_hand_frame()

  @type t :: %__MODULE__{
          conn: Mint.HTTP.t(),
          websocket: Mint.WebSocket.t() | nil,
          request_ref: reference() | nil,
          status: Mint.Types.status() | nil,
          resp_headers: Mint.Types.headers() | nil,
          relay_closing?: boolean(),
          error_closing?: boolean(),
          close_code: integer() | nil,
          frame: frame() | nil
        }

  defstruct [
    :conn,
    :websocket,
    :request_ref,
    :status,
    :resp_headers,
    :relay_closing?,
    :error_closing?,
    :close_code,
    :frame
  ]

  @bad_gateway_code 1014
  @going_away_code 1001

  @spec connect(Types.relay_uri()) :: {:ok, t()} | {:error, term(), t()}
  def connect(uri) do
    http_scheme = Utils.ws_to_http_scheme(uri.scheme)

    state = %__MODULE__{
      conn: nil,
      request_ref: nil,
      relay_closing?: false,
      error_closing?: false
    }

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, uri.port),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(uri.scheme, conn, uri.path, []) do
      state = %{state | conn: conn, request_ref: ref}
      {:ok, state}
    else
      {:error, reason} ->
        {:error, reason, state}

      {:error, conn, %{reason: reason}} ->
        {:error, reason, put_in(state.conn, conn)}
    end
  end

  @spec handle_message(t(), term()) ::
          {:ok, t()} | {:close, integer(), t()} | {:error, term(), t()}
  def handle_message(state, message) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = %{state | conn: conn, frame: nil} |> handle_responses(responses)
        if state.relay_closing?, do: close(state), else: {:ok, state}

      {:error, _conn, reason, _responses} ->
        state = put_in(state.error_closing?, true)
        {:error, reason, state}

      :unknown ->
        state = put_in(state.error_closing?, true)
        {:error, :unknown, state}
    end
  end

  @spec send_frame(t(), frame()) ::
          {:ok, t()} | {:error, t(), any()}
  def send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         state = put_in(state.websocket, websocket),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
      {:ok, put_in(state.conn, conn)}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} ->
        {:error, reason, put_in(state.websocket, websocket)}

      {:error, conn, reason} ->
        {:error, reason, put_in(state.conn, conn)}
    end
  end

  defp handle_responses(state, responses)

  defp handle_responses(%{request_ref: ref} = state, [{:status, ref, status} | rest]) do
    put_in(state.status, status)
    |> handle_responses(rest)
  end

  defp handle_responses(%{request_ref: ref} = state, [{:headers, ref, resp_headers} | rest]) do
    put_in(state.resp_headers, resp_headers)
    |> handle_responses(rest)
  end

  defp handle_responses(%{request_ref: ref} = state, [{:done, ref} | rest]) do
    case Mint.WebSocket.new(state.conn, ref, state.status, state.resp_headers) do
      {:ok, conn, websocket} ->
        %{state | conn: conn, websocket: websocket, status: nil, resp_headers: nil}
        |> handle_responses(rest)

      {:error, conn, _reason} ->
        %{state | conn: conn, error_closing?: true}
        |> close()
    end
  end

  defp handle_responses(%{request_ref: ref, websocket: websocket} = state, [
         {:data, ref, data} | rest
       ])
       when websocket != nil do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        put_in(state.websocket, websocket)
        |> handle_frames(frames)
        |> handle_responses(rest)

      {:error, websocket, _reason} ->
        %{state | websocket: websocket, error_closing?: true}
        |> close()
    end
  end

  defp handle_responses(state, [_response | rest]) do
    handle_responses(state, rest)
  end

  defp handle_responses(state, []), do: state

  def handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
      {:close, code, _reason} = frame, state ->
        %{state | relay_closing?: true, close_code: code, frame: frame}

      frame, state ->
        %{state | frame: frame}
    end)
  end

  # When connection is already closed
  def close(%{conn: %{state: :closed} = conn} = state) do
    {:close, state.close_code, put_in(state.conn, conn)}
  end

  # When there was a connection error with the relay
  def close(%{error_closing?: true, conn: conn} = state) do
    {:close, @bad_gateway_code, put_in(state.conn, conn)}
  end

  # When the client has initiated the close
  def close(%{relay_closing?: false, conn: conn} = state) do
    _ = send_frame(state, {:close, @going_away_code, ""})
    {:ok, conn} = Mint.HTTP.close(conn)
    {:ok, put_in(state.conn, conn)}
  end

  def close(%{conn: conn} = state) do
    # May fail if the relay has already closed
    _ = send_frame(state, :close)
    {:ok, conn} = Mint.HTTP.close(conn)
    {:close, state.close_code, put_in(state.conn, conn)}
  end
end
