defmodule Crawl.Workers.UploadWorkerTest do
  use Crawl.DataCase, async: true
  import Mox

  alias Crawl.Workers.UploadWebhookWorker
  alias Crawl.Workers.UploadWorker

  setup :verify_on_exit!

  setup do
    artifact_dir = "test/tmp/upload_worker_artifacts"
    File.rm_rf!(artifact_dir)
    File.mkdir_p!(artifact_dir)

    Application.put_env(:crawl, :google_drive_folder_id, "root_folder_id")

    on_exit(fn ->
      File.rm_rf!(artifact_dir)
      Application.delete_env(:crawl, :google_drive_folder_id)
    end)

    {:ok, artifact_dir: artifact_dir}
  end

  describe "perform/1" do
    test "unzips assets and uploads them to Google Drive", %{artifact_dir: artifact_dir} do
      url = "https://example.com/page"
      crawl_key = "crawl_key_123"
      zip_filename = "#{crawl_key}.zip"
      zip_path = Path.join(artifact_dir, zip_filename)

      # Create a dummy zip file
      create_dummy_zip(zip_path, artifact_dir)

      # Expect folder creation
      # The folder name should be derived from URL and date.
      # We'll use a regex to match the date part since it changes.
      Crawl.Integrations.GoogleDriveMock
      |> expect(:create_folder, fn name, parent_id ->
        assert name =~ ~r/example-com-page-\d{4}-\d{2}-\d{2}/
        assert parent_id == "root_folder_id"
        {:ok, "new_folder_id"}
      end)

      # Expect file uploads
      # We have file1.txt and file2.txt in the zip
      Crawl.Integrations.GoogleDriveMock
      |> expect(:upload_file, fn _path, name, parent_id, mime_type ->
        assert name == "file1.txt"
        assert parent_id == "new_folder_id"
        # or application/octet-stream
        assert mime_type == "text/plain"
        {:ok, "file1_id"}
      end)
      |> expect(:upload_file, fn _path, name, parent_id, _mime_type ->
        assert name == "file2.txt"
        assert parent_id == "new_folder_id"
        {:ok, "file2_id"}
      end)
      # We also have a subfolder 'sub' with file3.txt
      # So we expect a subfolder creation
      |> expect(:create_folder, fn name, parent_id ->
        assert name == "sub"
        assert parent_id == "new_folder_id"
        {:ok, "sub_folder_id"}
      end)
      # And upload inside that subfolder
      |> expect(:upload_file, fn _path, name, parent_id, _mime_type ->
        assert name == "file3.txt"
        assert parent_id == "sub_folder_id"
        {:ok, "file3_id"}
      end)

      # Execute the worker
      assert :ok =
               perform_job(UploadWorker, %{
                 "url" => url,
                 "crawl_key" => crawl_key,
                 "assets_zip_path" => zip_path
               })

      assert_enqueued(
        worker: UploadWebhookWorker,
        args: %{
          "url" => url,
          "crawl_key" => crawl_key,
          "root_google_drive_folder_id" => "new_folder_id"
        }
      )
    end

    test "handles missing configuration" do
      Application.delete_env(:crawl, :google_drive_folder_id)

      assert {:error, :missing_configuration} =
               perform_job(UploadWorker, %{
                 "url" => "url",
                 "crawl_key" => "key",
                 "assets_zip_path" => "path"
               })

      refute_enqueued(worker: UploadWebhookWorker)
    end

    test "handles missing zip file", %{artifact_dir: artifact_dir} do
      assert {:error, :zip_not_found} =
               perform_job(UploadWorker, %{
                 "url" => "url",
                 "crawl_key" => "key",
                 "assets_zip_path" => Path.join(artifact_dir, "missing.zip")
               })

      refute_enqueued(worker: UploadWebhookWorker)
    end

    test "handles drive api errors", %{artifact_dir: artifact_dir} do
      url = "https://example.com"
      crawl_key = "crawl_key_123"
      zip_filename = "#{crawl_key}.zip"
      zip_path = Path.join(artifact_dir, zip_filename)

      create_dummy_zip(zip_path, artifact_dir)

      Crawl.Integrations.GoogleDriveMock
      |> expect(:create_folder, fn _name, _parent_id ->
        {:error, :api_error}
      end)

      assert {:error, :api_error} =
               perform_job(UploadWorker, %{
                 "url" => url,
                 "crawl_key" => crawl_key,
                 "assets_zip_path" => zip_path
               })

      refute_enqueued(worker: UploadWebhookWorker)
    end
  end

  defp create_dummy_zip(zip_path, work_dir) do
    # Create some files to zip
    src_dir = Path.join(work_dir, "src")
    File.mkdir_p!(src_dir)
    File.write!(Path.join(src_dir, "file1.txt"), "content1")
    File.write!(Path.join(src_dir, "file2.txt"), "content2")

    sub_dir = Path.join(src_dir, "sub")
    File.mkdir_p!(sub_dir)
    File.write!(Path.join(sub_dir, "file3.txt"), "content3")

    # Zip them
    files =
      [
        "file1.txt",
        "file2.txt",
        "sub/file3.txt"
      ]
      |> Enum.map(&String.to_charlist/1)

    cwd = String.to_charlist(src_dir)
    {:ok, _} = :zip.create(String.to_charlist(zip_path), files, [{:cwd, cwd}])
  end
end
