defmodule Orangecheckr.ConnectivityTest do
  use ExUnit.Case, async: false
  alias OrangeCheckr.TestClient
  alias OrangeCheckr.TestRelay

  @proxy_port Application.compile_env(:orangecheckr, :proxy_port)
  @proxy_url "http://localhost:#{@proxy_port}"

  setup_all do
    {:ok, server} = Bandit.start_link(plug: TestRelay.Router, port: 0)

    Application.stop(:orangecheckr)
    Application.put_env(:orangecheckr, :relay_uri, TestRelay.Router.url(server))
    Application.ensure_started(:orangecheckr)

    :ok
  end

  setup do
    {:ok, _} = Registry.register(OrangeCheckr.TestRegistry, :test, self())
    {:ok, client} = TestClient.start(@proxy_url)

    relay =
      receive do
        {:relay_connected, relay} -> relay
      end

    %{client: client, relay: relay}
  end

  test "proxy endpoint without upgrade or accept header" do
    {:ok, response} = @proxy_url |> HTTPoison.get()

    assert response.status_code == 200
    assert response.body == "Please use a Nostr client to connect."
  end

  test "proxy relay information document endpoint" do
    {:ok, response} = @proxy_url |> HTTPoison.get(Accept: "application/nostr+json")

    assert response.status_code == 200
    assert response.body == File.read!("test/fixtures/relay_information.json")
  end

  test "proxy invalid endpoint" do
    {:ok, response} = (@proxy_url <> "/invalid") |> HTTPoison.get()

    assert response.status_code == 404
    assert response.body == "Not found. Relay path is /"
  end

  test "upgrade to websocket", %{client: client} do
    conn = TestClient.get_conn(client)

    accepted =
      Enum.any?(conn.resp_headers, fn {key, _} ->
        String.downcase(key) == "sec-websocket-accept"
      end)

    assert accepted
  end

  test "proxy sends an authentication request", %{client: client} do
    {:ok, message} = TestClient.receive_message(client)
    [type, challenge] = Jason.decode!(message)

    assert type == "AUTH"
    assert is_binary(challenge)
  end

  test "client authenticates", %{client: client} do
    {:ok, message} = TestClient.authenticate(client)

    decoded_message = Jason.decode!(message)

    assert length(decoded_message) == 4
    assert Enum.at(decoded_message, 0) == "OK"
    assert Enum.at(decoded_message, 2) == true
    assert Enum.at(decoded_message, 3) == ""
  end

  test "client pings the relay", %{client: client} do
    TestClient.ignore_authentication(client)

    client |> TestClient.ping("test")

    assert_receive :relay_ping_received, 100
    assert TestClient.pong_received?(client, "test")
  end

  test "relay pings the client", %{client: client, relay: relay} do
    TestClient.authenticate(client)

    send(relay, {:test, :ping, "test"})

    assert TestClient.ping_received?(client, "test")
    assert_receive :relay_pong_received, 100
  end

  test "subscribe to events", %{client: client} do
    TestClient.authenticate(client)

    TestClient.send_message(client, ~s(["REQ", "subscriptio-id", {}]))
    {:ok, message} = TestClient.receive_message(client)

    assert message == File.read!("test/fixtures/subscription_response.json")
  end

  test "client closing the connection", %{client: client} do
    TestClient.close(client)

    assert_receive {:client_closed, {:local, :normal}}, 100
    assert_receive {:relay_closed, :remote}, 100
  end
end
