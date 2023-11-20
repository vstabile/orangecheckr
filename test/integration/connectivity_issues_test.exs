defmodule Orangecheckr.ConnectivityIssuesTest do
  use ExUnit.Case
  alias OrangeCheckr.TestClient
  alias OrangeCheckr.TestRelay

  @proxy_port Application.compile_env(:orangecheckr, :proxy_port)
  @proxy_url "http://localhost:#{@proxy_port}"
  @bad_gateway_code 1014

  setup context do
    server_name = context.test

    {:ok, _} = Registry.register(OrangeCheckr.TestRegistry, :test, self())

    Bandit.start_link(
      plug: TestRelay,
      port: 0,
      thousand_island_options: [supervisor_options: [name: server_name]]
    )

    Application.stop(:orangecheckr)
    Application.put_env(:orangecheckr, :relay_uri, TestRelay.url(server_name))
    Application.ensure_started(:orangecheckr)
    {:ok, client} = TestClient.start(@proxy_url)

    relay =
      receive do
        {:relay_connected, relay} -> relay
      end

    %{client: client, relay: relay, server: server_name}
  end

  test "proxy closing the connection", %{client: client} do
    TestClient.authenticate(client)

    Application.stop(:orangecheckr)

    assert_receive {:client_closed, {:remote, 1000, ""}}, 100
    assert_receive {:relay_closed, :remote}, 100
  end

  test "trying to connect when the relay server is unavailable", %{server: server} do
    GenServer.stop(server, :normal)
    {:ok, _} = TestClient.start(@proxy_url)

    assert_receive {:client_closed, {:remote, @bad_gateway_code, ""}}, 100
  end

  test "proxy reconnects after relay closes the connection", %{client: client, relay: relay} do
    TestClient.authenticate(client)

    send(relay, {:test, :close, 1000, :normal})

    assert_receive {:relay_closed, :normal}, 100
    refute_receive {:client_closed, _}, 100
    assert_receive {:relay_connected, _}, 100
  end

  test "proxy does not reconnect when close status is 4000", %{client: client, relay: relay} do
    TestClient.authenticate(client)

    send(relay, {:test, :close, 4000, :normal})

    assert_receive {:relay_closed, :normal}, 100
    assert_receive {:client_closed, {:remote, 4000, ""}}, 100
  end

  test "relay server becomes unavailable after connected", %{client: client, server: server} do
    TestClient.authenticate(client)

    GenServer.stop(server, :normal)

    assert_receive {:relay_closed, :shutdown}, 100
    assert_receive {:client_closed, {:remote, @bad_gateway_code, ""}}, 100
  end
end
