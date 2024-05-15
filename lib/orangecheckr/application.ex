defmodule OrangeCheckr.Application do
  use Application
  alias OrangeCheckr.Router
  alias OrangeCheckr.Bot

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:orangecheckr, :proxy_port)

    relay_uri =
      Application.get_env(:orangecheckr, :relay_uri)
      |> URI.parse()
      |> Map.from_struct()
      |> Map.drop([:authority, :query, :fragment, :userinfo])
      |> Map.update(:scheme, :wss, &String.to_atom/1)
      |> Map.update(:path, "/", fn path -> path || "/" end)

    router_opts = %{
      uri: relay_uri,
      proxy_path: Application.get_env(:orangecheckr, :proxy_path, "/"),
      favicon_path: Application.get_env(:orangecheckr, :favicon_path, "/favicon.ico")
    }

    bot_opts = %{
      relay_uri: relay_uri,
      private_key:
        NostrBasics.Keys.PrivateKey.from_nsec!(Application.get_env(:orangecheckr, :bot_nsec))
    }

    children = [
      {Bot, bot_opts},
      {Bandit, scheme: :http, plug: {Router, router_opts}, port: port}
    ]

    opts = [strategy: :one_for_one, name: OrangeCheckr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
