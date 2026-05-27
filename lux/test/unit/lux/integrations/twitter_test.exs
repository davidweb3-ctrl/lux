defmodule Lux.Integrations.TwitterTest do
  use UnitCase, async: true

  alias Lux.Integrations.Twitter

  describe "headers/0" do
    test "returns default headers" do
      headers = Twitter.headers()
      
      assert {"Content-Type", "application/json"} in headers
      assert {"User-Agent", "Lux/1.0"} in headers
    end
  end

  describe "auth/0" do
    test "returns empty list when no token configured" do
      # Ensure env var is not set
      System.delete_env("TWITTER_BEARER_TOKEN")
      
      assert Twitter.auth() == []
    end

    test "returns auth header when token is configured" do
      System.put_env("TWITTER_BEARER_TOKEN", "test_token_123")
      
      auth = Twitter.auth()
      assert {"Authorization", "Bearer test_token_123"} in auth
      
      # Cleanup
      System.delete_env("TWITTER_BEARER_TOKEN")
    end
  end

  describe "base_url/0" do
    test "returns Twitter API v2 base URL" do
      assert Twitter.base_url() == "https://api.twitter.com/2"
    end
  end
end
