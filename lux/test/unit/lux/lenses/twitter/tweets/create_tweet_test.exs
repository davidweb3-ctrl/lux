defmodule Lux.Lenses.Twitter.Tweets.CreateTweetTest do
  use UnitCase, async: true

  alias Lux.Lenses.Twitter.Tweets.CreateTweet

  describe "focus/1" do
    test "successfully creates a tweet" do
      # Mock the API response
      expect(Lux.Lens, :focus, fn _lens, params ->
        assert params.text == "Hello, Twitter!"
        
        {:ok, %{
          "data" => %{
            "id" => "123456789",
            "text" => "Hello, Twitter!",
            "created_at" => "2024-01-01T00:00:00Z"
          }
        }}
      end)

      assert {:ok, result} = CreateTweet.focus(%{text: "Hello, Twitter!"})
      assert result.id == "123456789"
      assert result.text == "Hello, Twitter!"
      assert result.created_at == "2024-01-01T00:00:00Z"
    end

    test "returns error for invalid tweet text" do
      expect(Lux.Lens, :focus, fn _lens, _params ->
        {:ok, %{
          "errors" => [%{
            "message" => "Tweet text is required",
            "code" => 400
          }]
        }}
      end)

      assert {:error, %{errors: errors}} = CreateTweet.focus(%{text: ""})
      assert length(errors) > 0
    end

    test "validates text length (max 280 characters)" do
      long_text = String.duplicate("a", 281)
      
      # Schema validation should catch this before API call
      assert {:error, _} = CreateTweet.focus(%{text: long_text})
    end
  end

  describe "after_focus/1" do
    test "transforms successful response" do
      response = %{
        "data" => %{
          "id" => "123",
          "text" => "Test",
          "created_at" => "2024-01-01T00:00:00Z"
        }
      }

      assert {:ok, result} = CreateTweet.after_focus(response)
      assert result.id == "123"
      assert result.text == "Test"
    end

    test "transforms error response" do
      response = %{
        "errors" => [%{"message" => "Unauthorized"}]
      }

      assert {:error, %{errors: _}} = CreateTweet.after_focus(response)
    end
  end
end
