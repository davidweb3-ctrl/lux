defmodule Lux.Integrations.Twitter do
  @moduledoc """
  Integration module for Twitter API v2.
  Provides authentication and common utilities for Twitter lenses.
  """

  @doc """
  Returns default headers for Twitter API requests.
  """
  def headers do
    [
      {"Content-Type", "application/json"},
      {"User-Agent", "Lux/1.0"}
    ]
  end

  @doc """
  Returns authentication configuration for Twitter API.
  Supports OAuth 2.0 Bearer Token.
  """
  def auth do
    case System.get_env("TWITTER_BEARER_TOKEN") do
      nil -> []
      token -> [{"Authorization", "Bearer #{token}"}]
    end
  end

  @doc """
  Returns the base URL for Twitter API v2.
  """
  def base_url do
    "https://api.twitter.com/2"
  end
end
