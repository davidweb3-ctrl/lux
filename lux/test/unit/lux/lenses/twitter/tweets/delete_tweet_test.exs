defmodule Lux.Lenses.Twitter.Tweets.DeleteTweetTest do
  use UnitCase, async: true

  alias Lux.Lenses.Twitter.Tweets.DeleteTweet

  describe "focus/1" do
    test "successfully deletes a tweet" do
      expect(Lux.Lens, :focus, fn _lens, params ->
        assert params.id == "123456789"
        
        {:ok, %{
          "data" => %{
            "deleted" => true
          }
        }}
      end)

      assert {:ok, result} = DeleteTweet.focus(%{id: "123456789"})
      assert result.deleted == true
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

      assert {:error, %{errors: errors}} = DeleteTweet.focus(%{id: "nonexistent"})
      assert length(errors) > 0
    end

    test "returns error for unauthorized deletion" do
      expect(Lux.Lens, :focus, fn _lens, _params ->
        {:ok, %{
          "errors" => [%{
            "message" => "Unauthorized",
            "code" => 401
          }]
        }}
      end)

      assert {:error, %{errors: errors}} = DeleteTweet.focus(%{id: "123"})
      assert hd(errors)["code"] == 401
    end
  end

  describe "after_focus/1" do
    test "transforms successful deletion response" do
      response = %{
        "data" => %{"deleted" => true}
      }

      assert {:ok, result} = DeleteTweet.after_focus(response)
      assert result.deleted == true
    end

    test "transforms error response" do
      response = %{
        "errors" => [%{"message" => "Not found"}]
      }

      assert {:error, %{errors: _}} = DeleteTweet.after_focus(response)
    end
  end
end
