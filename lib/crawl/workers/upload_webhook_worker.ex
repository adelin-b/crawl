defmodule Crawl.Workers.UploadWebhookWorker do
  @moduledoc """
  Worker for sending a webhook payload after a successful upload.
  """
  use Oban.Worker, queue: :webhook

  require Logger

  alias Crawl.Integrations.UploadWebhook

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    root_google_drive_folder_id = args["root_google_drive_folder_id"]
    url = args["url"]
    crawl_key = args["crawl_key"]

    webhook_url = Application.get_env(:crawl, :upload_webhook_url)

    cond do
      is_nil(webhook_url) or String.trim(webhook_url) == "" ->
        Logger.info("Webhook URL not configured. Skipping webhook dispatch.")
        :ok

      is_nil(root_google_drive_folder_id) or is_nil(url) or is_nil(crawl_key) ->
        Logger.error("Missing required arguments for UploadWebhookWorker")
        {:error, :missing_arguments}

      true ->
        payload = %{
          "root_google_drive_folder_id" => root_google_drive_folder_id,
          "url" => url,
          "crawl_key" => crawl_key
        }

        Logger.info("Dispatching webhook to #{webhook_url} for crawl_key #{crawl_key}")

        case UploadWebhook.dispatch(webhook_url, payload) do
          {:ok, _response} ->
            Logger.info("Successfully dispatched webhook for crawl_key #{crawl_key}")
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to dispatch webhook for crawl_key #{crawl_key}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end
end
