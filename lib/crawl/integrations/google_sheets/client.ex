defmodule Crawl.Integrations.GoogleSheets.Client do
  @moduledoc """
  Behaviour for GoogleApi.Sheets interactions.
  """
  @callback sheets_spreadsheets_values_get(
              connection :: GoogleApi.Sheets.V4.Connection.t(),
              spreadsheet_id :: String.t(),
              range :: String.t(),
              opts :: keyword()
            ) ::
              {:ok, GoogleApi.Sheets.V4.Model.ValueRange.t()} | {:error, Tesla.Env.t()}

  @callback sheets_spreadsheets_values_update(
              connection :: GoogleApi.Sheets.V4.Connection.t(),
              spreadsheet_id :: String.t(),
              range :: String.t(),
              opts :: keyword()
            ) ::
              {:ok, GoogleApi.Sheets.V4.Model.UpdateValuesResponse.t()} | {:error, Tesla.Env.t()}

  def sheets_spreadsheets_values_get(conn, id, range, opts \\ []),
    do: impl().sheets_spreadsheets_values_get(conn, id, range, opts)

  def sheets_spreadsheets_values_update(conn, id, range, opts \\ []),
    do: impl().sheets_spreadsheets_values_update(conn, id, range, opts)

  defp impl,
    do: Application.get_env(:crawl, :google_sheets_client, GoogleApi.Sheets.V4.Api.Spreadsheets)
end
