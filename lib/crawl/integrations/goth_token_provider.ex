defmodule Crawl.Integrations.GothTokenProvider do
  @moduledoc """
  Default implementation for fetching tokens from the supervised Goth cache.
  """
  @behaviour Crawl.Integrations.GoogleSheets.TokenProvider

  @impl true
  def fetch(_opts \\ []) do
    Goth.fetch(Crawl.Goth)
  end
end
