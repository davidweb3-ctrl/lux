defmodule Lux.Prisms.Telegram.Bot.GetMe do
  @moduledoc """
  A prism for getting information about the bot.

  ## Examples

      iex> GetMe.handler(%{}, %{name: "Agent"})
      {:ok, %{
        id: 123_456_789,
        is_bot: true,
        first_name: "My Bot",
        username: "my_bot",
        can_join_groups: true,
        can_read_all_group_messages: false,
        supports_inline_queries: true
      }}
  """

  use Lux.Prism,
    name: "Get Bot Info",
    description: "Gets information about the bot",
    input_schema: %{
      type: :object,
      properties: %{}
    },
    output_schema: %{
      type: :object,
      properties: %{
        id: %{type: :integer},
        is_bot: %{type: :boolean},
        first_name: %{type: :string},
        username: %{type: :string},
        can_join_groups: %{type: :boolean},
        can_read_all_group_messages: %{type: :boolean},
        supports_inline_queries: %{type: :boolean}
      },
      required: ["id", "is_bot", "first_name", "username"]
    }

  alias Lux.Integrations.Telegram.Client
  require Logger

  @doc """
  Handles the request to get bot information.
  """
  def handler(_params, agent) do
    agent_name = agent[:name] || "Unknown Agent"
    Logger.info("Agent #{agent_name} requesting bot info")

    case Client.request(:get, "/getMe", %{}) do
      {:ok, %{"ok" => true, "result" => result}} ->
        {:ok,
         %{
           id: result["id"],
           is_bot: result["is_bot"],
           first_name: result["first_name"],
           username: result["username"],
           can_join_groups: result["can_join_groups"] || false,
           can_read_all_group_messages: result["can_read_all_group_messages"] || false,
           supports_inline_queries: result["supports_inline_queries"] || false
         }}

      {:error, {status, message}} ->
        Logger.error("Failed to get bot info: #{status} - #{message}")
        {:error, {status, message}}

      {:error, error} ->
        Logger.error("Failed to get bot info: #{inspect(error)}")
        {:error, error}
    end
  end
end