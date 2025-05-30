defmodule CompoundFile.Reader do
  @moduledoc """
  Reader for Compound File Binary (CFB) formatted files.

  This module is in its infancy, and will respond to errors in the file by crashing.  If you are
  going to use this module, please assume that some point in the future these functions will
  return `{:error, reason}` instead of crashing.

  It is also very, very slow working with large files.

  Please contribute to the project if you'd like to use this module in production!
  """

  alias CompoundFile.Reader.FileEntry

  @doc """
  List all files in a compound file.

  Note that passing invalid CFB files to this function will result in an exception or unpredictable behavior.

  Returns `{:ok, [FileEntry.t()]}` with a list of file entries.

  Use `CompoundFile.Reader.file_data/2` to get the data from a file entry.
  """
  @spec files(binary) :: {:ok, [FileEntry.t()]}
  def files(bin) do
    entries_by_id = parse_directory(bin) |> Map.new(fn entry -> {entry.id, entry} end)
    mini_stream_sector = Map.fetch!(entries_by_id, 0).start_sector

    entries_by_id
    |> find_streams()
    |> Enum.reverse()
    |> Enum.map(fn {path, entry} ->
      %FileEntry{
        path: path,
        start_sector: entry.start_sector,
        size: entry.size,
        clsid: entry.clsid,
        creation_time: parse_filetime(entry.creation_time),
        modified_time: parse_filetime(entry.modified_time),
        mini_stream_sector: if(entry.size < 4096, do: mini_stream_sector)
      }
    end)
    |> then(&{:ok, &1})
  end

  @doc """
  Get the data of a file by using its file entry.

  Note that passing invalid CFB files to this function will result in an exception or unpredictable behavior.

  You can get a file entry by calling `CompoundFile.Reader.files/1`.

  Returns `{:ok, binary}` with the file data.
  """
  @spec file_data(binary, FileEntry.t()) :: {:ok, binary}
  def file_data(bin, entry),
    do: {:ok, stream_data(bin, entry.start_sector, entry.size, entry.mini_stream_sector)}

  defp stream_data(bin, start_sector, size, nil) do
    read_sector_chain(bin, start_sector)
    |> binary_part(0, size)
  end

  defp stream_data(bin, start_sector, size, mini_stream_sector) do
    header = parse_header(bin)

    mini_fat = read_sector_chain(bin, header.first_mini_fat_sector)
    mini_fat = for <<entry::little-32 <- mini_fat>>, do: entry

    mini_stream = read_sector_chain(bin, mini_stream_sector)

    for sector <- get_chain(start_sector, mini_fat, []) do
      binary_part(mini_stream, sector * 64, 64)
    end
    |> IO.iodata_to_binary()
    |> binary_part(0, size)
  end

  @doc false
  def parse_header(bin) do
    <<
      signature::little-64,
      clsid::binary-16,
      minor_version::little-16,
      major_version::little-16,
      byte_order::little-16,
      sector_shift::little-16,
      mini_sector_shift::little-16,
      _reserved::binary-6,
      _num_directory_sectors::little-32,
      num_fat_sectors::little-32,
      first_directory_sector::little-32,
      _transaction_signature::little-32,
      mini_stream_cutoff_size::little-32,
      first_mini_fat_sector::little-32,
      num_mini_fat_sectors::little-32,
      first_difat_sector::little-32,
      num_difat_sectors::little-32,
      difat_array::binary-436,
      _rest::binary
    >> = bin

    %{
      signature: signature,
      clsid: clsid,
      minor_version: minor_version,
      major_version: major_version,
      byte_order: byte_order,
      sector_shift: sector_shift,
      mini_sector_shift: mini_sector_shift,
      num_fat_sectors: num_fat_sectors,
      first_directory_sector: first_directory_sector,
      mini_stream_cutoff_size: mini_stream_cutoff_size,
      first_mini_fat_sector: first_mini_fat_sector,
      num_mini_fat_sectors: num_mini_fat_sectors,
      first_difat_sector: first_difat_sector,
      num_difat_sectors: num_difat_sectors,
      difat_array: for(<<entry::little-32 <- difat_array>>, entry != 0xFFFFFFFF, do: entry)
    }
  end

  @doc false
  def read_sector_chain(bin, first_sector) do
    # Parse FAT sector locations from header
    header = parse_header(bin)

    fat_sector_locations =
      header.difat_array ++ load_difat_sectors(bin, header.first_difat_sector)

    sector_size = 512

    # Read FAT sectors
    fat =
      fat_sector_locations
      |> Enum.flat_map(fn sector_idx ->
        offset = 512 + sector_idx * sector_size
        fat_sector = binary_part(bin, offset, sector_size)
        for <<entry::little-32 <- fat_sector>>, do: entry
      end)

    # Follow the FAT chain
    chain = get_chain(first_sector, fat, [])

    # Extract data for each sector in the chain
    for sector <- chain do
      offset = 512 + sector * sector_size
      binary_part(bin, offset, sector_size)
    end
    |> IO.iodata_to_binary()
  end

  @maxregsect 0xFFFFFFFA
  @endofchain 0xFFFFFFFE

  defp load_difat_sectors(_bin, @endofchain), do: []

  defp load_difat_sectors(_bin, sector) when sector > @maxregsect do
    raise "Invalid DIFAT next link sector #{sector}"
  end

  defp load_difat_sectors(bin, sector) do
    entries =
      for <<entry::little-32 <- binary_part(bin, 512 + sector * 512, 508)>>, entry != 0xFFFFFFFF,
        do: entry

    <<next::little-32>> = binary_part(bin, 512 + sector * 512 + 508, 4)

    entries ++ load_difat_sectors(bin, next)
  end

  defp get_chain(start_sector, fat, acc) do
    case Enum.at(fat, start_sector) do
      0xFFFFFFFF -> raise "Sector chain ended unexpectedly at sector #{start_sector}"
      n when n >= 0xFFFFFFFC -> Enum.reverse([start_sector | acc])
      next when next < 0xFFFFFFF0 -> get_chain(next, fat, [start_sector | acc])
      next -> raise "Invalid FAT entry: #{next}"
    end
  end

  @doc false
  def parse_directory(bin) do
    header = parse_header(bin)

    read_sector_chain(bin, header.first_directory_sector)
    |> chunk()
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      <<name::binary-64, name_length::little-16, type, color, left::little-32, right::little-32,
        child::little-32, clsid::binary-16, state::little-32, creation_time::little-64,
        modified_time::little-64, start_sector::little-32, size::little-64>> = entry

      %{
        id: index,
        name: parse_name(name, name_length),
        type: type,
        color: color,
        left: left,
        right: right,
        child: child,
        clsid: Base.encode16(clsid),
        state: state,
        creation_time: if(creation_time == 0, do: nil, else: creation_time),
        modified_time: if(modified_time == 0, do: nil, else: modified_time),
        start_sector: start_sector,
        size: size
      }
    end)
  end

  defp find_streams(
         entries_by_id,
         id \\ 0,
         path \\ "",
         creation_time \\ nil,
         modified_time \\ nil,
         acc \\ []
       ) do
    entry = Map.fetch!(entries_by_id, id)
    creation_time = entry.creation_time || creation_time
    modified_time = entry.modified_time || modified_time

    [{entry.left, path}, entry, {entry.right, path}, {entry.child, Path.join(path, entry.name)}]
    |> Enum.reduce(acc, fn
      {next_id, next_path}, acc ->
        if next_id < 0xFFFFFFFE do
          find_streams(entries_by_id, next_id, next_path, creation_time, modified_time, acc)
        else
          acc
        end

      %{type: 2}, acc ->
        new_path = Path.join(path, entry.name)
        [{new_path, %{entry | creation_time: creation_time, modified_time: modified_time}} | acc]

      _, acc ->
        acc
    end)
  end

  defp parse_name(_name, 0), do: nil

  defp parse_name(name, length) do
    binary_part(name, 0, length - 2) |> :unicode.characters_to_binary({:utf16, :little}, :utf8)
  end

  defp chunk(<<dir::binary-128, rest::binary>>), do: [dir | chunk(rest)]
  defp chunk(<<>>), do: []

  defp parse_filetime(nil), do: nil
  defp parse_filetime(0), do: nil

  defp parse_filetime(value) do
    epoch_offset = 116_444_736_000_000_000

    div(value - epoch_offset, 10)
    |> DateTime.from_unix(:microsecond)
    |> case do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end
end
