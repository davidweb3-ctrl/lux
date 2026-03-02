defmodule Lux.Prisms.Telegram.Bot.SetWebhook do
  @moduledoc """
  A prism for setting the bot's webhook.

  ## Examples

      iex> SetWebhook.handler(%{
      ...>   url: "https://myapp.com/webhook"
      ...> }, %{name: "Agent"})
      {:ok, %{set: true}}

      iex> SetWebhook.handler(%{
      ...>   url: "https://myapp.com/webhook",
      ...>   max_connections: 20,
      ...>   allowed_updates: ["message", "callback_query"],
      ...>   secret_token: "my_secret"
      ...> }, %{name: "Agent"})
      {:ok, %{set: true}}
  """

  use Lux.Prism,
    name: "Set Telegram Webhook",
    description: "Sets the webhook URL for the bot",
    input_schema: %{
      type: :object,
      properties: %{
        url: %{
          type: :string,
          description: "HTTPS URL to send updates to",
          pattern: "^https://"
        },
        max_connections: %{
          type: :integer,
          description: "Maximum allowed number of simultaneous HTTPS connections",
          minimum: 1,
          maximum: 40
        },
        allowed_updates: %{
          type: :array,
          description: "List of the update types you want your bot to receive",
          items: %{type: :string}
        },
        drop_pending_updates: %{
          type: :boolean,
          description: "Drop all pending updates"
        },
        secret_token: %{
          type: :string,
          description: "A secret token to be sent in a header for verification",
          minLength: 1,
          maxLength: 256
        }
      },
      required: ["url"]
    },
    output_schema: %{
      type: :object,
      properties: %{
        set: %{type: :boolean}
      },
      required: ["set"]
    }

  alias Lux.Integrations.Telegram.Webhook
  require Logger

  @doc """
  Handles the request to set the webhook.
  """
  def handler(params, agent) do
    agent_name = agent[:name] || "Unknown Agent"
    Logger.info("Agent #{agent_name} setting webhook to #{params.url}")

    opts = %{
      max_connections: params[:max_connections],
      allowed_updates: params[:allowed_updates],
      drop_pending_updates: params[:drop_pending_updates],
      secret_token: params[:secret_token]
    }

    # Remove nil values
    opts = Enum.into(opts, %{}, fn {k, v} -> if v != nil, do: {k, v}, else: nil end) |> Enum.reject(&is_nil/1) |> Enum.into(%{})

    case Webhook.set_webhook(params.url, nil, opts) do
      {:ok, %{"ok" => true}} ->
        Logger.info("Successfully set webhook to #{params.url}")
        {:ok, %{set: true}}

      {:error, {status, message}} ->
        Logger.error("Failed to set webhook: #{status} - #{message}")
        {:error, {status, message}}

      {:error, error} ->
        Logger.error("Failed to set webhook: #{inspect(error)}")
        {:error, error}
    end
  end
end