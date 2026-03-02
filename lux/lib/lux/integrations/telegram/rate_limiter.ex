defmodule Lux.Integrations.Telegram.RateLimiter do
  @moduledoc """
  Rate limit management for Telegram Bot API.

  Telegram Bot API has the following limits:
  - 30 messages per second per bot
  - 20 messages per minute to the same chat
  - 1 message per second to the same chat (for bulk messages)

  This module provides token bucket rate limiting for both global and per-chat limits.
  """

  use GenServer

  require Logger

  @default_global_limit 30
  @default_global_window 1000
  @default_chat_limit 20
  @default_chat_window 60_000

  @type limit_type :: :global | {:chat, String.t() | integer()}
  @type limits :: %{
          global: {max :: pos_integer(), window_ms :: pos_integer()},
          chat: {max :: pos_integer(), window_ms :: pos_integer()}
        }

  # Client API

  @doc """
  Starts the rate limiter with optional configuration.

  ## Options
    * `:global_limit` - Max requests per global window (default: 30)
    * `:global_window` - Global window in milliseconds (default: 1000)
    * `:chat_limit` - Max requests per chat per window (default: 20)
    * `:chat_window` - Chat window in milliseconds (default: 60000)
    * `:name` - GenServer name (optional)

  ## Examples

      iex> RateLimiter.start_link([])
      {:ok, pid}

      iex> RateLimiter.start_link(global_limit: 50, chat_limit: 30)
      {:ok, pid}
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Acquires permission to make a request, blocking if necessary.

  Returns `:ok` if permission is granted, or `{:error, reason}` if rate limited.

  ## Examples

      iex> RateLimiter.acquire_permission()
      :ok

      iex> RateLimiter.acquire_permission(chat_id: "123456789")
      :ok
  """
  @spec acquire_permission(keyword()) :: :ok | {:error, term()}
  def acquire_permission(opts \\ []) do
    name = opts[:server] || __MODULE__
    chat_id = opts[:chat_id]

    GenServer.call(name, {:acquire, chat_id}, :infinity)
  end

  @doc """
  Checks if a request would be rate limited without blocking.

  Returns `true` if the request would be allowed, `false` otherwise.

  ## Examples

      iex> RateLimiter.allowed?()
      true

      iex> RateLimiter.allowed?(chat_id: "123456789")
      false
  """
  @spec allowed?(keyword()) :: boolean()
  def allowed?(opts \\ []) do
    name = opts[:server] || __MODULE__
    chat_id = opts[:chat_id]

    GenServer.call(name, {:check, chat_id})
  end

  @doc """
  Gets current rate limit status.

  ## Examples

      iex> RateLimiter.get_status()
      %{
        global: %{remaining: 25, reset_at: ~U[2025-01-01 12:00:01Z]},
        chats: %{"123456789" => %{remaining: 15, reset_at: ~U[2025-01-01 12:01:00Z]}}
      }
  """
  @spec get_status(keyword()) :: map()
  def get_status(opts \\ []) do
    name = opts[:server] || __MODULE__
    GenServer.call(name, :get_status)
  end

  @doc """
  Resets all rate limits. Useful for testing.

  ## Examples

      iex> RateLimiter.reset()
      :ok
  """
  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) do
    name = opts[:server] || __MODULE__
    GenServer.cast(name, :reset)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      global_limit: opts[:global_limit] || @default_global_limit,
      global_window: opts[:global_window] || @default_global_window,
      chat_limit: opts[:chat_limit] || @default_chat_limit,
      chat_window: opts[:chat_window] || @default_chat_window,
      global_tokens: @default_global_limit,
      global_last_refill: System.monotonic_time(:millisecond),
      chat_buckets: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:acquire, chat_id}, _from, state) do
    state = refill_tokens(state)

    case try_acquire(state, chat_id) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:wait, ms, new_state} ->
        Logger.debug("Rate limit hit, waiting #{ms}ms")
        Process.sleep(ms)
        # Try again after waiting
        state = refill_tokens(new_state)

        case try_acquire(state, chat_id) do
          {:ok, final_state} -> {:reply, :ok, final_state}
          {:wait, _, final_state} -> {:reply, {:error, :rate_limited}, final_state}
        end
    end
  end

  @impl true
  def handle_call({:check, chat_id}, _from, state) do
    state = refill_tokens(state)
    result = can_acquire?(state, chat_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      global: %{
        remaining: state.global_tokens,
        limit: state.global_limit,
        reset_in: time_until_refill(state.global_last_refill, state.global_window)
      },
      chats: build_chat_status(state.chat_buckets, state)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:reset, state) do
    new_state = %{
      state
      | global_tokens: state.global_limit,
        global_last_refill: System.monotonic_time(:millisecond),
        chat_buckets: %{}
    }

    {:noreply, new_state}
  end

  # Private Functions

  defp refill_tokens(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.global_last_refill

    if elapsed >= state.global_window do
      new_tokens = state.global_limit

      new_chat_buckets =
        Map.new(state.chat_buckets, fn {chat_id, bucket} ->
          chat_elapsed = now - bucket.last_refill

          if chat_elapsed >= state.chat_window do
            {chat_id, %{tokens: state.chat_limit, last_refill: now}}
          else
            {chat_id, bucket}
          end
        end)

      %{
        state
        | global_tokens: new_tokens,
          global_last_refill: now,
          chat_buckets: new_chat_buckets
      }
    else
      state
    end
  end

  defp try_acquire(state, nil) do
    if state.global_tokens > 0 do
      {:ok, %{state | global_tokens: state.global_tokens - 1}}
    else
      wait_ms = state.global_window - (System.monotonic_time(:millisecond) - state.global_last_refill)
      {:wait, max(wait_ms, 100), state}
    end
  end

  defp try_acquire(state, chat_id) do
    chat_key = to_string(chat_id)
    chat_bucket = Map.get(state.chat_buckets, chat_key, %{tokens: state.chat_limit, last_refill: System.monotonic_time(:millisecond)})

    cond do
      state.global_tokens <= 0 ->
        wait_ms = state.global_window - (System.monotonic_time(:millisecond) - state.global_last_refill)
        {:wait, max(wait_ms, 100), state}

      chat_bucket.tokens <= 0 ->
        wait_ms = state.chat_window - (System.monotonic_time(:millisecond) - chat_bucket.last_refill)
        {:wait, max(wait_ms, 100), state}

      true ->
        new_state = %{
          state
          | global_tokens: state.global_tokens - 1,
            chat_buckets: Map.put(state.chat_buckets, chat_key, %{chat_bucket | tokens: chat_bucket.tokens - 1})
        }

        {:ok, new_state}
    end
  end

  defp can_acquire?(state, nil) do
    state.global_tokens > 0
  end

  defp can_acquire?(state, chat_id) do
    chat_key = to_string(chat_id)
    chat_bucket = Map.get(state.chat_buckets, chat_key, %{tokens: state.chat_limit, last_refill: 0})

    state.global_tokens > 0 and chat_bucket.tokens > 0
  end

  defp time_until_refill(last_refill, window) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - last_refill
    max(window - elapsed, 0)
  end

  defp build_chat_status(chat_buckets, state) do
    Map.new(chat_buckets, fn {chat_id, bucket} ->
      {chat_id,
       %{
         remaining: bucket.tokens,
         limit: state.chat_limit,
         reset_in: time_until_refill(bucket.last_refill, state.chat_window)
       }}
    end)
  end
end