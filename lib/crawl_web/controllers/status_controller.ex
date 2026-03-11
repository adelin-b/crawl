defmodule CrawlWeb.StatusController do
  @moduledoc """
  GET /api/status — returns Oban crawler queue stats and recent jobs.
  Protected by CRAWL_API_SECRET.
  """
  use CrawlWeb, :controller

  import Ecto.Query
  require Logger

  def index(conn, params) do
    if authorized?(conn, params) do
      # Job state counts
      state_counts =
        Crawl.Repo.all(
          from(j in Oban.Job,
            where: j.queue == "crawler",
            group_by: j.state,
            select: {j.state, count(j.id)}
          )
        )
        |> Map.new()

      # Recent completed jobs (last 20)
      recent_completed =
        Crawl.Repo.all(
          from(j in Oban.Job,
            where: j.queue == "crawler" and j.state == "completed",
            order_by: [desc: j.completed_at],
            limit: 20,
            select: %{
              id: j.id,
              url: fragment("args->>'url'"),
              completed_at: j.completed_at,
              attempted_at: j.attempted_at
            }
          )
        )

      # Currently executing jobs
      executing =
        Crawl.Repo.all(
          from(j in Oban.Job,
            where: j.queue == "crawler" and j.state == "executing",
            select: %{
              id: j.id,
              url: fragment("args->>'url'"),
              attempted_at: j.attempted_at
            }
          )
        )

      # Failed/discarded jobs (last 10)
      failed =
        Crawl.Repo.all(
          from(j in Oban.Job,
            where: j.queue == "crawler" and j.state in ["retryable", "discarded"],
            order_by: [desc: j.attempted_at],
            limit: 10,
            select: %{
              id: j.id,
              state: j.state,
              url: fragment("args->>'url'"),
              errors: j.errors
            }
          )
        )

      json(conn, %{
        ok: true,
        queue: "crawler",
        state_counts: state_counts,
        executing: executing,
        recent_completed: recent_completed,
        failed: failed
      })
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
