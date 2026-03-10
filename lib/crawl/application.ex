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
      # Read raw JSON string from app config (wired from env in runtime.exs)
      json = Application.get_env(:crawl, :google_credentials_json)

      source =
        case Crawl.GoogleCredentials.build_source(json) do
          {:ok, built} -> built
          {:error, reason} -> handle_goth_error(reason)
        end

      [{Goth, name: Crawl.Goth, source: source}]
    else
      []
    end
  end

  defp handle_goth_error(reason) do
    if Application.get_env(:crawl, :env, :prod) == :prod do
      raise "Failed to build Goth source: #{reason}"
    else
      {:service_account, %{}}
    end
  end
end
