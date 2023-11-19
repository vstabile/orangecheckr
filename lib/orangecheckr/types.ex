defmodule OrangeCheckr.Types do
  @type relay_uri :: %{
          scheme: :ws | :wss,
          host: String.t(),
          port: :inet.port_number(),
          path: String.t()
        }
end
