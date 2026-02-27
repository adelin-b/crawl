defmodule Crawl.Integrations.GoogleSheetsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mox

  alias Crawl.Integrations.GoogleSheets
  alias Crawl.Integrations.GoogleSheets.ClientMock
  alias Crawl.Integrations.GoogleSheets.TokenProviderMock
  alias GoogleApi.Sheets.V4.Model.ValueRange

  setup :verify_on_exit!

  # Define a stub implementation within the test module or file
  defmodule Stub do
    @behaviour Crawl.Integrations.GoogleSheets

    @impl true
    def fetch_rows(spreadsheet_id, range) do
      send(self(), {:stub_fetch_rows, spreadsheet_id, range})
      {:ok, [["url"]]}
    end

    @impl true
    def append_status(spreadsheet_id, sheet_name, row_index, col_index, status) do
      send(
        self(),
        {:stub_append_status, spreadsheet_id, sheet_name, row_index, col_index, status}
      )

      :ok
    end
  end

  setup do
    original_impl = Application.get_env(:crawl, :google_sheets)
    original_token = Application.get_env(:crawl, :goth_token_provider)
    original_client = Application.get_env(:crawl, :google_sheets_client)

    on_exit(fn ->
      restore_env(:google_sheets, original_impl)
      restore_env(:goth_token_provider, original_token)
      restore_env(:google_sheets_client, original_client)
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:crawl, key)
  defp restore_env(key, val), do: Application.put_env(:crawl, key, val)

  describe "delegation" do
    test "fetch_rows delegates to configured implementation" do
      Application.put_env(:crawl, :google_sheets, Stub)

      assert {:ok, [["url"]]} = GoogleSheets.fetch_rows("sheet-1", "Sheet1!A:O")
      assert_received {:stub_fetch_rows, "sheet-1", "Sheet1!A:O"}
    end

    test "append_status delegates to configured implementation" do
      Application.put_env(:crawl, :google_sheets, Stub)

      assert :ok = GoogleSheets.append_status("sheet-1", "Sheet1", 3, 14, "PROCESSED")
      assert_received {:stub_append_status, "sheet-1", "Sheet1", 3, 14, "PROCESSED"}
    end
  end

  describe "default implementation logic" do
    setup do
      Application.delete_env(:crawl, :google_sheets)
      Application.put_env(:crawl, :goth_token_provider, TokenProviderMock)
      Application.put_env(:crawl, :google_sheets_client, ClientMock)
      :ok
    end

    test "fetch_rows returns values on success" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:sheets_spreadsheets_values_get, fn _conn, "sheet-1", "range", [] ->
        {:ok, %ValueRange{values: [["a"], ["b"]]}}
      end)

      assert {:ok, [["a"], ["b"]]} = GoogleSheets.fetch_rows("sheet-1", "range")
    end

    test "fetch_rows returns empty list when values are nil" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:sheets_spreadsheets_values_get, fn _conn, "sheet-1", "range", [] ->
        {:ok, %ValueRange{values: nil}}
      end)

      assert {:ok, []} = GoogleSheets.fetch_rows("sheet-1", "range")
    end

    test "fetch_rows handles token fetch error" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:error, :token_error} end)

      log =
        capture_log(fn ->
          assert {:error, :token_error} = GoogleSheets.fetch_rows("sheet-1", "range")
        end)

      assert log =~ "Failed to fetch rows from Google Sheets: {:error, :token_error}"
    end

    test "fetch_rows handles API error" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:sheets_spreadsheets_values_get, fn _conn, "sheet-1", "range", [] ->
        {:error, :api_error}
      end)

      log =
        capture_log(fn ->
          assert {:error, :api_error} = GoogleSheets.fetch_rows("sheet-1", "range")
        end)

      assert log =~ "Failed to fetch rows from Google Sheets: {:error, :api_error}"
    end

    test "fetch_rows handles rescue (exception)" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> raise "boom" end)

      log =
        capture_log(fn ->
          assert {:error, %RuntimeError{message: "boom"}} =
                   GoogleSheets.fetch_rows("sheet-1", "range")
        end)

      assert log =~ "Failed to fetch rows from Google Sheets: %RuntimeError{message: \"boom\"}"
    end

    test "append_status returns :ok on success and handles column conversion" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:sheets_spreadsheets_values_update, fn _conn, "sheet-1", "Sheet1!O3", opts ->
        assert opts[:valueInputOption] == "RAW"
        assert %ValueRange{values: [["PROCESSED"]]} = opts[:body]
        {:ok, %{}}
      end)

      assert :ok = GoogleSheets.append_status("sheet-1", "Sheet1", 3, 14, "PROCESSED")
    end

    test "append_status converts column index over 26 correctly" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:sheets_spreadsheets_values_update, fn _conn, "sheet-1", "Sheet1!AA3", _opts ->
        {:ok, %{}}
      end)

      # 26 corresponds to AA
      assert :ok = GoogleSheets.append_status("sheet-1", "Sheet1", 3, 26, "PROCESSED")
    end

    test "append_status handles token fetch error" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:error, :token_error} end)

      log =
        capture_log(fn ->
          assert {:error, :token_error} =
                   GoogleSheets.append_status("sheet-1", "Sheet1", 3, 14, "PROCESSED")
        end)

      assert log =~ "Failed to update status in Google Sheets: {:error, :token_error}"
    end

    test "append_status handles API error" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> {:ok, %Goth.Token{token: "fake-token"}} end)

      ClientMock
      |> expect(:sheets_spreadsheets_values_update, fn _conn, "sheet-1", "Sheet1!O3", _opts ->
        {:error, :api_error}
      end)

      log =
        capture_log(fn ->
          assert {:error, :api_error} =
                   GoogleSheets.append_status("sheet-1", "Sheet1", 3, 14, "PROCESSED")
        end)

      assert log =~ "Failed to update status in Google Sheets: {:error, :api_error}"
    end

    test "append_status handles rescue (exception)" do
      TokenProviderMock
      |> expect(:fetch, fn [source: :default] -> raise "boom" end)

      log =
        capture_log(fn ->
          assert {:error, %RuntimeError{message: "boom"}} =
                   GoogleSheets.append_status("sheet-1", "Sheet1", 3, 14, "PROCESSED")
        end)

      assert log =~ "Failed to update status in Google Sheets: %RuntimeError{message: \"boom\"}"
    end
  end
end
