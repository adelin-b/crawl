defmodule Crawl.Integrations.GoogleDriveTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mox

  alias Crawl.Integrations.GoogleDrive
  alias Crawl.Integrations.GoogleDrive.ClientMock
  alias Crawl.Integrations.GoogleDrive.TokenProviderMock
  alias GoogleApi.Drive.V3.Model.File, as: DriveFile

  setup :verify_on_exit!

  setup do
    original_impl = Application.get_env(:crawl, :google_drive)
    original_token = Application.get_env(:crawl, :goth_token_provider)
    original_client = Application.get_env(:crawl, :google_drive_client)

    on_exit(fn ->
      restore_env(:google_drive, original_impl)
      restore_env(:goth_token_provider, original_token)
      restore_env(:google_drive_client, original_client)
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:crawl, key)
  defp restore_env(key, val), do: Application.put_env(:crawl, key, val)

  describe "default implementation logic" do
    setup do
      Application.delete_env(:crawl, :google_drive)
      Application.put_env(:crawl, :goth_token_provider, TokenProviderMock)
      Application.put_env(:crawl, :google_drive_client, ClientMock)
      :ok
    end

    test "create_folder/2 succeeds" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:drive_files_create, fn _conn, params, _opts ->
        assert params[:body].name == "test_folder"
        assert params[:body].mimeType == "application/vnd.google-apps.folder"
        assert params[:body].parents == ["parent_id"]
        {:ok, %DriveFile{id: "folder_id"}}
      end)

      assert {:ok, "folder_id"} = GoogleDrive.create_folder("test_folder", "parent_id")
    end

    test "create_folder/2 handles error" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:drive_files_create, fn _conn, _params, _opts ->
        {:error, :api_error}
      end)

      log =
        capture_log(fn ->
          assert {:error, :api_error} = GoogleDrive.create_folder("test_folder", "parent_id")
        end)

      assert log =~ "Failed to create folder 'test_folder'"
    end

    test "upload_file/4 succeeds" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:drive_files_create_simple, fn _conn, type, metadata, path, _params, _opts ->
        assert type == "multipart"
        assert metadata.name == "file.txt"
        assert metadata.parents == ["parent_id"]
        assert path == "/path/to/file.txt"
        {:ok, %DriveFile{id: "file_id"}}
      end)

      assert {:ok, "file_id"} =
               GoogleDrive.upload_file("/path/to/file.txt", "file.txt", "parent_id", "text/plain")
    end

    test "upload_file/4 handles error" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:drive_files_create_simple, fn _conn, _type, _metadata, _path, _params, _opts ->
        {:error, :upload_failed}
      end)

      log =
        capture_log(fn ->
          assert {:error, :upload_failed} =
                   GoogleDrive.upload_file(
                     "/path/to/file.txt",
                     "file.txt",
                     "parent_id",
                     "text/plain"
                   )
        end)

      assert log =~ "Failed to upload file 'file.txt'"
    end
  end
end
