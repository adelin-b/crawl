defmodule Crawl.Integrations.UploadWebhook do
  @moduledoc """
  Wrapper for sending webhooks after upload success.
  """

  @callback dispatch(String.t(), map()) :: {:ok, any()} | {:error, any()}

  def dispatch(url, payload) do
    impl().dispatch(url, payload)
  end

  defp impl do
    Application.get_env(:crawl, :upload_webhook, Crawl.Integrations.UploadWebhook.Impl)
  end
end
