defmodule Crawl.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 13, prefix: "crawl")

  def down, do: Oban.Migration.down(version: 13, prefix: "crawl")
end
