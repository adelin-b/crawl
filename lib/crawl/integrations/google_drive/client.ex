defmodule Crawl.Integrations.GoogleDrive.Client do
  @moduledoc """
  Behaviour for GoogleApi.Drive interactions.
  """
  @callback drive_files_create(
              connection :: GoogleApi.Drive.V3.Connection.t(),
              optional_params :: keyword(),
              opts :: keyword()
            ) ::
              {:ok, GoogleApi.Drive.V3.Model.File.t()}
              | {:ok, Tesla.Env.t()}
              | {:error, any()}

  @callback drive_files_create_simple(
              connection :: GoogleApi.Drive.V3.Connection.t(),
              upload_type :: String.t(),
              metadata :: GoogleApi.Drive.V3.Model.File.t(),
              data :: String.t(),
              optional_params :: keyword(),
              opts :: keyword()
            ) ::
              {:ok, GoogleApi.Drive.V3.Model.File.t()}
              | {:ok, Tesla.Env.t()}
              | {:error, any()}

  def drive_files_create(conn, optional_params \\ [], opts \\ []),
    do: impl().drive_files_create(conn, optional_params, opts)

  def drive_files_create_simple(
        conn,
        upload_type,
        metadata,
        data,
        optional_params \\ [],
        opts \\ []
      ),
      do:
        impl().drive_files_create_simple(conn, upload_type, metadata, data, optional_params, opts)

  defp impl,
    do: Application.get_env(:crawl, :google_drive_client, GoogleApi.Drive.V3.Api.Files)
end
