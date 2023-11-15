defmodule OrangeCheckr.Application do
  use Application
  alias OrangeCheckr.ProxyServer

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:orangecheckr, :proxy_port)

    children = [
      {Bandit, scheme: :http, plug: ProxyServer, port: port}
    ]

    opts = [strategy: :one_for_one, name: OrangeCheckr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
