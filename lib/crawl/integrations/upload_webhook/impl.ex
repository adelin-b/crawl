defmodule Crawl.Integrations.UploadWebhook.Impl do
  @moduledoc """
  Default implementation using Req for sending the webhook.
  """
  @behaviour Crawl.Integrations.UploadWebhook

  require Logger

  @impl true
  def dispatch(url, payload) do
    case Req.post(url, json: payload) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response.body}

      {:ok, %Req.Response{status: status} = response} ->
        Logger.error("Webhook returned non-success status #{status}: #{inspect(response.body)}")
        {:error, {:bad_status, status, response.body}}

      {:error, exception} ->
        Logger.error("Failed to send webhook to #{url}: #{inspect(exception)}")
        {:error, exception}
    end
  end
end
