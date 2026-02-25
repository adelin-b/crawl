defmodule Crawl.Integrations.PythonCrawler.Port do
  @moduledoc """
  Implementation of the PythonCrawler behaviour using System ports.
  """
  @behaviour Crawl.Integrations.PythonCrawler

  require Logger

  @impl true
  def run(url, output_dir) do
    setup_directories(output_dir)

    case run_crawler(url, output_dir) do
      {:ok, _} ->
        maybe_run_pipeline(output_dir)

      error ->
        error
    end
  end

  defp setup_directories(output_dir) do
    File.mkdir_p!(Path.join(output_dir, "pdfs"))
    File.mkdir_p!(Path.join(output_dir, "markdown"))
    File.mkdir_p!(Path.join(output_dir, "pdf_markdown"))
    File.mkdir_p!(Path.join(output_dir, "images"))
  end

  defp run_crawler(url, output_dir) do
    python = python_cmd()
    repo_path = repo_path()
    crawler_script = Path.join(repo_path, "web_crawler.py")
    report_path = Path.join(output_dir, "report.csv")

    args = [
      crawler_script,
      url,
      "--output-folder",
      output_dir,
      "--report",
      report_path,
      "--quiet"
    ]

    Logger.info("Running crawler: #{Enum.join([python | args], " ")}")

    case System.cmd(python, args, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, output_dir}
      {error, _} -> {:error, "Crawler failed: #{error}"}
    end
  end

  defp maybe_run_pipeline(output_dir) do
    pdfs_dir = Path.join(output_dir, "pdfs")

    if File.ls!(pdfs_dir) != [] do
      run_pipeline(output_dir)
    else
      finalize(output_dir)
    end
  end

  defp run_pipeline(output_dir) do
    python = python_cmd()
    repo_path = repo_path()
    pipeline_script = Path.join(repo_path, "pipeline.py")
    pdfs_dir = Path.join(output_dir, "pdfs")
    pdf_md_dir = Path.join(output_dir, "pdf_markdown")
    images_dir = Path.join(output_dir, "images")

    args = [
      pipeline_script,
      "--input-folder",
      pdfs_dir,
      "--output-folder",
      pdf_md_dir,
      "--images-dir",
      images_dir,
      "--quiet"
    ]

    Logger.info("Running pipeline: #{Enum.join([python | args], " ")}")

    case System.cmd(python, args, stderr_to_stdout: true) do
      {_out, 0} -> finalize(output_dir)
      {err, _} -> {:error, "Pipeline failed: #{err}"}
    end
  end

  defp finalize(output_dir) do
    report_path = Path.join(output_dir, "report.csv")
    organize_files(output_dir, report_path)
    {:ok, %{}}
  end

  defp organize_files(output_dir, report_path) do
    if File.exists?(report_path) do
      rows = parse_csv(report_path)

      url_to_id = build_url_map(rows)

      pages_dir = Path.join(output_dir, "pages")
      File.mkdir_p!(pages_dir)

      Enum.each(rows, fn row ->
        process_row(row, output_dir, pages_dir, url_to_id)
      end)
    end
  end

  defp build_url_map(rows) do
    rows
    |> Enum.filter(fn row -> row["type"] == "page" end)
    |> Enum.map(fn row -> {row["url"], hash_url(row["url"])} end)
    |> Map.new()
  end

  defp process_row(%{"type" => "page"} = row, _output_dir, pages_dir, url_to_id) do
    url = row["url"]
    id = Map.get(url_to_id, url) || hash_url(url)
    page_dir = Path.join(pages_dir, id)
    File.mkdir_p!(page_dir)

    saved_as = row["saved_as"]

    if saved_as != "" and File.exists?(saved_as) do
      File.cp(saved_as, Path.join(page_dir, "page.md"))
    end
  end

  defp process_row(%{"type" => "pdf"} = row, output_dir, pages_dir, url_to_id) do
    found_on = row["found_on"]
    parent_id = Map.get(url_to_id, found_on)

    if parent_id do
      process_pdf_row(row, output_dir, pages_dir, parent_id)
    end
  end

  defp process_row(_, _, _, _), do: :ok

  defp process_pdf_row(row, output_dir, pages_dir, parent_id) do
    page_dir = Path.join(pages_dir, parent_id)
    File.mkdir_p!(page_dir)

    saved_as = row["saved_as"]

    if saved_as != "" and File.exists?(saved_as) do
      copy_pdf_assets(saved_as, output_dir, page_dir)
    end
  end

  defp copy_pdf_assets(saved_as, output_dir, page_dir) do
    filename = Path.basename(saved_as)

    # PDF File
    pdfs_dir = Path.join(page_dir, "pdfs")
    File.mkdir_p!(pdfs_dir)
    File.cp(saved_as, Path.join(pdfs_dir, filename))

    # Markdown
    md_filename = Path.rootname(filename) <> ".md"
    pdf_md_src = Path.join([output_dir, "pdf_markdown", md_filename])

    if File.exists?(pdf_md_src) do
      dest_md_dir = Path.join(page_dir, "pdf_markdown")
      File.mkdir_p!(dest_md_dir)
      File.cp(pdf_md_src, Path.join(dest_md_dir, md_filename))
    end

    # Images
    pdf_stem = Path.rootname(filename)
    images_src_dir = Path.join([output_dir, "images", pdf_stem])

    if File.dir?(images_src_dir) do
      dest_images_dir = Path.join([page_dir, "images", pdf_stem])
      File.mkdir_p!(dest_images_dir)
      File.cp_r(images_src_dir, dest_images_dir)
    end
  end

  defp parse_csv(path) do
    File.read!(path)
    |> String.split("\n", trim: true)
    |> parse_csv_lines()
  end

  defp parse_csv_lines([]) do
    []
  end

  defp parse_csv_lines([header | rows]) do
    headers = parse_csv_line(header)

    Enum.map(rows, fn row ->
      values = parse_csv_line(row)
      values = values ++ List.duplicate("", max(0, length(headers) - length(values)))
      Enum.zip(headers, values) |> Map.new()
    end)
  end

  defp parse_csv_line(line) do
    line
    |> String.trim()
    |> do_parse_csv_line([], "", false)
  end

  defp do_parse_csv_line("", acc, current, _in_quotes), do: Enum.reverse([current | acc])

  defp do_parse_csv_line(<<",", rest::binary>>, acc, current, false),
    do: do_parse_csv_line(rest, [current | acc], "", false)

  defp do_parse_csv_line(<<"\"", rest::binary>>, acc, current, false),
    do: do_parse_csv_line(rest, acc, current, true)

  defp do_parse_csv_line(<<"\"", rest::binary>>, acc, current, true),
    do: do_parse_csv_line(rest, acc, current, false)

  defp do_parse_csv_line(<<char, rest::binary>>, acc, current, in_quotes),
    do: do_parse_csv_line(rest, acc, current <> <<char>>, in_quotes)

  defp hash_url(url) do
    :crypto.hash(:md5, url) |> Base.encode16(case: :lower)
  end

  defp python_cmd, do: Application.get_env(:crawl, :python_executable, "python3")

  defp repo_path do
    default_path = Application.app_dir(:crawl, "priv/python/crawler-ingest")
    Application.get_env(:crawl, :crawler_ingest_path, default_path)
  end
end
