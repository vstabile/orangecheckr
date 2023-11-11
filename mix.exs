defmodule Orangecheckr.MixProject do
  use Mix.Project

  def project do
    [
      app: :orangecheckr,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {OrangeCheckr.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 0.6"},
      {:plug, "~> 1.15"},
      {:httpoison, "~> 2.2"},
      {:websock_adapter, "~> 0.5.5"},
      {:mint_web_socket, "~> 1.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
