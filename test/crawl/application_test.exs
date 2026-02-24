defmodule Crawl.ApplicationTest do
  use ExUnit.Case, async: false

  alias Crawl.Application, as: App

  setup do
    # Save original env
    original_goth_start = Application.get_env(:crawl, :start_goth)
    original_dns = Application.get_env(:crawl, :dns_cluster_query)
    original_json = System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON")

    on_exit(fn ->
      # Restore original env
      if original_goth_start == nil,
        do: Application.delete_env(:crawl, :start_goth),
        else: Application.put_env(:crawl, :start_goth, original_goth_start)

      if original_dns == nil,
        do: Application.delete_env(:crawl, :dns_cluster_query),
        else: Application.put_env(:crawl, :dns_cluster_query, original_dns)

      if original_json,
        do: System.put_env("GOOGLE_APPLICATION_CREDENTIALS_JSON", original_json),
        else: System.delete_env("GOOGLE_APPLICATION_CREDENTIALS_JSON")
    end)
  end

  test "children/0 includes Goth when :start_goth is true (default)" do
    Application.put_env(:crawl, :start_goth, true)
    System.put_env("GOOGLE_APPLICATION_CREDENTIALS_JSON", "{\"type\": \"service_account\"}")

    children = App.children()

    assert Enum.any?(children, fn
             {Goth,
              [name: Crawl.Goth, source: {:service_account, %{"type" => "service_account"}}]} ->
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

  test "children/0 handles invalid JSON credentials gracefully" do
    Application.put_env(:crawl, :start_goth, true)
    System.put_env("GOOGLE_APPLICATION_CREDENTIALS_JSON", "invalid-json")

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
