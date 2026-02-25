defmodule Crawl.Workers.UploadWebhookWorkerTest do
  use Crawl.DataCase, async: true
  import Mox

  alias Crawl.Workers.UploadWebhookWorker

  setup :verify_on_exit!

  describe "perform/1" do
    test "sends webhook successfully when URL is configured" do
      Application.put_env(:crawl, :upload_webhook_url, "https://webhook.example.com/endpoint")

      Crawl.Integrations.UploadWebhookMock
      |> expect(:dispatch, fn "https://webhook.example.com/endpoint", payload ->
        assert payload["root_google_drive_folder_id"] == "folder_123"
        assert payload["url"] == "https://example.com"
        assert payload["crawl_key"] == "crawl_abc"
        {:ok, %{}}
      end)

      assert :ok =
               perform_job(UploadWebhookWorker, %{
                 "root_google_drive_folder_id" => "folder_123",
                 "url" => "https://example.com",
                 "crawl_key" => "crawl_abc"
               })

      Application.delete_env(:crawl, :upload_webhook_url)
    end

    test "skips execution and returns :ok when webhook url is not configured" do
      Application.delete_env(:crawl, :upload_webhook_url)

      assert :ok =
               perform_job(UploadWebhookWorker, %{
                 "root_google_drive_folder_id" => "folder_123",
                 "url" => "https://example.com",
                 "crawl_key" => "crawl_abc"
               })
    end

    test "skips execution and returns :ok when webhook url is empty string" do
      Application.put_env(:crawl, :upload_webhook_url, "")

      assert :ok =
               perform_job(UploadWebhookWorker, %{
                 "root_google_drive_folder_id" => "folder_123",
                 "url" => "https://example.com",
                 "crawl_key" => "crawl_abc"
               })

      Application.delete_env(:crawl, :upload_webhook_url)
    end

    test "returns error if required args are missing" do
      Application.put_env(:crawl, :upload_webhook_url, "https://webhook.example.com/endpoint")

      assert {:error, :missing_arguments} =
               perform_job(UploadWebhookWorker, %{
                 "url" => "https://example.com",
                 "crawl_key" => "crawl_abc"
                 # missing root_google_drive_folder_id
               })

      Application.delete_env(:crawl, :upload_webhook_url)
    end

    test "returns error when webhook send fails" do
      Application.put_env(:crawl, :upload_webhook_url, "https://webhook.example.com/endpoint")

      Crawl.Integrations.UploadWebhookMock
      |> expect(:dispatch, fn _url, _payload ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               perform_job(UploadWebhookWorker, %{
                 "root_google_drive_folder_id" => "folder_123",
                 "url" => "https://example.com",
                 "crawl_key" => "crawl_abc"
               })

      Application.delete_env(:crawl, :upload_webhook_url)
    end
  end
end
