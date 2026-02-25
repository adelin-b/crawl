defmodule Crawl.Integrations.PythonCrawler.PortTest do
  use ExUnit.Case, async: false

  alias Crawl.Integrations.PythonCrawler.Port

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Save current config to restore later
    orig_python = Application.get_env(:crawl, :python_executable)
    orig_path = Application.get_env(:crawl, :crawler_ingest_path)

    # We will use bash to "mock" the python executable.
    # The python_executable will just run our fake scripts as bash scripts.
    Application.put_env(:crawl, :python_executable, "bash")

    repo_dir = Path.join(tmp_dir, "fake_repo")
    File.mkdir_p!(repo_dir)
    Application.put_env(:crawl, :crawler_ingest_path, repo_dir)

    # Create dummy web_crawler.py
    crawler_script = Path.join(repo_dir, "web_crawler.py")

    File.write!(crawler_script, """
    #!/usr/bin/env bash
    # web_crawler.py mock
    # Usage: web_crawler.py <url> --output-folder <out_dir> --report <report_path> --quiet

    out_dir="$3"
    report_path="$5"

    exit 0
    """)

    File.chmod!(crawler_script, 0o755)

    # Create dummy pipeline.py
    pipeline_script = Path.join(repo_dir, "pipeline.py")

    File.write!(pipeline_script, """
    #!/usr/bin/env bash
    # pipeline.py mock
    exit 0
    """)

    File.chmod!(pipeline_script, 0o755)

    on_exit(fn ->
      if orig_python,
        do: Application.put_env(:crawl, :python_executable, orig_python),
        else: Application.delete_env(:crawl, :python_executable)

      if orig_path,
        do: Application.put_env(:crawl, :crawler_ingest_path, orig_path),
        else: Application.delete_env(:crawl, :crawler_ingest_path)
    end)

    %{repo_dir: repo_dir, out_dir: Path.join(tmp_dir, "output")}
  end

  describe "run/2" do
    test "handles crawler failure", %{repo_dir: repo_dir, out_dir: out_dir} do
      # Make crawler fail
      File.write!(Path.join(repo_dir, "web_crawler.py"), """
      #!/usr/bin/env bash
      echo "Failed to crawl" >&2
      exit 1
      """)

      assert {:error, "Crawler failed: Failed to crawl\n"} =
               Port.run("https://example.com", out_dir)
    end

    test "success without PDFs skips pipeline and report parsing if no report", %{
      out_dir: out_dir
    } do
      # Crawler succeeds but creates no files in pdfs/ and no report.csv
      assert {:ok, %{}} = Port.run("https://example.com", out_dir)

      # Verify directories were created
      assert File.dir?(Path.join(out_dir, "pdfs"))
      assert File.dir?(Path.join(out_dir, "markdown"))
      assert File.dir?(Path.join(out_dir, "pdf_markdown"))
      assert File.dir?(Path.join(out_dir, "images"))
    end

    test "handles pipeline failure when PDFs exist", %{repo_dir: repo_dir, out_dir: out_dir} do
      # Make crawler succeed and create a PDF
      File.write!(Path.join(repo_dir, "web_crawler.py"), """
      #!/usr/bin/env bash
      # web_crawler.py <url> --output-folder <out_dir> --report <report_path> --quiet

      out_dir="$3"
      mkdir -p "$out_dir/pdfs"
      touch "$out_dir/pdfs/dummy.pdf"
      exit 0
      """)

      # Make pipeline fail
      File.write!(Path.join(repo_dir, "pipeline.py"), """
      #!/usr/bin/env bash
      echo "Pipeline error" >&2
      exit 1
      """)

      assert {:error, "Pipeline failed: Pipeline error\n"} =
               Port.run("https://example.com", out_dir)
    end

    test "success with empty report.csv", %{repo_dir: repo_dir, out_dir: out_dir} do
      File.write!(Path.join(repo_dir, "web_crawler.py"), """
      #!/usr/bin/env bash
      # web_crawler.py <url> --output-folder <out_dir> --report <report_path> --quiet

      report_path="$5"
      touch "$report_path" # Create empty report.csv
      exit 0
      """)

      assert {:ok, %{}} = Port.run("https://example.com", out_dir)
      assert File.dir?(Path.join(out_dir, "pages"))
    end

    test "success organizes files based on report.csv and handles CSV quotes/commas", %{
      repo_dir: repo_dir,
      out_dir: out_dir,
      tmp_dir: tmp_dir
    } do
      url1 = "https://example.com/page1"
      url2 = "https://example.com/page2"
      md5_url1 = :crypto.hash(:md5, url1) |> Base.encode16(case: :lower)
      md5_url2 = :crypto.hash(:md5, url2) |> Base.encode16(case: :lower)

      fake_saved_md1 = Path.join(tmp_dir, "fake1.md")
      File.write!(fake_saved_md1, "content1")

      # File with comma in name to test quote parsing
      fake_saved_md2 = Path.join(tmp_dir, "fake,2.md")
      File.write!(fake_saved_md2, "content2")

      fake_pdf = Path.join(tmp_dir, "doc.pdf")
      File.write!(fake_pdf, "pdfcontent")

      File.write!(Path.join(repo_dir, "web_crawler.py"), """
      #!/usr/bin/env bash
      # web_crawler.py <url> --output-folder <out_dir> --report <report_path> --quiet
      # Simulate crawler output
      out="$3"
      report="$5"

      # Write report CSV
      # Headers: url,type,saved_as,found_on
      echo "url,type,saved_as,found_on,extra" > "$report"

      # Page 1: normal
      echo "#{url1},page,#{fake_saved_md1},," >> "$report"

      # Page 2: quoted saved_as with comma
      echo "#{url2},page,\\"#{fake_saved_md2}\\",," >> "$report"

      # Page 3: missing saved_as
      echo "https://example.com/page3,page,,,," >> "$report"

      # Page 4: non-existent saved_as
      echo "https://example.com/page4,page,/does/not/exist,," >> "$report"

      # PDF 1: associated with Page 1
      echo "https://example.com/doc.pdf,pdf,#{fake_pdf},#{url1}," >> "$report"

      # PDF 2: associated with Page 2, empty saved_as
      echo "https://example.com/doc2.pdf,pdf,,#{url2}," >> "$report"

      # PDF 3: unknown parent
      echo "https://example.com/doc3.pdf,pdf,#{fake_pdf},https://unknown.com," >> "$report"

      # Unknown type
      echo "https://example.com/unknown,image,#{fake_saved_md1},," >> "$report"

      # Generate fake pipeline assets for doc.pdf
      mkdir -p "$out/pdf_markdown"
      mkdir -p "$out/images/doc"
      printf "%s" "pdfmd" > "$out/pdf_markdown/doc.md"
      printf "%s" "img" > "$out/images/doc/1.png"

      # Trigger pipeline by creating a file in pdfs/
      mkdir -p "$out/pdfs"
      touch "$out/pdfs/trigger.pdf"
      exit 0
      """)

      # Run it
      assert {:ok, %{}} = Port.run("https://example.com", out_dir)

      # Verify pages were organized
      pages_dir = Path.join(out_dir, "pages")

      # Page 1
      page1_dir = Path.join(pages_dir, md5_url1)
      assert File.read!(Path.join(page1_dir, "page.md")) == "content1"

      # PDF 1 was copied to Page 1
      assert File.read!(Path.join([page1_dir, "pdfs", "doc.pdf"])) == "pdfcontent"
      assert File.read!(Path.join([page1_dir, "pdf_markdown", "doc.md"])) == "pdfmd"
      assert File.read!(Path.join([page1_dir, "images", "doc", "1.png"])) == "img"

      # Page 2 (quoted path parsing worked)
      page2_dir = Path.join(pages_dir, md5_url2)
      assert File.read!(Path.join(page2_dir, "page.md")) == "content2"
    end
  end
end
