defmodule Crawl.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Crawl.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def children do
    [
      CrawlWeb.Telemetry,
      Crawl.Repo,
      {DNSCluster, query: Application.get_env(:crawl, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Crawl.PubSub}
    ] ++
      goth_children() ++
      [
        {Oban, Application.fetch_env!(:crawl, Oban)},
        # Start a worker by calling: Crawl.Worker.start_link(arg)
        # {Crawl.Worker, arg},
        # Start to serve requests, typically the last entry
        CrawlWeb.Endpoint
      ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CrawlWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp goth_children do
    if Application.get_env(:crawl, :start_goth, true) do
      # Make sure to handle potential JSON errors gracefully or assume valid input in prod
      json = System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON", "{}")

      source =
        case Jason.decode(json) do
          {:ok, decoded} -> {:service_account, decoded}
          {:error, _} -> {:service_account, %{}}
        end

      [{Goth, name: Crawl.Goth, source: source}]
    else
      []
    end
  end
end
