defmodule Lux.Integrations.Telegram.ClientWithRetryTest do
  use UnitAPICase, async: true

  alias Lux.Integrations.Telegram.ClientWithRetry

  import Mock

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  describe "request/3" do
    test "succeeds on first try" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/bottest_token/sendMessage"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => %{"message_id" => 123}
        }))
      end)

      assert {:ok, %{"ok" => true}} =
        ClientWithRetry.request(:post, "/sendMessage", %{
          token: "test_token",
          json: %{chat_id: 123, text: "Hello"}
        })
    end

    test "retries on 500 error and succeeds" do
      # First request fails
      Req.Test.expect(TelegramClientMock, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{
          "ok" => false,
          "error_code" => 500,
          "description" => "Internal Server Error"
        }))
      end)

      # Second request succeeds
      Req.Test.expect(TelegramClientMock, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => %{"message_id" => 123}
        }))
      end)

      assert {:ok, %{"ok" => true}} =
        ClientWithRetry.request(:post, "/sendMessage", %{
          token: "test_token",
          json: %{chat_id: 123, text: "Hello"},
          base_delay: 100  # Faster retry for tests
        })
    end

    test "retries on 429 rate limit with retry_after" do
      # First request rate limited
      Req.Test.expect(TelegramClientMock, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(429, Jason.encode!(%{
          "ok" => false,
          "error_code" => 429,
          "description" => "Too Many Requests",
          "parameters" => %{"retry_after" => 1}
        }))
      end)

      # Second request succeeds
      Req.Test.expect(TelegramClientMock, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => %{"message_id" => 123}
        }))
      end)

      start_time = System.monotonic_time(:millisecond)

      assert {:ok, %{"ok" => true}} =
        ClientWithRetry.request(:post, "/sendMessage", %{
          token: "test_token",
          json: %{chat_id: 123, text: "Hello"}
        })

      # Should have waited at least 1 second
      elapsed = System.monotonic_time(:millisecond) - start_time
      assert elapsed >= 900  # Allow some margin
    end

    test "gives up after max retries" do
      # All requests fail
      for _ <- 1..4 do
        Req.Test.expect(TelegramClientMock, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, Jason.encode!(%{
            "ok" => false,
            "error_code" => 500,
            "description" => "Internal Server Error"
          }))
        end)
      end

      assert {:error, _} =
        ClientWithRetry.request(:post, "/sendMessage", %{
          token: "test_token",
          json: %{chat_id: 123, text: "Hello"},
          max_retries: 3,
          base_delay: 10
        })
    end

    test "does not retry 4xx errors (except 429)" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{
          "ok" => false,
          "error_code" => 400,
          "description" => "Bad Request: chat not found"
        }))
      end)

      assert {:error, {400, "Bad Request: chat not found"}} =
        ClientWithRetry.request(:post, "/sendMessage", %{
          token: "test_token",
          json: %{chat_id: 123, text: "Hello"}
        })
    end
  end

  describe "rate limit integration" do
    test "checks rate limiter before request" do
      # Start a rate limiter
      {:ok, limiter} = Lux.Integrations.Telegram.RateLimiter.start_link(
        name: :test_retry_limiter,
        global_limit: 1,
        global_window: 5000
      )

      # First request should succeed
      Req.Test.expect(TelegramClientMock, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => %{"message_id" => 1}
        }))
      end)

      assert {:ok, _} = ClientWithRetry.request(:post, "/sendMessage", %{
        token: "test_token",
        json: %{chat_id: 123, text: "Hello"},
        rate_limit_chat_id: 123
      })
    end
  end
end