defmodule Lux.Lenses.Twitter.Tweets.ReadTweetTest do
  use UnitCase, async: true

  alias Lux.Lenses.Twitter.Tweets.ReadTweet

  describe "focus/1" do
    test "successfully reads a tweet" do
      expect(Lux.Lens, :focus, fn _lens, params ->
        assert params.id == "123456789"
        
        {:ok, %{
          "data" => %{
            "id" => "123456789",
            "text" => "Hello, World!",
            "author_id" => "987654321",
            "created_at" => "2024-01-01T00:00:00Z"
          }
        }}
      end)

      assert {:ok, result} = ReadTweet.focus(%{id: "123456789"})
      assert result.id == "123456789"
      assert result.text == "Hello, World!"
      assert result.author_id == "987654321"
    end

    test "returns error for non-existent tweet" do
      expect(Lux.Lens, :focus, fn _lens, _params ->
        {:ok, %{
          "errors" => [%{
            "message" => "Tweet not found",
            "code" => 404
          }]
        }}
      end)

      assert {:error, %{errors: errors}} = ReadTweet.focus(%{id: "nonexistent"})
      assert length(errors) > 0
    end
  end
end
