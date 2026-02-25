defmodule Crawl.Integrations.GoogleDrive do
  @moduledoc """
  Wrapper for Google Drive API interactions.
  """

  @callback create_folder(String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  @callback upload_file(String.t(), String.t(), String.t(), String.t()) ::
              {:ok, String.t()} | {:error, any()}

  def create_folder(name, parent_id) do
    impl().create_folder(name, parent_id)
  end

  def upload_file(path, name, parent_id, mime_type) do
    impl().upload_file(path, name, parent_id, mime_type)
  end

  defp impl do
    Application.get_env(:crawl, :google_drive, Crawl.Integrations.GoogleDrive.Impl)
  end
end
