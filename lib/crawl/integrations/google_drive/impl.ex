defmodule Crawl.Integrations.GoogleDrive.Impl do
  @moduledoc """
  Default implementation using GoogleApi.Drive.
  """
  @behaviour Crawl.Integrations.GoogleDrive

  alias Crawl.Integrations.GoogleDrive.Client
  alias Crawl.Integrations.GoogleDrive.TokenProvider
  alias GoogleApi.Drive.V3
  alias GoogleApi.Drive.V3.Model.File, as: DriveFile

  require Logger

  @impl true
  def create_folder(name, parent_id) do
    file_metadata = %DriveFile{
      name: name,
      mimeType: "application/vnd.google-apps.folder",
      parents: [parent_id]
    }

    with {:ok, token} <- TokenProvider.fetch(source: :default),
         conn = V3.Connection.new(token.token),
         {:ok, file} <-
           Client.drive_files_create(conn, body: file_metadata, fields: "id") do
      {:ok, file.id}
    else
      error ->
        Logger.error("Failed to create folder '#{name}': #{inspect(error)}")
        handle_error(error)
    end
  rescue
    e ->
      Logger.error("Exception creating folder '#{name}': #{inspect(e)}")
      {:error, e}
  end

  @impl true
  def upload_file(path, name, parent_id, mime_type) do
    file_metadata = %DriveFile{
      name: name,
      parents: [parent_id],
      mimeType: mime_type
    }

    with {:ok, token} <- TokenProvider.fetch(source: :default),
         conn = V3.Connection.new(token.token),
         {:ok, file} <-
           Client.drive_files_create_simple(
             conn,
             "multipart",
             file_metadata,
             path,
             fields: "id"
           ) do
      {:ok, file.id}
    else
      error ->
        Logger.error("Failed to upload file '#{name}': #{inspect(error)}")
        handle_error(error)
    end
  rescue
    e ->
      Logger.error("Exception uploading file '#{name}': #{inspect(e)}")
      {:error, e}
  end

  defp handle_error({:error, reason}), do: {:error, reason}
  defp handle_error(reason), do: {:error, reason}
end
