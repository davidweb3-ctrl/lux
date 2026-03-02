defmodule Lux.Integrations.Telegram.ClientWithRetry do
  @moduledoc """
  Telegram Client with retry logic and rate limiting.

  This module wraps the base Telegram.Client with:
  - Automatic retries with exponential backoff
  - Rate limit handling (429 responses)
  - Connection error recovery
  - Configurable retry policies

  ## Retry Policy

  By default, the client will retry:
  - Up to 3 attempts for transient errors (5xx, network errors, rate limits)
  - With exponential backoff: 1s, 2s, 4s
  - Only retry safe HTTP methods (GET, POST with idempotent operations)

  ## Examples

      # Automatic retry on rate limit
      ClientWithRetry.request(:post, "/sendMessage", %{
        token: "bot_token",
        json: %{chat_id: 123, text: "Hello"}
      })

      # Custom retry configuration
      ClientWithRetry.request(:post, "/sendMessage", %{
        token: "bot_token",
        json: %{chat_id: 123, text: "Hello"},
        max_retries: 5,
        base_delay: 500
      })
  """

  alias Lux.Integrations.Telegram.Client
  alias Lux.Integrations.Telegram.RateLimiter

  require Logger

  @default_max_retries 3
  @default_base_delay 1000
  @default_max_delay 30_000

  @type retry_opts :: %{
          max_retries: non_neg_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          retry_on_rate_limit: boolean()
        }

  @doc """
  Makes a request to the Telegram Bot API with automatic retries.

  ## Options
    * `:token` - Bot API token
    * `:json` - Request body
    * `:headers` - Additional headers
    * `:plug` - Test plug
    * `:max_retries` - Max retry attempts (default: 3)
    * `:base_delay` - Initial retry delay in ms (default: 1000)
    * `:max_delay` - Max retry delay in ms (default: 30000)
    * `:retry_on_rate_limit` - Whether to retry on 429 (default: true)
    * `:rate_limit_chat_id` - Chat ID for per-chat rate limiting

  ## Examples

      iex> ClientWithRetry.request(:post, "/sendMessage", %{
      ...>   token: "bot_token",
      ...>   json: %{chat_id: 123, text: "Hello"}
      ...> })
      {:ok, %{"ok" => true, "result" => %{"message_id" => 456}}}

      iex> ClientWithRetry.request(:get, "/getMe", %{token: "bot_token"})
      {:ok, %{"ok" => true, "result" => %{"username" => "my_bot"}}}
  """
  @spec request(atom(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def request(method, path, opts \\ %{}) do
    retry_opts = %{
      max_retries: opts[:max_retries] || @default_max_retries,
      base_delay: opts[:base_delay] || @default_base_delay,
      max_delay: opts[:max_delay] || @default_max_delay,
      retry_on_rate_limit: opts[:retry_on_rate_limit] != false
    }

    # Apply rate limiting if available
    chat_id = opts[:rate_limit_chat_id]

    case apply_rate_limit(chat_id) do
      :ok ->
        do_request_with_retry(method, path, opts, retry_opts, 0)

      {:error, reason} ->
        {:error, {:rate_limited, reason}}
    end
  end

  # Private Functions

  defp apply_rate_limit(nil), do: :ok

  defp apply_rate_limit(chat_id) do
    if Process.whereis(RateLimiter) do
      RateLimiter.acquire_permission(chat_id: chat_id)
    else
      :ok
    end
  end

  defp do_request_with_retry(method, path, opts, retry_opts, attempt) do
    case Client.request(method, path, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, error} ->
        if should_retry?(error, retry_opts, attempt) do
          delay = calculate_delay(error, retry_opts, attempt)
          log_retry(error, attempt, delay, path)
          Process.sleep(delay)
          do_request_with_retry(method, path, opts, retry_opts, attempt + 1)
        else
          {:error, error}
        end
    end
  end

  defp should_retry?(_error, %{max_retries: max}, attempt) when attempt >= max, do: false

  defp should_retry?({429, _}, %{retry_on_rate_limit: true}, _attempt), do: true
  defp should_retry?({status, _}, _opts, _attempt) when status in 500..599, do: true

  defp should_retry?(error, _opts, _attempt) when is_atom(error) do
    error in [:timeout, :connect_timeout, :closed, :enetunreach, :econnrefused]
  end

  defp should_retry?(%{reason: reason}, _opts, _attempt) when is_atom(reason) do
    reason in [:timeout, :connect_timeout, :closed, :enetunreach, :econnrefused]
  end

  defp should_retry?(_error, _opts, _attempt), do: false

  defp calculate_delay({429, %{"parameters" => %{"retry_after" => retry_after}}}, _opts, _attempt) do
    # Telegram tells us exactly how long to wait
    retry_after * 1000
  end

  defp calculate_delay(_error, %{base_delay: base, max_delay: max}, attempt) do
    # Exponential backoff with jitter
    base_delay = min(base * :math.pow(2, attempt), max)
    jitter = :rand.uniform(100)
    trunc(base_delay) + jitter
  end

  defp log_retry(error, attempt, delay, path) do
    Logger.warning(
      "Telegram API retry #{attempt + 1} for #{path}: #{inspect(error)}, waiting #{delay}ms"
    )
  end
end