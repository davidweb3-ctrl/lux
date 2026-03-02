defmodule Lux.Integrations.Telegram.Polling do
  @moduledoc """
  Long polling implementation for receiving Telegram updates.

  This module provides an alternative to webhooks for receiving updates.
  It uses getUpdates method with long polling (timeout up to 50 seconds).

  ## Features

  - Automatic offset management
  - Configurable polling interval and timeout
  - Update filtering by type
  - Graceful shutdown
  - Error recovery with backoff

  ## Examples

      # Start polling with default options
      {:ok, pid} = Polling.start_link(token: "bot_token", handler: MyHandler)

      # Start with custom options
      {:ok, pid} = Polling.start_link(
        token: "bot_token",
        handler: MyHandler,
        timeout: 30,
        allowed_updates: ["message", "callback_query"],
        limit: 50
      )
  """

  use GenServer

  alias Lux.Integrations.Telegram.Client

  require Logger

  @default_timeout 30
  @default_limit 100
  @default_poll_interval 100
  @max_backoff 30_000

  @type handler :: module() | {module(), term()}
  @type opts :: %{
          token: String.t(),
          handler: handler(),
          optional(:timeout) => pos_integer(),
          optional(:limit) => pos_integer(),
          optional(:allowed_updates) => [String.t()],
          optional(:poll_interval) => pos_integer()
        }

  # Client API

  @doc """
  Starts the polling GenServer.

  ## Options
    * `:token` - Bot API token (required)
    * `:handler` - Module or {module, state} to handle updates (required)
    * `:timeout` - Long polling timeout in seconds (default: 30)
    * `:limit` - Max updates per request (default: 100)
    * `:allowed_updates` - List of update types (default: all)
    * `:poll_interval` - Interval between polls in ms (default: 100)

  ## Handler Callback

  The handler module must implement:
  - `handle_update(update, state)` - Receives each update

  ## Examples

      defmodule MyHandler do
        def handle_update(update, state) do
          IO.inspect(update)
          {:ok, state}
        end
      end

      {:ok, pid} = Polling.start_link(
        token: "bot_token",
        handler: MyHandler
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    token = Keyword.fetch!(opts, :token)
    name = opts[:name] || via_tuple(token)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stops the polling process.

  ## Examples

      iex> Polling.stop(pid)
      :ok
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  @doc """
  Gets current polling status.

  ## Examples

      iex> Polling.get_status(pid)
      %{
        last_update_id: 123456789,
        total_updates: 1000,
        is_polling: true
      }
  """
  @spec get_status(GenServer.server()) :: map()
  def get_status(server) do
    GenServer.call(server, :get_status)
  end

  @doc """
  Pauses polling without stopping the process.

  ## Examples

      iex> Polling.pause(pid)
      :ok
  """
  @spec pause(GenServer.server()) :: :ok
  def pause(server) do
    GenServer.cast(server, :pause)
  end

  @doc """
  Resumes polling after pause.

  ## Examples

      iex> Polling.resume(pid)
      :ok
  """
  @spec resume(GenServer.server()) :: :ok
  def resume(server) do
    GenServer.cast(server, :resume)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      token: opts[:token],
      handler: normalize_handler(opts[:handler]),
      timeout: opts[:timeout] || @default_timeout,
      limit: opts[:limit] || @default_limit,
      allowed_updates: opts[:allowed_updates],
      poll_interval: opts[:poll_interval] || @default_poll_interval,
      offset: nil,
      last_update_id: nil,
      total_updates: 0,
      is_polling: true,
      backoff: 0
    }

    # Start polling immediately
    send(self(), :poll)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      last_update_id: state.last_update_id,
      total_updates: state.total_updates,
      is_polling: state.is_polling
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:pause, state) do
    {:noreply, %{state | is_polling: false}}
  end

  @impl true
  def handle_cast(:resume, state) do
    send(self(), :poll)
    {:noreply, %{state | is_polling: true}}
  end

  @impl true
  def handle_info(:poll, %{is_polling: false} = state) do
    # Don't poll if paused
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    case fetch_updates(state) do
      {:ok, []} ->
        # No updates, poll again immediately
        send(self(), :poll)
        {:noreply, %{state | backoff: 0}}

      {:ok, updates} ->
        # Process updates
        new_state = process_updates(updates, state)
        send(self(), :poll)
        {:noreply, %{new_state | backoff: 0}}

      {:error, reason} ->
        Logger.error("Polling error: #{inspect(reason)}")
        backoff = min(state.backoff * 2 + 1000, @max_backoff)
        Process.sleep(backoff)
        send(self(), :poll)
        {:noreply, %{state | backoff: backoff}}
    end
  end

  # Private Functions

  defp via_tuple(token) do
    {:via, Registry, {Lux.Registry, {:telegram_polling, token}}}
  end

  defp normalize_handler({module, state}), do: {module, state}
  defp normalize_handler(module) when is_atom(module), do: {module, nil}

  defp fetch_updates(state) do
    params = %{
      timeout: state.timeout,
      limit: state.limit
    }

    params = if state.offset, do: Map.put(params, :offset, state.offset), else: params

    params = if state.allowed_updates, do: Map.put(params, :allowed_updates, state.allowed_updates), else: params

    case Client.request(:post, "/getUpdates", %{
           token: state.token,
           json: params
         }) do
      {:ok, %{"ok" => true, "result" => updates}} ->
        {:ok, updates}

      {:ok, %{"ok" => false, "description" => description}} ->
        {:error, description}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_updates(updates, state) do
    {module, handler_state} = state.handler

    {last_id, new_handler_state, count} =
      Enum.reduce(updates, {state.last_update_id, handler_state, 0}, fn update,
                                                                        {last_id, h_state, count} ->
        update_id = update["update_id"]

        try do
          case module.handle_update(update, h_state) do
            {:ok, new_state} -> {update_id, new_state, count + 1}
            _ -> {update_id, h_state, count + 1}
          end
        rescue
          error ->
            Logger.error("Handler error for update #{update_id}: #{inspect(error)}")
            {update_id, h_state, count + 1}
        end
      end)

    # Update offset for next poll (last_update_id + 1)
    new_offset = if last_id, do: last_id + 1, else: state.offset

    %{
      state
      | offset: new_offset,
        last_update_id: last_id,
        total_updates: state.total_updates + count,
        handler: {module, new_handler_state}
    }
  end
end