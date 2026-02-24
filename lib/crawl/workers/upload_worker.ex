defmodule Crawl.Workers.UploadWorker do
  @moduledoc """
  Worker for uploading crawled assets to Google Drive.
  """
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    :ok
  end
end
