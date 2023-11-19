defmodule Orangecheckr.Utils do
  def ws_to_http_scheme(:ws), do: :http
  def ws_to_http_scheme(:wss), do: :https
end
