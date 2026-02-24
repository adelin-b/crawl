defmodule Crawl.Workers.Crawler do
  @moduledoc """
  Worker for crawling a specific candidate URL.
  """
  use Oban.Worker, queue: :crawler

  require Logger

  alias Crawl.Assets.Archiver
  alias Crawl.Integrations.PythonCrawler
  alias Crawl.Workers.UploadWorker

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"url" => url}}) do
    Logger.info("Starting crawl for URL: #{url}")

    # Create a unique temporary directory for this job
    temp_dir = Path.join(System.tmp_dir!(), "crawl_#{job_id}_#{Ecto.UUID.generate()}")
    File.mkdir_p!(temp_dir)

    try do
      case PythonCrawler.run(url, temp_dir) do
        {:ok, _metadata} ->
          handle_success(url, job_id, temp_dir)

        {:error, reason} ->
          Logger.error("Crawl failed for #{url}: #{inspect(reason)}")
          {:error, reason}
      end
    after
      File.rm_rf(temp_dir)
    end
  end

  defp handle_success(url, job_id, temp_dir) do
    crawl_key = "crawl_#{job_id}_#{Ecto.UUID.generate()}"
    zip_filename = "#{crawl_key}.zip"

    artifact_dir = Application.get_env(:crawl, :artifact_dir) || "/tmp/crawl_artifacts"
    zip_path = Path.join(artifact_dir, zip_filename)

    # Zip the assets
    case Archiver.zip_directory(temp_dir, zip_path) do
      {:ok, zip_path} ->
        Logger.info("Assets zipped to #{zip_path}")

        # Enqueue UploadWorker
        %{
          "url" => url,
          "crawl_key" => crawl_key,
          "assets_zip_path" => zip_path
        }
        |> UploadWorker.new()
        |> Oban.insert()

        :ok

      {:error, reason} ->
        Logger.error("Failed to zip assets: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
