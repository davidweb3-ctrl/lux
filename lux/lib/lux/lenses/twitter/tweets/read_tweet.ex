defmodule Lux.Lenses.Twitter.Tweets.ReadTweet do
  @moduledoc """
  A lens for reading tweets via Twitter API v2.
  
  ## Examples
      iex> ReadTweet.focus(%{
      ...>   id: "123456789"
      ...> })
      {:ok, %{
        id: "123456789",
        text: "Hello, Twitter!",
        author_id: "987654321",
        created_at: "2024-01-01T00:00:00Z"
      }}
  """

  alias Lux.Integrations.Twitter

  use Lux.Lens,
    name: "Read Tweet",
    description: "Reads a tweet by ID via Twitter API v2",
    url: "#{Twitter.base_url()}/tweets/:id",
    method: :get,
    headers: Twitter.headers(),
    auth: Twitter.auth(),
    schema: %{
      type: :object,
      properties: %{
        id: %{
          type: :string,
          description: "The ID of the tweet to read"
        }
      },
      required: ["id"]
    }

  @impl true
  def after_focus(%{"data" => data}) do
    {:ok, %{
      id: data["id"],
      text: data["text"],
      author_id: data["author_id"],
      created_at: data["created_at"]
    }}
  end

  def after_focus(%{"errors" => errors}) do
    {:error, %{errors: errors}}
  end
end
