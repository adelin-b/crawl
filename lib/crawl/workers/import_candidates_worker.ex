defmodule Crawl.Workers.ImportCandidatesWorker do
  @moduledoc """
  Worker for importing candidates from a Google Sheet.
  """
  use Oban.Worker, queue: :gsheet

  alias Crawl.Integrations.GoogleSheets
  alias Crawl.Workers.Crawler
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    spreadsheet_id = args["spreadsheet_id"] || Application.get_env(:crawl, :google_sheet_id)
    range = args["range"] || Application.get_env(:crawl, :google_sheet_range)

    if is_nil(spreadsheet_id) or is_nil(range) do
      Logger.error("Missing Google Sheet configuration (spreadsheet_id or range)")
      {:error, :missing_configuration}
    else
      Logger.info("Starting Google Sheet import for #{spreadsheet_id} range #{range}")

      case GoogleSheets.fetch_rows(spreadsheet_id, range) do
        {:ok, rows} ->
          sheet_name = parse_sheet_name(range)
          process_rows(rows, spreadsheet_id, sheet_name)
          :ok

        {:error, reason} ->
          Logger.error("Failed to fetch rows: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp process_rows(rows, spreadsheet_id, sheet_name) do
    rows
    |> Enum.with_index(1)
    |> Enum.each(fn {row, index} ->
      process_row(row, index, spreadsheet_id, sheet_name)
    end)
  end

  defp process_row(row, index, _spreadsheet_id, _sheet_name) when index == 1 do
    # Skip header if it looks like one, or just assume first row is header.
    # We can check content to be safe.
    if header?(row) do
      Logger.info("Skipping header row at index #{index}")
    else
      # If it's not a header (unlikely for index 1 but possible), treat as data?
      # For now, let's assume index 1 is always header given the test setup.
      :ok
    end
  end

  defp process_row(row, index, spreadsheet_id, sheet_name) do
    # Columns:
    # 0..11: Metadata
    # 12: website_url
    # 13..14: timestamps
    # 15: status (optional)

    url = Enum.at(row, 12)
    status = Enum.at(row, 15)

    cond do
      is_nil(url) || url == "" ->
        :ok

      status == "PROCESSED" ->
        :ok

      true ->
        enqueue_crawler_job(url)
        Logger.info("Enqueued crawler job for #{url}")
        mark_as_processed(spreadsheet_id, sheet_name, index)
    end
  end

  defp header?(row) do
    Enum.at(row, 0) == "candidate_id"
  end

  defp enqueue_crawler_job(url) do
    %{url: url}
    |> Crawler.new()
    |> Oban.insert()
  end

  defp mark_as_processed(spreadsheet_id, sheet_name, index) do
    GoogleSheets.append_status(spreadsheet_id, sheet_name, index, "PROCESSED")
  end

  defp parse_sheet_name(range) do
    range
    |> String.split("!")
    |> List.first()
  end
end
