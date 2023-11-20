defmodule Orangecheckr.DelayedConnectivityTest do
  use ExUnit.Case, async: false
  alias OrangeCheckr.TestClient
  alias OrangeCheckr.TestRelay

  @proxy_port Application.compile_env(:orangecheckr, :proxy_port)
  @proxy_url "http://localhost:#{@proxy_port}"

  setup_all do
    {:ok, server} = Bandit.start_link(plug: {TestRelay, [delay: 50]}, port: 0)

    Application.stop(:orangecheckr)
    Application.put_env(:orangecheckr, :relay_uri, TestRelay.url(server))
    Application.ensure_started(:orangecheckr)

    :ok
  end

  setup do
    {:ok, _} = Registry.register(OrangeCheckr.TestRegistry, :test, self())

    {:ok, client} = TestClient.start(@proxy_url)

    %{client: client}
  end

  test "client pings before the proxy is connected to the relay", %{client: client} do
    TestClient.ignore_authentication(client)

    client |> TestClient.ping("test")

    # Relay was not connected when ping was sent
    refute_received {:relay_connected, _}

    assert_receive {:relay_connected, _}, 100
    assert_receive :relay_ping_received, 100
    assert TestClient.pong_received?(client, "test")
  end

  test "client subscribe to events before the proxy is connected to the relay", %{client: client} do
    TestClient.authenticate(client)

    TestClient.send_message(client, ~s(["REQ", "subscriptio-id", {}]))

    # Relay was not connected when message was sent
    refute_received {:relay_connected, _}

    {:ok, message} = TestClient.receive_message(client)

    assert message == File.read!("test/fixtures/subscription_response.json")
  end

  test "client closing before the proxy is connected to the relay", %{client: client} do
    TestClient.close(client)

    # Relay was not connected when close was sent
    refute_received {:relay_connected, _}

    assert_receive {:client_closed, {:local, :normal}}, 100
    assert_receive {:relay_closed, :remote}, 100
  end
end
