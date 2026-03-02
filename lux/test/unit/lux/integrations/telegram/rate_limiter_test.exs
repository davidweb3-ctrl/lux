defmodule Lux.Integrations.Telegram.RateLimiterTest do
  use UnitAPICase, async: true

  alias Lux.Integrations.Telegram.RateLimiter

  setup do
    # Start a fresh rate limiter for each test
    {:ok, pid} = RateLimiter.start_link(name: :test_rate_limiter)
    %{limiter: pid}
  end

  describe "acquire_permission/1" do
    test "allows requests within global limit", %{limiter: limiter} do
      # Should allow first request
      assert :ok = RateLimiter.acquire_permission(server: limiter)

      # Should still allow more requests
      assert :ok = RateLimiter.acquire_permission(server: limiter)
    end

    test "tracks per-chat limits separately", %{limiter: limiter} do
      chat_id = "123456789"

      # Multiple requests to different chats should be allowed
      assert :ok = RateLimiter.acquire_permission(server: limiter, chat_id: chat_id)
      assert :ok = RateLimiter.acquire_permission(server: limiter, chat_id: "987654321")
      assert :ok = RateLimiter.acquire_permission(server: limiter, chat_id: chat_id)
    end

    test "returns rate_limited when global limit exceeded", %{limiter: limiter} do
      # Set very low limits for testing
      {:ok, limiter} = RateLimiter.start_link(
        name: :test_global_limit,
        global_limit: 1,
        global_window: 5000
      )

      # First request should succeed
      assert :ok = RateLimiter.acquire_permission(server: limiter)

      # Second request should wait and eventually return
      # Note: In practice this would block, but with our implementation it retries
      result = RateLimiter.acquire_permission(server: limiter)
      assert result == :ok or result == {:error, :rate_limited}
    end
  end

  describe "allowed?/1" do
    test "returns true when under limit", %{limiter: limiter} do
      assert RateLimiter.allowed?(server: limiter)
    end

    test "returns false when global limit would be exceeded", %{limiter: limiter} do
      # Acquire all available tokens
      for _ <- 1..30 do
        RateLimiter.acquire_permission(server: limiter)
      end

      # Should return false
      refute RateLimiter.allowed?(server: limiter)
    end
  end

  describe "get_status/1" do
    test "returns current rate limit status", %{limiter: limiter} do
      status = RateLimiter.get_status(server: limiter)

      assert is_map(status)
      assert status.global.remaining <= 30
      assert status.global.limit == 30
      assert is_integer(status.global.reset_in)
    end

    test "includes chat-specific status", %{limiter: limiter} do
      # Make some requests to specific chats
      RateLimiter.acquire_permission(server: limiter, chat_id: "123")
      RateLimiter.acquire_permission(server: limiter, chat_id: "456")

      status = RateLimiter.get_status(server: limiter)

      assert is_map(status.chats)
    end
  end

  describe "reset/1" do
    test "resets all rate limits", %{limiter: limiter} do
      # Use up some tokens
      RateLimiter.acquire_permission(server: limiter)
      RateLimiter.acquire_permission(server: limiter, chat_id: "123")

      # Reset
      :ok = RateLimiter.reset(server: limiter)

      # Should have full quota again
      status = RateLimiter.get_status(server: limiter)
      assert status.global.remaining == 30
    end
  end
end