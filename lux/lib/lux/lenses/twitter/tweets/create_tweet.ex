defmodule Lux.Lenses.Twitter.Tweets.CreateTweet do
  @moduledoc """
  A lens for creating tweets via Twitter API v2.
  
  ## Examples
      iex> CreateTweet.focus(%{
      ...>   text: "Hello, Twitter!"
      ...> })
      {:ok, %{
        id: "123456789",
        text: "Hello, Twitter!",
        created_at: "2024-01-01T00:00:00Z"
      }}
  """

  alias Lux.Integrations.Twitter

  use Lux.Lens,
    name: "Create Tweet",
    description: "Creates a new tweet via Twitter API v2",
    url: "#{Twitter.base_url()}/tweets",
    method: :post,
    headers: Twitter.headers(),
    auth: Twitter.auth(),
    schema: %{
      type: :object,
      properties: %{
        text: %{
          type: :string,
          description: "The content of the tweet (max 280 characters)",
          maxLength: 280
        }
      },
      required: ["text"]
    }

  @impl true
  def after_focus(%{"data" => data}) do
    {:ok, %{
      id: data["id"],
      text: data["text"],
      created_at: data["created_at"]
    }}
  end

  def after_focus(%{"errors" => errors}) do
    {:error, %{errors: errors}}
  end
end
