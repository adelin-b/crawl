defmodule Crawl.Assets.Archiver do
  @moduledoc """
  Helper module for archiving assets.
  """

  def zip_directory(source_dir, zip_path) do
    if File.dir?(source_dir) do
      do_zip_directory(source_dir, zip_path)
    else
      {:error, :source_dir_not_found}
    end
  end

  defp do_zip_directory(source_dir, zip_path) do
    files =
      list_relative_files(source_dir)
      |> Enum.map(&String.to_charlist/1)

    # Ensure parent directory of zip exists
    zip_dir = Path.dirname(zip_path)
    File.mkdir_p!(zip_dir)

    if files == [] do
      {:ok, zip_path}
    else
      create_zip(source_dir, zip_path, files)
    end
  end

  defp create_zip(source_dir, zip_path, files) do
    cwd_charlist = String.to_charlist(source_dir)

    case :zip.create(String.to_charlist(zip_path), files, [{:cwd, cwd_charlist}]) do
      {:ok, _path} -> {:ok, zip_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_relative_files(dir) do
    Path.wildcard(Path.join(dir, "**/*"))
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(fn path -> Path.relative_to(path, dir) end)
  end
end
