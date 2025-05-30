defmodule CompoundFile.Debug do
  @moduledoc """
  Debugging utilities for the Compound File structure.

  Used while developing and testing the library, but kept in case you'd like to inspect the
  internals of a compound file.
  """

  alias CompoundFile.Reader

  def print_header(bin) do
    header = Reader.parse_header(bin)
    difat_array = Enum.map_join(header.difat_array, " ", &to_string/1)

    IO.puts("OLE Compound File Header:")
    IO.puts("Signature: 0x#{Integer.to_string(header.signature, 16)}")
    IO.puts("CLSID: #{Base.encode16(header.clsid)}")
    IO.puts("Minor Version: #{header.minor_version}")
    IO.puts("Major Version: #{header.major_version}")
    IO.puts("Byte Order: 0x#{Integer.to_string(header.byte_order, 16)}")

    IO.puts(
      "Sector Shift: #{header.sector_shift} (sector size: #{:math.pow(2, header.sector_shift) |> trunc} bytes)"
    )

    IO.puts(
      "Mini Sector Shift: #{header.mini_sector_shift} (mini sector size: #{:math.pow(2, header.mini_sector_shift) |> trunc} bytes)"
    )

    IO.puts("Number of FAT Sectors: #{header.num_fat_sectors}")
    IO.puts("First Directory Sector Location: #{header.first_directory_sector}")
    IO.puts("Mini Stream Cutoff Size: #{header.mini_stream_cutoff_size}")
    IO.puts("First Mini FAT Sector Location: #{header.first_mini_fat_sector}")
    IO.puts("Number of Mini FAT Sectors: #{header.num_mini_fat_sectors}")
    IO.puts("First DIFAT Sector Location: #{header.first_difat_sector}")
    IO.puts("Number of DIFAT Sectors: #{header.num_difat_sectors}")
    IO.puts("DIFAT Array (first 109 entries): #{difat_array}")
  end

  def dump_sector(bin, sector_number) do
    offset = 512 + sector_number * 512

    if offset + 512 <= byte_size(bin) do
      sector_data = binary_part(bin, offset, 512)
      hexdump(sector_data, offset)
    else
      IO.puts("Sector number #{sector_number} is out of bounds.")
      :error
    end
  end

  def dump_chain(bin, first_sector) do
    sectors = Reader.read_sector_chain(bin, first_sector)

    if byte_size(sectors) > 0 do
      hexdump(sectors)
    else
      IO.puts("No data found for sector chain starting at #{first_sector}.")
      :error
    end
  end

  def hexdump(bin, start \\ 0) when is_binary(bin) do
    bin
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.each(fn {row, idx} ->
      offset = idx * 16

      hex =
        Enum.map(row, fn b -> :io_lib.format("~2.16.0B", [b]) |> List.to_string() end)
        |> Enum.map(&String.upcase/1)
        |> Enum.map(&String.pad_leading(&1, 2, "0"))
        |> Enum.chunk_every(2)
        |> Enum.map_join(" ", &Enum.join(&1, ""))

      ascii =
        Enum.map_join(row, "", fn
          b when b in 32..126 -> <<b>>
          _ -> "."
        end)

      hex =
        String.pad_trailing(hex, 47) |> String.split_at(19) |> Tuple.to_list() |> Enum.join(" ")

      IO.puts(
        "#{String.pad_leading(Integer.to_string(offset + start, 16), 8, "0")}: #{hex}  #{ascii}"
      )
    end)

    IO.puts("")
  end
end
