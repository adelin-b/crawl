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

    url_header = Application.get_env(:crawl, :google_sheet_url_header, "website_url")
    status_header = Application.get_env(:crawl, :google_sheet_status_header, "status")

    if is_nil(spreadsheet_id) or is_nil(range) do
      Logger.error("Missing Google Sheet configuration (spreadsheet_id or range)")
      {:error, :missing_configuration}
    else
      Logger.info("Starting Google Sheet import for #{spreadsheet_id} range #{range}")
      execute_import(spreadsheet_id, range, url_header, status_header)
    end
  end

  defp execute_import(spreadsheet_id, range, url_header, status_header) do
    case GoogleSheets.fetch_rows(spreadsheet_id, range) do
      {:ok, []} ->
        Logger.info("Sheet is empty")
        :ok

      {:ok, [header_row | data_rows]} ->
        process_fetched_rows(
          header_row,
          data_rows,
          spreadsheet_id,
          range,
          url_header,
          status_header
        )

      {:error, reason} ->
        Logger.error("Failed to fetch rows: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_fetched_rows(header, data, spreadsheet_id, range, url_header, status_header) do
    case resolve_column_indices(header, url_header, status_header) do
      {:ok, url_col_idx, status_col_idx} ->
        sheet_name = parse_sheet_name(range)
        process_data_rows(data, spreadsheet_id, sheet_name, url_col_idx, status_col_idx)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_column_indices(header_row, url_header, status_header) do
    url_col_idx = find_column_index(header_row, url_header)
    status_col_idx = find_column_index(header_row, status_header)

    cond do
      is_nil(url_col_idx) ->
        Logger.error("URL column '#{url_header}' not found in header")
        {:error, :url_header_not_found}

      is_nil(status_col_idx) ->
        Logger.error("Status column '#{status_header}' not found in header")
        {:error, :status_header_not_found}

      true ->
        {:ok, url_col_idx, status_col_idx}
    end
  end

  defp find_column_index(header_row, label) do
    normalized_label = label |> to_string() |> String.trim() |> String.downcase()

    Enum.find_index(header_row, fn col ->
      normalized_col = col |> to_string() |> String.trim() |> String.downcase()
      String.contains?(normalized_col, normalized_label)
    end)
  end

  defp process_data_rows(rows, spreadsheet_id, sheet_name, url_col_idx, status_col_idx) do
    # rows is everything after the header, so the first data row is index 2 in sheets (1-based)
    rows
    |> Enum.with_index(2)
    |> Enum.each(fn {row, index} ->
      process_row(row, index, spreadsheet_id, sheet_name, url_col_idx, status_col_idx)
    end)
  end

  defp process_row(row, index, spreadsheet_id, sheet_name, url_col_idx, status_col_idx) do
    url = Enum.at(row, url_col_idx)
    status = Enum.at(row, status_col_idx)

    cond do
      is_nil(url) || url == "" ->
        :ok

      status == "PROCESSED" ->
        :ok

      true ->
        enqueue_crawler_job(url)
        Logger.info("Enqueued crawler job for #{url}")
        mark_as_processed(spreadsheet_id, sheet_name, index, status_col_idx)
    end
  end

  defp enqueue_crawler_job(url) do
    %{url: url}
    |> Crawler.new()
    |> Oban.insert()
  end

  defp mark_as_processed(spreadsheet_id, sheet_name, index, status_col_idx) do
    GoogleSheets.append_status(spreadsheet_id, sheet_name, index, status_col_idx, "PROCESSED")
  end

  defp parse_sheet_name(range) do
    range
    |> String.split("!")
    |> List.first()
  end
end
