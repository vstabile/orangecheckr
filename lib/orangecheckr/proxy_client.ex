defmodule OrangeCheckr.ProxyClient do
  require Logger

  @type frame :: Mint.WebSocket.frame() | Mint.WebSocket.short_hand_frame()

  @type t :: %__MODULE__{
          conn: Mint.HTTP.t(),
          websocket: Mint.WebSocket.t() | nil,
          request_ref: reference(),
          status: Mint.Types.status() | nil,
          resp_headers: Mint.Types.headers() | nil,
          closing?: boolean(),
          frame: frame() | nil
        }
  @type http_scheme :: :http | :https
  @type ws_scheme :: :ws | :wss

  defstruct [
    :conn,
    :websocket,
    :request_ref,
    :status,
    :resp_headers,
    :closing?,
    :frame
  ]

  @spec connect(http_scheme(), ws_scheme(), String.t(), :inet.port_number(), String.t()) ::
          {:ok, t()} | {:error, term()}
  def connect(http_scheme, ws_scheme, host, port, path) do
    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, host, port),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []) do
      state = %__MODULE__{conn: conn, request_ref: ref, closing?: false}
      {:ok, state}
    else
      {:error, reason} ->
        {:error, reason}

      {:error, _conn, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec handle_message(t(), term()) :: {:ok, t()} | {:close, t()} | {:error, atom()}
  def handle_message(state, message) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state =
          %{state | conn: conn, frame: nil} |> handle_responses(responses)

        if state.closing?, do: close(state), else: {:ok, state}

      {:error, _conn, reason, _responses} ->
        {:error, reason}

      :unknown ->
        {:error, :unknown}
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
        {:error, put_in(state.websocket, websocket), reason}

      {:error, conn, reason} ->
        {:error, put_in(state.conn, conn), reason}
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

      {:error, conn, reason} ->
        IO.inspect({:error, reason})

        put_in(state.conn, conn)
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

      {:error, websocket, reason} ->
        IO.inspect({:error, reason})

        put_in(state.websocket, websocket)
        |> close()
    end
  end

  defp handle_responses(state, [_response | rest]) do
    handle_responses(state, rest)
  end

  defp handle_responses(state, []), do: state

  def handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
      {:close, _code, _reason} = frame, state ->
        %{state | closing?: true, frame: frame}

      frame, state ->
        %{state | frame: frame}
    end)
  end

  def close(state) do
    _ = send_frame(state, :close)
    {:ok, conn} = Mint.HTTP.close(state.conn)
    {:close, put_in(state.conn, conn)}
  end
end
