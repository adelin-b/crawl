defmodule Crawl.Workers.CrawlerTest do
  use Crawl.DataCase, async: true
  import Mox

  alias Crawl.Workers.Crawler
  alias Crawl.Workers.UploadWorker

  setup :verify_on_exit!

  setup do
    artifact_dir = Application.get_env(:crawl, :artifact_dir) || "test/tmp/artifacts"
    File.rm_rf!(artifact_dir)
    File.mkdir_p!(artifact_dir)

    on_exit(fn ->
      File.rm_rf!(artifact_dir)
    end)

    {:ok, artifact_dir: artifact_dir}
  end

  describe "perform/1" do
    test "crawls URL, zips assets, and enqueues upload job", %{artifact_dir: artifact_dir} do
      url = "https://example.com"
      page_id = "page_123"

      # Mock the Python crawler execution
      Crawl.Integrations.PythonCrawlerMock
      |> expect(:run, fn ^url, output_dir ->
        # Create dummy files in the output directory to simulate crawler output
        page_dir = Path.join([output_dir, "pages", page_id])
        File.mkdir_p!(page_dir)

        File.write!(Path.join(page_dir, "page.md"), "# Page Content")

        pdf_dir = Path.join(page_dir, "pdfs")
        File.mkdir_p!(pdf_dir)
        File.write!(Path.join(pdf_dir, "doc.pdf"), "PDF Content")

        pdf_md_dir = Path.join(page_dir, "pdf_markdown")
        File.mkdir_p!(pdf_md_dir)
        File.write!(Path.join(pdf_md_dir, "doc.md"), "# PDF Markdown")

        img_dir = Path.join([page_dir, "images", "doc"])
        File.mkdir_p!(img_dir)
        File.write!(Path.join(img_dir, "image.png"), "Image Content")

        {:ok, %{pages: [%{id: page_id, url: url}]}}
      end)

      # Execute the worker
      assert :ok = perform_job(Crawler, %{"url" => url})

      # Verify UploadWorker is enqueued
      assert_enqueued(worker: UploadWorker, args: %{"url" => url})

      # Get the enqueued job to check args
      job = all_enqueued(worker: UploadWorker) |> List.first()
      assert job.args["crawl_key"]
      assert job.args["assets_zip_path"]

      zip_path = job.args["assets_zip_path"]
      assert String.starts_with?(zip_path, artifact_dir)
      assert File.exists?(zip_path)

      # Verify zip content
      {:ok, files} = :zip.unzip(String.to_charlist(zip_path), [:memory])
      filenames = files |> Enum.map(fn {name, _content} -> to_string(name) end)

      assert Enum.any?(filenames, &String.ends_with?(&1, "page.md"))
      assert Enum.any?(filenames, &String.ends_with?(&1, "doc.pdf"))
      assert Enum.any?(filenames, &String.ends_with?(&1, "doc.md"))
      assert Enum.any?(filenames, &String.ends_with?(&1, "image.png"))

      # Ensure structure is preserved (path includes page_id)
      assert Enum.any?(filenames, &String.contains?(&1, "pages/#{page_id}/"))
    end

    test "handles crawler errors gracefully", %{artifact_dir: _artifact_dir} do
      url = "https://example.com/error"

      Crawl.Integrations.PythonCrawlerMock
      |> expect(:run, fn ^url, _output_dir ->
        {:error, "Crawl failed"}
      end)

      # Expect perform to return error tuple or raise, Oban handles retries based on return
      assert {:error, "Crawl failed"} = perform_job(Crawler, %{"url" => url})

      refute_enqueued(worker: UploadWorker)
    end
  end
end
