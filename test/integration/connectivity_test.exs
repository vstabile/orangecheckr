defmodule Orangecheckr.ConnectivityTest do
  use ExUnit.Case, async: false

  @proxy_port Application.compile_env(:orangecheckr, :proxy_port)
  @proxy_url "http://localhost:#{@proxy_port}"

  setup_all do
    {:ok, relay} = Bandit.start_link(plug: TestRelay, port: 0)

    Application.stop(:orangecheckr)
    Application.put_env(:orangecheckr, :relay_uri, TestRelay.url(relay))
    Application.ensure_started(:orangecheckr)

    on_exit(fn ->
      TestRelay.stop(relay)
    end)

    :ok
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
    assert response.body == "Cannot GET /invalid"
  end

  test "upgrade to websocket" do
    {:ok, client} = TestClient.start(@proxy_url)
    conn = TestClient.get_conn(client)

    accepted =
      Enum.any?(conn.resp_headers, fn {key, _} ->
        String.downcase(key) == "sec-websocket-accept"
      end)

    assert accepted
  end

  test "subscribe to events" do
    {:ok, client} = TestClient.start(@proxy_url)

    TestClient.send_message(client, ~s(["REQ", "subscriptio-id", {}]))
    {:ok, message} = TestClient.receive_message(client)

    assert message == File.read!("test/fixtures/subscription_response.json")
  end
end
