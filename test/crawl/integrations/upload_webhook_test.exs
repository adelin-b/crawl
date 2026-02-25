defmodule Crawl.Integrations.UploadWebhookTest do
  use ExUnit.Case, async: false

  alias Crawl.Integrations.UploadWebhook

  # Define a stub implementation to test the delegation
  defmodule Stub do
    @behaviour Crawl.Integrations.UploadWebhook

    @impl true
    def dispatch(url, payload) do
      send(self(), {:stub_dispatch, url, payload})
      {:ok, %{response: "ok"}}
    end
  end

  setup do
    original_impl = Application.get_env(:crawl, :upload_webhook)

    on_exit(fn ->
      if original_impl do
        Application.put_env(:crawl, :upload_webhook, original_impl)
      else
        Application.delete_env(:crawl, :upload_webhook)
      end
    end)

    :ok
  end

  describe "delegation" do
    test "dispatch/2 delegates to configured implementation" do
      Application.put_env(:crawl, :upload_webhook, Stub)

      assert {:ok, %{response: "ok"}} = UploadWebhook.dispatch("http://example.com", %{"a" => 1})
      assert_received {:stub_dispatch, "http://example.com", %{"a" => 1}}
    end
  end

  # The actual Req implementation could be tested if we use Tesla mock or bypass.
  # Since Req is used directly, testing HTTP failures might require Bypass.
  # We'll skip complex Req mock tests here and rely on the fact that the impl uses Req correctly.
end
