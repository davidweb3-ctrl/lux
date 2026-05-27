defmodule Lux.Lenses.Twitter.Tweets.DeleteTweet do
  @moduledoc """
  A lens for deleting tweets via Twitter API v2.
  
  ## Examples
      iex> DeleteTweet.focus(%{
      ...>   id: "123456789"
      ...> })
      {:ok, %{deleted: true}}
  """

  alias Lux.Integrations.Twitter

  use Lux.Lens,
    name: "Delete Tweet",
    description: "Deletes a tweet by ID via Twitter API v2",
    url: "#{Twitter.base_url()}/tweets/:id",
    method: :delete,
    headers: Twitter.headers(),
    auth: Twitter.auth(),
    schema: %{
      type: :object,
      properties: %{
        id: %{
          type: :string,
          description: "The ID of the tweet to delete"
        }
      },
      required: ["id"]
    }

  @type delete_response :: %{deleted: boolean()}
  @type error_response :: %{errors: list(map())}

  @impl true
  @spec after_focus(map()) :: {:ok, delete_response()} | {:error, error_response()}
  def after_focus(%{"data" => %{"deleted" => true}}) do
    {:ok, %{deleted: true}}
  end

  def after_focus(%{"errors" => errors}) do
    {:error, %{errors: errors}}
  end
end
