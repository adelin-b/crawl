# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :crawl,
  ecto_repos: [Crawl.Repo],
  generators: [timestamp_type: :utc_datetime]

config :crawl, Crawl.Repo,
  after_connect: {Postgrex, :query!, ["SET search_path TO crawl,public", []]},
  ssl_opts: [
    # for otp26: https://elixirforum.com/t/how-to-set-ssl-options-correctly-when-connecting-to-heroku-postgres-db/59426
    verify: :verify_none
  ]

# Configure the endpoint
config :crawl, CrawlWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CrawlWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Crawl.PubSub,
  live_view: [signing_salt: "KOo98ujz"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban Configuration
config :crawl, Oban,
  repo: Crawl.Repo,
  prefix: "crawl",
  plugins: [
    {Oban.Plugins.Pruner, max_age: 432_000},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", Crawl.Workers.ImportCandidatesWorker}
     ]}
  ],
  queues: [default: 10, gsheet: 10, crawler: 10, webhook: 10]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
