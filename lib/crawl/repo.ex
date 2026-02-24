defmodule Crawl.Repo do
  use Ecto.Repo,
    otp_app: :crawl,
    adapter: Ecto.Adapters.Postgres
end
