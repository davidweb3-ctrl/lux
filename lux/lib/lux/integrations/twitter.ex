defmodule Lux.Integrations.Twitter do
  @moduledoc """
  Integration module for Twitter API v2.
  Provides authentication and common utilities for Twitter lenses.
  """

  @type headers_list :: [{String.t(), String.t()}]
  @type auth_headers :: [{String.t(), String.t()}]

  @doc """
  Returns default headers for Twitter API requests.
  """
  @spec headers() :: headers_list()
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
  @spec auth() :: auth_headers()
  def auth do
    case System.get_env("TWITTER_BEARER_TOKEN") do
      nil -> []
      token -> [{"Authorization", "Bearer #{token}"}]
    end
  end

  @doc """
  Returns the base URL for Twitter API v2.
  """
  @spec base_url() :: String.t()
  def base_url do
    "https://api.twitter.com/2"
  end
end
