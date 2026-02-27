import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :crawl, Crawl.Repo,
  username: "postgres",
  password: "postgrespw",
  hostname: "localhost",
  database: "tandem",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :crawl, CrawlWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "uKYwJB94YcX5azhsdnMjk7R9xXmtpoqUh9x1s3v5NdVSLQpd6tjS1DzppKnXNJxn",
  server: false

config :crawl, :google_sheets, Crawl.Integrations.GoogleSheetsMock

config :crawl, :google_drive, Crawl.Integrations.GoogleDriveMock

config :crawl, :python_crawler, Crawl.Integrations.PythonCrawlerMock

config :crawl, :upload_webhook, Crawl.Integrations.UploadWebhookMock

config :crawl, :artifact_dir, "test/tmp/artifacts"

config :crawl, :google_credentials_json, nil

config :crawl, :start_goth, false

config :crawl, Oban,
  repo: Crawl.Repo,
  queues: false,
  plugins: false,
  testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
