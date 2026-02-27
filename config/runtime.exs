import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/crawl start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :crawl, CrawlWeb.Endpoint, server: true
end

config :crawl, CrawlWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  config :crawl,
    google_sheet_id: System.get_env("GOOGLE_SHEET_ID"),
    google_sheet_range: System.get_env("GOOGLE_SHEET_RANGE"),
    google_sheet_url_header: System.get_env("GOOGLE_SHEET_URL_HEADER") || "website_url",
    google_sheet_status_header: System.get_env("GOOGLE_SHEET_STATUS_HEADER") || "status",
    google_drive_folder_id: System.get_env("GOOGLE_DRIVE_FOLDER_ID"),
    google_credentials_json: System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON"),
    upload_webhook_url:
      if(System.get_env("UPLOAD_WEBHOOK_URL") == "",
        do: nil,
        else: System.get_env("UPLOAD_WEBHOOK_URL")
      )

  # Validate required Google integration env vars
  google_sheet_id = System.get_env("GOOGLE_SHEET_ID")
  google_sheet_range = System.get_env("GOOGLE_SHEET_RANGE")
  google_drive_folder_id = System.get_env("GOOGLE_DRIVE_FOLDER_ID")
  google_credentials_json = System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON")

  if is_nil(google_sheet_id) or is_nil(google_sheet_range) or is_nil(google_drive_folder_id) or
       is_nil(google_credentials_json) do
    raise """
    Required Google integration environment variables are missing in production:
    - GOOGLE_SHEET_ID
    - GOOGLE_SHEET_RANGE
    - GOOGLE_DRIVE_FOLDER_ID
    - GOOGLE_APPLICATION_CREDENTIALS_JSON (full service account JSON)
    """
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :crawl, Crawl.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :crawl, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :crawl, CrawlWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :crawl, CrawlWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :crawl, CrawlWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
