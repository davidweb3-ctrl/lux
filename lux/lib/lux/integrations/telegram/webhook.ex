defmodule Lux.Integrations.Telegram.Webhook do
  @moduledoc """
  Webhook management for Telegram Bot API.

  This module provides functions to configure and manage Telegram webhooks:
  - Set webhook URL
  - Get webhook info
  - Delete webhook
  - Handle webhook updates

  ## Webhook Security

  Telegram sends updates to your webhook with:
  - HTTPS only (required by Telegram)
  - IP range restrictions (can whitelist Telegram IPs)
  - Custom secret token in header (X-Telegram-Bot-Api-Secret-Token)

  ## Examples

      # Set webhook
      Webhook.set_webhook("https://myapp.com/webhook", "bot_token")

      # Get webhook info
      Webhook.get_webhook_info("bot_token")

      # Delete webhook
      Webhook.delete_webhook("bot_token")
  """

  alias Lux.Integrations.Telegram.Client

  require Logger

  @type webhook_opts :: %{
          optional(:max_connections) => pos_integer(),
          optional(:allowed_updates) => [String.t()],
          optional(:drop_pending_updates) => boolean(),
          optional(:secret_token) => String.t(),
          optional(:certificate) => String.t()
        }

  @doc """
  Sets the webhook for the bot.

  ## Options
    * `:max_connections` - Max concurrent connections (1-40, default: 40)
    * `:allowed_updates` - List of update types to receive (default: all)
    * `:drop_pending_updates` - Drop pending updates (default: false)
    * `:secret_token` - Secret token for webhook verification
    * `:certificate` - Path to self-signed certificate (if needed)

  ## Examples

      iex> Webhook.set_webhook("https://myapp.com/webhook", "bot_token")
      {:ok, %{"ok" => true, "result" => true}}

      iex> Webhook.set_webhook("https://myapp.com/webhook", "bot_token",
      ...>   max_connections: 20,
      ...>   allowed_updates: ["message", "callback_query"],
      ...>   secret_token: "my_secret"
      ...> )
      {:ok, %{"ok" => true, "result" => true}}
  """
  @spec set_webhook(String.t(), String.t(), webhook_opts()) :: {:ok, map()} | {:error, term()}
  def set_webhook(url, token, opts \\ %{}) do
    body = %{
      url: url
    }

    body =
      body
      |> maybe_add_param(opts, :max_connections)
      |> maybe_add_param(opts, :allowed_updates)
      |> maybe_add_param(opts, :drop_pending_updates)
      |> maybe_add_param(opts, :secret_token)

    # Handle certificate if provided
    body =
      if opts[:certificate] do
        # Certificate upload would require multipart/form-data
        # For now, we assume the certificate is handled separately
        Map.put(body, :certificate, opts[:certificate])
      else
        body
      end

    Client.request(:post, "/setWebhook", %{
      token: token,
      json: body
    })
  end

  @doc """
  Gets current webhook status.

  ## Examples

      iex> Webhook.get_webhook_info("bot_token")
      {:ok, %{
        "ok" => true,
        "result" => %{
          "url" => "https://myapp.com/webhook",
          "has_custom_certificate" => false,
          "pending_update_count" => 0,
          "max_connections" => 40
        }
      }}
  """
  @spec get_webhook_info(String.t()) :: {:ok, map()} | {:error, term()}
  def get_webhook_info(token) do
    Client.request(:get, "/getWebhookInfo", %{token: token})
  end

  @doc """
  Deletes the webhook and stops receiving updates.

  ## Options
    * `:drop_pending_updates` - Drop pending updates (default: false)

  ## Examples

      iex> Webhook.delete_webhook("bot_token")
      {:ok, %{"ok" => true, "result" => true}}

      iex> Webhook.delete_webhook("bot_token", drop_pending_updates: true)
      {:ok, %{"ok" => true, "result" => true}}
  """
  @spec delete_webhook(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def delete_webhook(token, opts \\ []) do
    body = %{}
    body = if opts[:drop_pending_updates], do: Map.put(body, :drop_pending_updates, true), else: body

    Client.request(:post, "/deleteWebhook", %{
      token: token,
      json: body
    })
  end

  @doc """
  Verifies webhook request signature/secret.

  Telegram sends a secret token in the X-Telegram-Bot-Api-Secret-Token header
  if configured. This function verifies that token matches.

  ## Examples

      iex> Webhook.verify_request(conn, "my_secret")
      :ok

      iex> Webhook.verify_request(conn, "wrong_secret")
      {:error, :invalid_secret}
  """
  @spec verify_request(Plug.Conn.t(), String.t()) :: :ok | {:error, term()}
  def verify_request(%Plug.Conn{} = conn, expected_secret) do
    actual_secret =
      conn
      |> Plug.Conn.get_req_header("x-telegram-bot-api-secret-token")
      |> List.first()

    if actual_secret == expected_secret do
      :ok
    else
      {:error, :invalid_secret}
    end
  end

  @doc """
  Parses webhook update from request body.

  ## Examples

      iex> Webhook.parse_update(conn)
      {:ok, %{
        "update_id" => 123456789,
        "message" => %{
          "message_id" => 1,
          "from" => %{"id" => 123, "first_name" => "John"},
          "chat" => %{"id" => 456, "type" => "private"},
          "text" => "Hello!"
        }
      }}
  """
  @spec parse_update(Plug.Conn.t()) :: {:ok, map()} | {:error, term()}
  def parse_update(%Plug.Conn{} = conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} ->
        case Jason.decode(body) do
          {:ok, update} -> {:ok, update}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      {:error, reason} ->
        {:error, {:read_body_failed, reason}}
    end
  end

  @doc """
  Returns list of Telegram IP ranges for webhook source validation.

  These are the IP ranges that Telegram uses to send webhook updates.

  ## Examples

      iex> Webhook.telegram_ip_ranges()
      ["149.154.160.0/20", "91.108.4.0/22"]
  """
  @spec telegram_ip_ranges() :: [String.t()]
  def telegram_ip_ranges do
    [
      "149.154.160.0/20",
      "91.108.4.0/22"
    ]
  end

  @doc """
  Checks if an IP address is from Telegram's webhook servers.

  ## Examples

      iex> Webhook.telegram_ip?("149.154.160.1")
      true

      iex> Webhook.telegram_ip?("192.168.1.1")
      false
  """
  @spec telegram_ip?(String.t()) :: boolean()
  def telegram_ip?(ip_address) when is_binary(ip_address) do
    telegram_ip_ranges()
    |> Enum.any?(fn range ->
      ip_in_range?(ip_address, range)
    end)
  end

  # Private Functions

  defp maybe_add_param(body, opts, key) do
    case opts[key] do
      nil -> body
      value -> Map.put(body, key, value)
    end
  end

  defp ip_in_range?(ip, cidr) do
    # Simple CIDR matching
    # In production, use a proper CIDR library like :inet_cidr
    [range_ip, mask] = String.split(cidr, "/")
    mask_bits = String.to_integer(mask)

    ip_parts = String.split(ip, ".") |> Enum.map(&String.to_integer/1)
    range_parts = String.split(range_ip, ".") |> Enum.map(&String.to_integer/1)

    ip_int = ip_to_integer(ip_parts)
    range_int = ip_to_integer(range_parts)

    mask_int = Bitwise.bsl(0xFFFFFFFF, 32 - mask_bits) &&& 0xFFFFFFFF

    (ip_int &&& mask_int) == (range_int &&& mask_int)
  end

  defp ip_to_integer([a, b, c, d]) do
    Bitwise.bsl(a, 24) + Bitwise.bsl(b, 16) + Bitwise.bsl(c, 8) + d
  end
end