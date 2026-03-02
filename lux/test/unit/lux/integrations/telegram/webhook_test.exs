defmodule Lux.Integrations.Telegram.WebhookTest do
  use UnitAPICase, async: true

  alias Lux.Integrations.Telegram.Webhook

  import Mock

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  describe "set_webhook/3" do
    test "sets webhook with URL only" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/bottest_token/setWebhook"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["url"] == "https://myapp.com/webhook"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => true
        }))
      end)

      assert {:ok, %{"ok" => true}} =
        Webhook.set_webhook("https://myapp.com/webhook", "test_token")
    end

    test "sets webhook with all options" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)

        assert params["url"] == "https://myapp.com/webhook"
        assert params["max_connections"] == 20
        assert params["allowed_updates"] == ["message", "callback_query"]
        assert params["drop_pending_updates"] == true
        assert params["secret_token"] == "my_secret"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => true
        }))
      end)

      assert {:ok, %{"ok" => true}} =
        Webhook.set_webhook("https://myapp.com/webhook", "test_token", %{
          max_connections: 20,
          allowed_updates: ["message", "callback_query"],
          drop_pending_updates: true,
          secret_token: "my_secret"
        })
    end
  end

  describe "get_webhook_info/1" do
    test "returns webhook info" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/bottest_token/getWebhookInfo"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => %{
            "url" => "https://myapp.com/webhook",
            "has_custom_certificate" => false,
            "pending_update_count" => 0,
            "max_connections" => 40
          }
        }))
      end)

      assert {:ok, %{"ok" => true, "result" => result}} =
        Webhook.get_webhook_info("test_token")

      assert result["url"] == "https://myapp.com/webhook"
    end
  end

  describe "delete_webhook/2" do
    test "deletes webhook" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/bottest_token/deleteWebhook"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => true
        }))
      end)

      assert {:ok, %{"ok" => true}} =
        Webhook.delete_webhook("test_token")
    end

    test "deletes webhook with drop_pending_updates" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["drop_pending_updates"] == true

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => true
        }))
      end)

      assert {:ok, %{"ok" => true}} =
        Webhook.delete_webhook("test_token", drop_pending_updates: true)
    end
  end

  describe "telegram_ip_ranges/0" do
    test "returns list of IP ranges" do
      ranges = Webhook.telegram_ip_ranges()
      assert is_list(ranges)
      assert "149.154.160.0/20" in ranges
      assert "91.108.4.0/22" in ranges
    end
  end

  describe "telegram_ip?/1" do
    test "returns true for Telegram IPs" do
      assert Webhook.telegram_ip?("149.154.160.1")
      assert Webhook.telegram_ip?("91.108.4.1")
    end

    test "returns false for non-Telegram IPs" do
      refute Webhook.telegram_ip?("192.168.1.1")
      refute Webhook.telegram_ip?("8.8.8.8")
    end
  end
end