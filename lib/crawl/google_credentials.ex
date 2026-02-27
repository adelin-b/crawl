defmodule Crawl.GoogleCredentials do
  @moduledoc """
  Helper for parsing and validating Google Cloud service account credentials.

  This module centralizes JSON parsing and validation logic so it can be reused
  across the application (e.g., Goth setup, Google API clients).
  """

  @required_fields [
    "type",
    "project_id",
    "private_key_id",
    "private_key",
    "client_email",
    "client_id",
    "token_uri"
  ]

  @doc """
  Parse a raw JSON string into a credentials map.

  Returns `{:ok, map}` if parsing succeeds, `{:error, reason}` otherwise.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} -> validate(decoded)
      {:error, reason} -> {:error, "JSON decode failed: #{reason}"}
    end
  end

  def parse(_), do: {:error, "Expected a binary JSON string"}

  @doc """
  Validate that a decoded credentials map contains all required fields.

  Returns `{:ok, map}` if valid, `{:error, reason}` otherwise.
  """
  @spec validate(map()) :: {:ok, map()} | {:error, String.t()}
  def validate(creds) when is_map(creds) do
    missing = Enum.reject(@required_fields, &(&1 in Map.keys(creds)))

    if missing == [] do
      {:ok, creds}
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  def validate(_), do: {:error, "Expected a map"}

  @doc """
  Build a Goth source tuple from a raw JSON string or an already-decoded map.

  This is a convenience wrapper around `parse/1` and `validate/1` that returns
  a Goth-compatible source tuple (`{:service_account, map}`) or an error.
  """
  @spec build_source(String.t() | map()) ::
          {:ok, {:service_account, map()}} | {:error, String.t()}
  def build_source(json) when is_binary(json), do: build_source_from_json(json)
  def build_source(creds) when is_map(creds), do: build_source_from_map(creds)
  def build_source(_), do: {:error, "Expected a binary JSON string or a map"}

  defp build_source_from_json(json) do
    case parse(json) do
      {:ok, creds} -> build_source_tuple(creds)
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_source_from_map(creds) do
    case validate(creds) do
      {:ok, valid} -> build_source_tuple(valid)
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_source_tuple(valid_creds) do
    {:ok,
     {:service_account, valid_creds,
      [
        scopes: [
          "https://www.googleapis.com/auth/spreadsheets",
          "https://www.googleapis.com/auth/drive"
        ]
      ]}}
  end
end
