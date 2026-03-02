defmodule Lux.Integrations.Telegram.PollingTest do
  use UnitAPICase, async: true

  alias Lux.Integrations.Telegram.Polling

  # Test handler module
  defmodule TestHandler do
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end

    def init(_) do
      {:ok, %{updates: []}}
    end

    def handle_update(update, state) do
      GenServer.call(__MODULE__, {:update, update})
      {:ok, state}
    end

    def handle_call({:update, update}, _from, %{updates: updates} = state) do
      {:reply, :ok, %{state | updates: [update | updates]}}
    end

    def handle_call(:get_updates, _from, %{updates: updates} = state) do
      {:reply, Enum.reverse(updates), state}
    end

    def get_updates do
      GenServer.call(__MODULE__, :get_updates)
    end
  end

  setup do
    Req.Test.verify_on_exit!()
    {:ok, handler_pid} = TestHandler.start_link([])
    %{handler: handler_pid}
  end

  describe "start_link/1" do
    test "starts polling process", %{handler: handler} do
      Req.Test.expect(TelegramClientMock, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/bottest_token/getUpdates"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => []
        }))
      end)

      assert {:ok, pid} = Polling.start_link(
        token: "test_token",
        handler: TestHandler,
        poll_interval: 10
      )

      assert Process.alive?(pid)
      Polling.stop(pid)
    end
  end

  describe "get_status/1" do
    test "returns polling status" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => []
        }))
      end)

      {:ok, pid} = Polling.start_link(
        token: "test_token",
        handler: TestHandler,
        poll_interval: 10
      )

      status = Polling.get_status(pid)
      assert is_map(status)
      assert status.is_polling == true
      assert status.total_updates == 0

      Polling.stop(pid)
    end
  end

  describe "pause/1 and resume/1" do
    test "pauses and resumes polling" do
      Req.Test.expect(TelegramClientMock, 1, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => []
        }))
      end)

      {:ok, pid} = Polling.start_link(
        token: "test_token",
        handler: TestHandler,
        poll_interval: 10
      )

      # Give it time to make one request
      Process.sleep(50)

      # Pause
      :ok = Polling.pause(pid)

      status = Polling.get_status(pid)
      assert status.is_polling == false

      # Resume
      :ok = Polling.resume(pid)

      status = Polling.get_status(pid)
      assert status.is_polling == true

      Polling.stop(pid)
    end
  end

  describe "update handling" do
    test "processes updates from Telegram" do
      Req.Test.expect(TelegramClientMock, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => [
            %{
              "update_id" => 1,
              "message" => %{
                "message_id" => 100,
                "text" => "Hello!"
              }
            }
          ]
        }))
      end)

      Req.Test.expect(TelegramClientMock, fn conn ->
        # Check that offset is set correctly
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["offset"] == 2

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "ok" => true,
          "result" => []
        }))
      end)

      {:ok, pid} = Polling.start_link(
        token: "test_token",
        handler: TestHandler,
        poll_interval: 10
      )

      # Give it time to process
      Process.sleep(100)

      status = Polling.get_status(pid)
      assert status.total_updates >= 1
      assert status.last_update_id == 1

      Polling.stop(pid)
    end
  end
end