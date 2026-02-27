defmodule Crawl.ApplicationTest do
  use ExUnit.Case, async: false

  alias Crawl.Application, as: App

  setup do
    # Save original env
    original_goth_start = Application.get_env(:crawl, :start_goth)
    original_dns = Application.get_env(:crawl, :dns_cluster_query)
    original_creds_json = Application.get_env(:crawl, :google_credentials_json)

    on_exit(fn ->
      # Restore original env
      if original_goth_start == nil,
        do: Application.delete_env(:crawl, :start_goth),
        else: Application.put_env(:crawl, :start_goth, original_goth_start)

      if original_dns == nil,
        do: Application.delete_env(:crawl, :dns_cluster_query),
        else: Application.put_env(:crawl, :dns_cluster_query, original_dns)

      if original_creds_json == nil,
        do: Application.delete_env(:crawl, :google_credentials_json),
        else: Application.put_env(:crawl, :google_credentials_json, original_creds_json)
    end)
  end

  test "children/0 includes Goth when :start_goth is true (default)" do
    Application.put_env(:crawl, :start_goth, true)

    json =
      "{\"type\":\"service_account\",\"project_id\":\"test\",\"private_key_id\":\"keyid\",\"private_key\":\"key\",\"client_email\":\"test@test.iam.gserviceaccount.com\",\"client_id\":\"123\",\"token_uri\":\"https://oauth2.googleapis.com/token\"}"

    Application.put_env(:crawl, :google_credentials_json, json)

    children = App.children()

    assert Enum.any?(children, fn
             {Goth,
              [
                name: Crawl.Goth,
                source: {:service_account, %{"type" => "service_account"} = _creds, _opts}
              ]} ->
               true

             _ ->
               false
           end)
  end

  test "children/0 excludes Goth when :start_goth is false" do
    Application.put_env(:crawl, :start_goth, false)

    children = App.children()

    refute Enum.any?(children, fn
             {Goth, _} -> true
             _ -> false
           end)
  end

  test "children/0 handles missing credentials gracefully" do
    Application.put_env(:crawl, :start_goth, true)
    # Do not set :google_credentials_json

    children = App.children()

    assert Enum.any?(children, fn
             {Goth, [name: Crawl.Goth, source: {:service_account, %{}}]} -> true
             _ -> false
           end)
  end

  test "children/0 uses empty credentials when env var is not set (dev default)" do
    Application.put_env(:crawl, :start_goth, true)
    # Simulate dev environment where GOOGLE_APPLICATION_CREDENTIALS_JSON is not set
    Application.put_env(:crawl, :google_credentials_json, nil)

    children = App.children()

    assert Enum.any?(children, fn
             {Goth, [name: Crawl.Goth, source: {:service_account, %{}}]} -> true
             _ -> false
           end)
  end

  test "children/0 uses configured DNS cluster query" do
    Application.put_env(:crawl, :dns_cluster_query, :my_query)

    children = App.children()

    assert Enum.member?(children, {DNSCluster, query: :my_query})
  end

  test "children/0 defaults DNS cluster query to :ignore" do
    Application.delete_env(:crawl, :dns_cluster_query)

    children = App.children()

    assert Enum.member?(children, {DNSCluster, query: :ignore})
  end

  test "config_change/3 returns :ok" do
    assert :ok = App.config_change([], [], [])
  end
end
