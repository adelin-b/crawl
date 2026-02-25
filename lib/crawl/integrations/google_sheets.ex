defmodule Crawl.Integrations.GoogleSheets do
  @moduledoc """
  Wrapper for Google Sheets API interactions.
  """

  @callback fetch_rows(String.t(), String.t()) :: {:ok, [[String.t()]]} | {:error, any()}
  @callback append_status(String.t(), String.t(), integer(), integer(), String.t()) ::
              :ok | {:error, any()}

  def fetch_rows(spreadsheet_id, range) do
    impl().fetch_rows(spreadsheet_id, range)
  end

  def append_status(spreadsheet_id, sheet_name, row_index, col_index, status) do
    impl().append_status(spreadsheet_id, sheet_name, row_index, col_index, status)
  end

  defp impl do
    Application.get_env(:crawl, :google_sheets, Crawl.Integrations.GoogleSheets.Impl)
  end
end

defmodule Crawl.Integrations.GoogleSheets.Impl do
  @moduledoc """
  Default implementation using GoogleApi.Sheets.
  """
  @behaviour Crawl.Integrations.GoogleSheets

  alias Crawl.Integrations.GoogleSheets.Client
  alias Crawl.Integrations.GoogleSheets.TokenProvider
  alias GoogleApi.Sheets.V4
  alias GoogleApi.Sheets.V4.Model.ValueRange

  require Logger

  @impl true
  def fetch_rows(spreadsheet_id, range) do
    with {:ok, token} <- TokenProvider.fetch(source: :default),
         conn = V4.Connection.new(token.token),
         {:ok, response} <-
           Client.sheets_spreadsheets_values_get(
             conn,
             spreadsheet_id,
             range
           ) do
      {:ok, response.values || []}
    else
      error ->
        Logger.error("Failed to fetch rows from Google Sheets: #{inspect(error)}")
        error
    end
  rescue
    e ->
      Logger.error("Failed to fetch rows from Google Sheets: #{inspect(e)}")
      {:error, e}
  end

  @impl true
  def append_status(spreadsheet_id, sheet_name, row_index, col_index, status) do
    # Convert col_index (0-based) to column letter(s) (e.g. 0 -> A, 14 -> O, 26 -> AA)
    col_letter = col_index_to_letter(col_index)

    # We assume the row_index is 1-based as per Google Sheets API
    range = "#{sheet_name}!#{col_letter}#{row_index}"

    value_range = %ValueRange{
      values: [[status]]
    }

    with {:ok, token} <- TokenProvider.fetch(source: :default),
         conn = V4.Connection.new(token.token),
         {:ok, _response} <-
           Client.sheets_spreadsheets_values_update(
             conn,
             spreadsheet_id,
             range,
             value_input_option: "RAW",
             body: value_range
           ) do
      :ok
    else
      error ->
        Logger.error("Failed to update status in Google Sheets: #{inspect(error)}")
        error
    end
  rescue
    e ->
      Logger.error("Failed to update status in Google Sheets: #{inspect(e)}")
      {:error, e}
  end

  defp col_index_to_letter(index) do
    do_col_index_to_letter(index, "")
  end

  defp do_col_index_to_letter(index, acc) when index < 26 do
    <<index + ?A>> <> acc
  end

  defp do_col_index_to_letter(index, acc) do
    rem = rem(index, 26)
    quotient = div(index, 26) - 1
    do_col_index_to_letter(quotient, <<rem + ?A>> <> acc)
  end
end
