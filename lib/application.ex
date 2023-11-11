defmodule OrangeCheckr.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Bandit, scheme: :http, plug: OrangeCheckr.Proxy, port: 4000}
    ]

    opts = [strategy: :one_for_one, name: OrangeCheckr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
