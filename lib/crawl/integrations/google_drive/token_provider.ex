defmodule Crawl.Integrations.GoogleDrive.TokenProvider do
  @moduledoc """
  Behaviour for fetching Goth tokens for Google Drive.
  """
  @callback fetch(opts :: keyword()) :: {:ok, Goth.Token.t()} | {:error, any()}

  def fetch(opts), do: impl().fetch(opts)

  defp impl, do: Application.get_env(:crawl, :goth_token_provider, Goth.Token)
end
