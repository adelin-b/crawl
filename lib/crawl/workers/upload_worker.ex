defmodule Crawl.Workers.UploadWorker do
  @moduledoc """
  Worker for uploading crawled assets to Google Drive.
  """
  use Oban.Worker, queue: :default

  require Logger

  alias Crawl.Assets.Archiver
  alias Crawl.Integrations.GoogleDrive
  alias Crawl.Workers.UploadWebhookWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    url = args["url"]
    crawl_key = args["crawl_key"]
    zip_path = args["assets_zip_path"]
    parent_folder_id = Application.get_env(:crawl, :google_drive_folder_id)

    cond do
      is_nil(parent_folder_id) ->
        Logger.error("Missing Google Drive folder ID configuration")
        {:error, :missing_configuration}

      is_nil(zip_path) or not File.exists?(zip_path) ->
        Logger.error("Zip file not found: #{inspect(zip_path)}")
        {:error, :zip_not_found}

      true ->
        process_upload(url, crawl_key, zip_path, parent_folder_id)
    end
  end

  defp process_upload(url, crawl_key, zip_path, parent_folder_id) do
    temp_dir = Path.join(System.tmp_dir!(), "upload_#{crawl_key}")

    try do
      case Archiver.unzip(zip_path, temp_dir) do
        {:ok, _dest_dir} ->
          folder_name = generate_folder_name(url)

          case GoogleDrive.create_folder(folder_name, parent_folder_id) do
            {:ok, folder_id} ->
              Logger.info("Created folder '#{folder_name}' (ID: #{folder_id})")

              case recursive_upload(temp_dir, folder_id) do
                :ok ->
                  enqueue_webhook(url, crawl_key, folder_id)
                  :ok

                error ->
                  error
              end

            {:error, reason} ->
              Logger.error("Failed to create folder '#{folder_name}': #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Failed to unzip archive: #{inspect(reason)}")
          {:error, reason}
      end
    after
      File.rm_rf(temp_dir)
    end
  end

  defp recursive_upload(local_dir, parent_id) do
    local_dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn file, _acc ->
      process_entry(local_dir, file, parent_id)
    end)
  end

  defp process_entry(local_dir, file, parent_id) do
    path = Path.join(local_dir, file)

    if File.dir?(path) do
      handle_directory(path, file, parent_id)
    else
      handle_file(path, file, parent_id)
    end
  end

  defp handle_directory(path, name, parent_id) do
    case GoogleDrive.create_folder(name, parent_id) do
      {:ok, new_folder_id} ->
        case recursive_upload(path, new_folder_id) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp handle_file(path, name, parent_id) do
    mime_type = MIME.from_path(path)

    case GoogleDrive.upload_file(path, name, parent_id, mime_type) do
      {:ok, _file_id} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp generate_folder_name(url) do
    date = Date.utc_today() |> Date.to_string()
    slug = slugify_url(url)
    "#{slug}-#{date}"
  end

  defp slugify_url(url) do
    uri = URI.parse(url)
    host = uri.host |> String.replace(".", "-")
    path = uri.path || ""

    path_slug =
      path
      |> String.replace("/", "-")
      |> String.replace(~r/[^a-zA-Z0-9-]/, "")
      |> String.trim("-")

    if path_slug == "", do: host, else: "#{host}-#{path_slug}"
  end

  defp enqueue_webhook(url, crawl_key, folder_id) do
    %{
      "url" => url,
      "crawl_key" => crawl_key,
      "root_google_drive_folder_id" => folder_id
    }
    |> UploadWebhookWorker.new()
    |> Oban.insert()
  end
end
