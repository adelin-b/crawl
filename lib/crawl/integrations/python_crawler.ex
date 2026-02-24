defmodule Crawl.Integrations.PythonCrawler do
  @moduledoc """
  Behaviour for the Python crawler integration.
  """

  @callback run(url :: String.t(), output_dir :: String.t()) ::
              {:ok, map()} | {:error, any()}

  def run(url, output_dir) do
    impl().run(url, output_dir)
  end

  defp impl do
    Application.get_env(:crawl, :python_crawler, Crawl.Integrations.PythonCrawler.Port)
  end
end
