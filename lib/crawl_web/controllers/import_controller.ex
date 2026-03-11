defmodule CrawlWeb.ImportController do
  @moduledoc """
  API controller for triggering the import pipeline on demand.

  POST /api/import — enqueue an ImportCandidatesWorker job immediately.
  Protected by CRAWL_API_SECRET (passed as Bearer token or `secret` query param).
  """
  use CrawlWeb, :controller

  alias Crawl.Workers.ImportCandidatesWorker
  require Logger

  def create(conn, params) do
    if authorized?(conn, params) do
      job_args = %{}

      case ImportCandidatesWorker.new(job_args) |> Oban.insert() do
        {:ok, job} ->
          Logger.info("Import job enqueued on demand (job_id=#{job.id})")
          json(conn, %{ok: true, job_id: job.id, message: "Import job enqueued"})

        {:error, reason} ->
          Logger.error("Failed to enqueue import job: #{inspect(reason)}")

          conn
          |> put_status(:internal_server_error)
          |> json(%{ok: false, error: "Failed to enqueue job"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{ok: false, error: "Invalid or missing secret"})
    end
  end

  defp authorized?(conn, params) do
    expected = Application.get_env(:crawl, :api_secret)

    if is_nil(expected) or expected == "" do
      false
    else
      token_from_header(conn) == expected or
        Map.get(params, "secret") == expected
    end
  end

  defp token_from_header(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      _ -> nil
    end
  end
end
