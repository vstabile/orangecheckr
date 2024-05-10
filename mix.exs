defmodule Orangecheckr.MixProject do
  use Mix.Project

  def project do
    [
      app: :orangecheckr,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      licenses: ["MIT"],
      elixirc_paths: elixirc_paths(Mix.env())
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
      {:bandit, "~> 1.1"},
      {:plug, "~> 1.15"},
      {:httpoison, "~> 2.2"},
      {:websock_adapter, "~> 0.5.5"},
      {:mint_web_socket, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},
      {:nostr_basics, "~> 0.1.6"},
      {:websockex, "~> 0.4.3", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
