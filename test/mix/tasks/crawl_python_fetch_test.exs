defmodule Mix.Tasks.Crawl.Python.FetchTest do
  use ExUnit.Case, async: false
  import Mox

  alias Mix.Tasks.Crawl.Python.Fetch

  @moduletag :tmp_dir

  defmodule HTTPClientMock do
    @callback get(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get(String.t()) :: {:ok, map()} | {:error, any()}
  end

  Mox.defmock(Crawl.HTTPClientMock, for: Mix.Tasks.Crawl.Python.FetchTest.HTTPClientMock)

  setup %{tmp_dir: tmp_dir} do
    # Override http_client
    Application.put_env(:crawl, :http_client, Crawl.HTTPClientMock)

    on_exit(fn ->
      Application.delete_env(:crawl, :http_client)
    end)

    %{dest: Path.join(tmp_dir, "python_crawler")}
  end

  describe "run/1" do
    test "fetches files successfully with explicit commit", %{dest: dest} do
      sha = "123456"
      repo = "test/repo"

      # Expect downloads for all required files
      Fetch.required_files()
      |> Enum.each(fn filename ->
        url = "https://raw.githubusercontent.com/#{repo}/#{sha}/#{filename}"

        Crawl.HTTPClientMock
        |> expect(:get, fn ^url ->
          {:ok, %{status: 200, body: "content of #{filename}"}}
        end)
      end)

      args = ["--commit", sha, "--repo", repo, "--dest", dest]
      Fetch.run(args)

      # Verify files
      assert File.exists?(Path.join(dest, "web_crawler.py"))
      assert File.read!(Path.join(dest, "web_crawler.py")) == "content of web_crawler.py"
      assert File.exists?(Path.join(dest, "manifest.json"))

      # Verify chmod
      stat = File.stat!(Path.join(dest, "web_crawler.py"))
      assert Bitwise.band(stat.mode, 0o111) != 0
    end

    test "resolves branch sha and fetches files", %{dest: dest} do
      branch = "feature-branch"
      repo = "test/repo"
      sha = "abcdef"

      # Mock branch resolution
      branch_url = "https://api.github.com/repos/#{repo}/commits/#{branch}"

      Crawl.HTTPClientMock
      |> expect(:get, fn ^branch_url, _opts ->
        {:ok, %{status: 200, body: %{"sha" => sha}}}
      end)

      # Expect downloads
      Fetch.required_files()
      |> Enum.each(fn filename ->
        url = "https://raw.githubusercontent.com/#{repo}/#{sha}/#{filename}"

        Crawl.HTTPClientMock
        |> expect(:get, fn ^url ->
          {:ok, %{status: 200, body: "content"}}
        end)
      end)

      args = ["--branch", branch, "--repo", repo, "--dest", dest]
      Fetch.run(args)
    end

    test "handles branch not found", %{dest: dest} do
      repo = "test/repo"
      branch = "missing"
      url = "https://api.github.com/repos/#{repo}/commits/#{branch}"

      Crawl.HTTPClientMock
      |> expect(:get, fn ^url, _opts ->
        {:ok, %{status: 404}}
      end)

      assert_raise Mix.Error, ~r/Branch 'missing' not found/, fn ->
        Fetch.run(["--branch", branch, "--repo", repo, "--dest", dest])
      end
    end

    test "handles branch resolution error", %{dest: dest} do
      repo = "test/repo"
      branch = "main"
      url = "https://api.github.com/repos/#{repo}/commits/#{branch}"

      Crawl.HTTPClientMock
      |> expect(:get, fn ^url, _opts ->
        {:error, :nxdomain}
      end)

      assert_raise Mix.Error, ~r/Failed to resolve branch SHA/, fn ->
        Fetch.run(["--branch", branch, "--repo", repo, "--dest", dest])
      end
    end

    test "handles unexpected branch response", %{dest: dest} do
      repo = "test/repo"
      branch = "main"
      url = "https://api.github.com/repos/#{repo}/commits/#{branch}"

      Crawl.HTTPClientMock
      |> expect(:get, fn ^url, _opts ->
        {:ok, %{status: 500}}
      end)

      assert_raise Mix.Error, ~r/Unexpected response/, fn ->
        Fetch.run(["--branch", branch, "--repo", repo, "--dest", dest])
      end
    end

    test "handles file download 404", %{dest: dest} do
      sha = "123"
      repo = "test/repo"
      filename = List.first(Fetch.required_files())
      url = "https://raw.githubusercontent.com/#{repo}/#{sha}/#{filename}"

      Crawl.HTTPClientMock
      |> expect(:get, fn ^url ->
        {:ok, %{status: 404}}
      end)

      assert_raise Mix.Error, ~r/File '#{filename}' not found/, fn ->
        Fetch.run(["--commit", sha, "--repo", repo, "--dest", dest])
      end
    end

    test "handles file download error", %{dest: dest} do
      sha = "123"
      repo = "test/repo"
      filename = List.first(Fetch.required_files())
      url = "https://raw.githubusercontent.com/#{repo}/#{sha}/#{filename}"

      Crawl.HTTPClientMock
      |> expect(:get, fn ^url ->
        {:error, :econnrefused}
      end)

      assert_raise Mix.Error, ~r/Failed to download/, fn ->
        Fetch.run(["--commit", sha, "--repo", repo, "--dest", dest])
      end
    end

    test "handles unexpected file download response", %{dest: dest} do
      sha = "123"
      repo = "test/repo"
      filename = List.first(Fetch.required_files())
      url = "https://raw.githubusercontent.com/#{repo}/#{sha}/#{filename}"

      Crawl.HTTPClientMock
      |> expect(:get, fn ^url ->
        {:ok, %{status: 500}}
      end)

      assert_raise Mix.Error, ~r/Unexpected response/, fn ->
        Fetch.run(["--commit", sha, "--repo", repo, "--dest", dest])
      end
    end
  end
end
