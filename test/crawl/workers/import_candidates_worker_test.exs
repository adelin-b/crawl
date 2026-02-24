defmodule Crawl.Workers.ImportCandidatesWorkerTest do
  use Crawl.DataCase, async: true
  import Mox

  alias Crawl.Workers.ImportCandidatesWorker

  setup :verify_on_exit!

  describe "perform/1" do
    test "fetches rows, skips header, enqueues crawler jobs for new URLs, and marks them as processed" do
      spreadsheet_id = "test-sheet-id"
      # We assume the range includes the sheet name like "Sheet1!A:O"
      range_arg = "Sheet1!A:O"
      sheet_name = "Sheet1"

      headers = [
        "candidate_id",
        # Added to match data structure
        "external_id",
        "first_name",
        "last_name",
        "municipality_code",
        "municipality_name",
        "party_ids",
        "election_type_id",
        "position",
        "bio",
        "is_incumbent",
        "birth_year",
        "website_url",
        "created_at",
        "updated_at",
        "status"
      ]

      rows = [
        headers,
        [
          "cand-paris-001",
          "cand-Paris-001",
          "Rachida",
          "Dati",
          "75001, 75002, 75003, 75004, 75005,  75006, 75007, 75008, 75009, 75010, 75011, 75012, 75013, 75014, 75015, 75016, 75017, 75018, 75019, 75020, ",
          "Paris",
          "[lr]",
          "municipalities-2026",
          "Tête de liste",
          "Engagée depuis 15 ans dans la vie locale d'Arcueil, Sophie Martin porte un projet écologique et social pour la ville.",
          "false",
          "",
          "https://rachidadati2026.com",
          "",
          ""
        ],
        [
          "cand-paris-002",
          "cand-Paris-002",
          "Emmanuel",
          "Grégoire",
          "75001, 75002, 75003, 75004, 75005,  75006, 75007, 75008, 75009, 75010, 75011, 75012, 75013, 75014, 75015, 75016, 75017, 75018, 75019, 75020, ",
          "Paris",
          "[ps]",
          "municipalities-2026",
          "Tête de liste",
          "",
          "false",
          "",
          "https://emmanuel-gregoire-2026.fr",
          "",
          ""
        ],
        # Add a row that is already processed to ensure it's skipped
        [
          "cand-paris-003",
          "cand-Paris-003",
          "Someone",
          "Else",
          "...",
          "Paris",
          "[eelv]",
          "municipalities-2026",
          "Tête de liste",
          "",
          "false",
          "",
          "https://already-processed.com",
          "",
          "",
          "PROCESSED"
        ],
        [
          "cand-paris-004",
          "cand-Paris-004",
          "No",
          "Url",
          "75001",
          "Paris",
          "[lr]",
          "municipalities-2026",
          "Tête de liste",
          "",
          "false",
          "",
          # Missing URL
          "",
          "",
          ""
        ],
        [
          "cand-paris-005",
          "cand-Paris-005",
          "Nil",
          "Url",
          "75001",
          "Paris",
          "[lr]",
          "municipalities-2026",
          "Tête de liste",
          "",
          "false",
          "",
          # Nil URL
          nil,
          "",
          ""
        ]
      ]

      Crawl.Integrations.GoogleSheetsMock
      |> expect(:fetch_rows, fn ^spreadsheet_id, ^range_arg ->
        {:ok, rows}
      end)

      # Expect append_status for rows 2 and 3 (1-based index)
      # Row 1 is header
      # Row 2 is Rachida Dati
      # Row 3 is Emmanuel Grégoire
      # Row 4 is Someone Else (already processed)
      # Row 5 is No Url (should be skipped)
      # Row 6 is Nil Url (should be skipped)

      Crawl.Integrations.GoogleSheetsMock
      |> expect(:append_status, fn ^spreadsheet_id, ^sheet_name, 2, "PROCESSED" -> :ok end)
      |> expect(:append_status, fn ^spreadsheet_id, ^sheet_name, 3, "PROCESSED" -> :ok end)

      # We do NOT expect append_status for row 5 or 6

      # Perform the worker
      assert :ok =
               ImportCandidatesWorker.perform(%Oban.Job{
                 args: %{"spreadsheet_id" => spreadsheet_id, "range" => range_arg}
               })

      # Verify jobs are enqueued
      assert_enqueued(
        worker: Crawl.Workers.Crawler,
        args: %{"url" => "https://rachidadati2026.com"}
      )

      assert_enqueued(
        worker: Crawl.Workers.Crawler,
        args: %{"url" => "https://emmanuel-gregoire-2026.fr"}
      )

      refute_enqueued(
        worker: Crawl.Workers.Crawler,
        args: %{"url" => "https://already-processed.com"}
      )
    end
  end

  describe "configuration" do
    test "perform/1 returns error when missing configuration" do
      Application.delete_env(:crawl, :google_sheet_id)
      Application.delete_env(:crawl, :google_sheet_range)

      assert {:error, :missing_configuration} =
               ImportCandidatesWorker.perform(%Oban.Job{args: %{}})
    end

    test "perform/1 uses application env when args are missing" do
      spreadsheet_id = "env-sheet-id"
      range = "Sheet1!A:O"

      Application.put_env(:crawl, :google_sheet_id, spreadsheet_id)
      Application.put_env(:crawl, :google_sheet_range, range)

      Crawl.Integrations.GoogleSheetsMock
      |> expect(:fetch_rows, fn ^spreadsheet_id, ^range ->
        {:ok, []}
      end)

      assert :ok = ImportCandidatesWorker.perform(%Oban.Job{args: %{}})
    end
  end

  describe "fetch_rows errors" do
    test "perform/1 returns error when fetch_rows fails" do
      spreadsheet_id = "test-sheet-id"
      range = "Sheet1!A:O"

      Crawl.Integrations.GoogleSheetsMock
      |> expect(:fetch_rows, fn ^spreadsheet_id, ^range ->
        {:error, :sheet_unavailable}
      end)

      assert {:error, :sheet_unavailable} =
               ImportCandidatesWorker.perform(%Oban.Job{
                 args: %{"spreadsheet_id" => spreadsheet_id, "range" => range}
               })
    end
  end

  describe "row processing robustness" do
    test "skips first row even if it is not a header" do
      spreadsheet_id = "test-sheet-id"
      range = "Sheet1!A:O"
      sheet_name = "Sheet1"

      # First row is NOT a header (candidate_id doesn't match)
      # Second row is valid data
      rows = [
        ["not_candidate_id", "some", "data"],
        [
          "cand-paris-002",
          "cand-Paris-002",
          "Emmanuel",
          "Grégoire",
          "75001",
          "Paris",
          "[ps]",
          "municipalities-2026",
          "Tête de liste",
          "",
          "false",
          "",
          "https://emmanuel-gregoire-2026.fr",
          "",
          ""
        ]
      ]

      Crawl.Integrations.GoogleSheetsMock
      |> expect(:fetch_rows, fn ^spreadsheet_id, ^range ->
        {:ok, rows}
      end)

      # We only expect append_status for the second row (index 2)
      Crawl.Integrations.GoogleSheetsMock
      |> expect(:append_status, fn ^spreadsheet_id, ^sheet_name, 2, "PROCESSED" -> :ok end)

      assert :ok =
               ImportCandidatesWorker.perform(%Oban.Job{
                 args: %{"spreadsheet_id" => spreadsheet_id, "range" => range}
               })

      # Verify job enqueued for second row
      assert_enqueued(
        worker: Crawl.Workers.Crawler,
        args: %{"url" => "https://emmanuel-gregoire-2026.fr"}
      )
    end

    test "handles short rows gracefully" do
      spreadsheet_id = "test-sheet-id"
      range = "Sheet1!A:O"

      # Row with missing columns
      rows = [
        # Header
        ["candidate_id"],
        # Only 2 columns
        ["cand-short", "Short"]
      ]

      Crawl.Integrations.GoogleSheetsMock
      |> expect(:fetch_rows, fn ^spreadsheet_id, ^range ->
        {:ok, rows}
      end)

      # We don't expect any append_status or enqueues
      assert :ok =
               ImportCandidatesWorker.perform(%Oban.Job{
                 args: %{"spreadsheet_id" => spreadsheet_id, "range" => range}
               })

      refute_enqueued(worker: Crawl.Workers.Crawler)
    end

    test "does not crash if append_status fails" do
      spreadsheet_id = "test-sheet-id"
      range = "Sheet1!A:O"
      sheet_name = "Sheet1"

      rows = [
        ["candidate_id"],
        [
          "cand-paris-002",
          "cand-Paris-002",
          "Emmanuel",
          "Grégoire",
          "75001",
          "Paris",
          "[ps]",
          "municipalities-2026",
          "Tête de liste",
          "",
          "false",
          "",
          "https://emmanuel-gregoire-2026.fr",
          "",
          ""
        ]
      ]

      Crawl.Integrations.GoogleSheetsMock
      |> expect(:fetch_rows, fn ^spreadsheet_id, ^range ->
        {:ok, rows}
      end)

      # Mock append_status failure
      Crawl.Integrations.GoogleSheetsMock
      |> expect(:append_status, fn ^spreadsheet_id, ^sheet_name, 2, "PROCESSED" ->
        {:error, :update_failed}
      end)

      assert :ok =
               ImportCandidatesWorker.perform(%Oban.Job{
                 args: %{"spreadsheet_id" => spreadsheet_id, "range" => range}
               })

      # Verify job is still enqueued despite update failure
      assert_enqueued(
        worker: Crawl.Workers.Crawler,
        args: %{"url" => "https://emmanuel-gregoire-2026.fr"}
      )
    end
  end
end
