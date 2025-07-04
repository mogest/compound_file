defmodule CompoundFile.Writer do
  @moduledoc """
  Creates a Compound File Document (CFD) in the Microsoft Compound File Binary Format (CFBF).

  This module allows you to create a new document, add streams and storages, and render the final
  binary representation of the document.

  ## Example usage

      iex> alias CompoundFile.Writer
      iex>
      iex> Writer.new()
      iex> |> Writer.add_file("example.txt", "Hello, World!")
      iex> |> Writer.add_file("data/text/example2.txt", "Another file")
      iex> |> Writer.render()

  This will create a new Compound File Document with the following files:

    - `/example.txt`
    - `/data/text/example2.txt`
  """

  alias CompoundFile.Writer.Document
  alias CompoundFile.Writer.Object

  @sector_size 512
  @mini_sector_size 64
  @mini_stream_cutoff_size 4096

  @difsect 0xFFFFFFFC
  @fatsect 0xFFFFFFFD
  @endofchain 0xFFFFFFFE
  @nostream 0xFFFFFFFF

  @doc "Initialises a new, empty Compound File Document."
  @spec new :: Document.t()
  def new, do: %Document{}

  @doc """
  Adds a file to the Compound File Document.

  If the directory structure specified in the `path` does not exist, directories (storage objects)
  will be created as needed. The file will then be added as a stream object.

  Returns the updated document.
  """
  @spec add_file(Document.t(), String.t(), binary()) :: Document.t()
  def add_file(document, path, data) do
    {filename, dirs} = Path.split(path) |> List.pop_at(-1)

    {document, parent} =
      Enum.reduce(dirs, {document, 0}, fn dir, {document, parent} ->
        case Enum.find(
               document.objects,
               &(&1.name == dir and &1.parent == parent and &1.storage?)
             ) do
          nil -> add_storage(document, parent, dir)
          object -> {document, object.id}
        end
      end)

    add_stream(document, parent, filename, data)
  end

  @doc """
  Adds a stream object to the Compound File Document.

  This function is used to add a binary stream to the document.  The stream object is added to the
  either the root directory (when `parent` is `nil`) or to the specified parent directory (by
  passing the storage object's ID as `parent`).

  Returns the updated document.
  """
  @spec add_stream(Document.t(), non_neg_integer() | nil, String.t(), binary()) :: Document.t()
  def add_stream(document, parent, filename, data) do
    {document, start_sector} =
      cond do
        byte_size(data) == 0 -> {document, @endofchain}
        byte_size(data) < @mini_stream_cutoff_size -> add_to_mini_fat(document, data)
        true -> add_to_fat(document, data)
      end

    new_object = %Object{
      id: length(document.objects) + 1,
      name: filename,
      start_sector: start_sector,
      size: byte_size(data),
      storage?: false,
      parent: parent || 0
    }

    %{document | objects: [new_object | document.objects]}
  end

  @doc """
  Adds a storage object (directory) to the Compound File Document.

  This function creates a new storage entry in the document. The storage object can be used to group
  files (stream objects) together. The `parent` parameter specifies the parent storage object ID, or
  `nil` for the root directory. The `filename` is the name of the storage object.

  Returns a tuple of the updated document and the object ID of the new storage object.
  """
  @spec add_storage(Document.t(), non_neg_integer() | nil, String.t()) ::
          {Document.t(), object_id :: pos_integer()}
  def add_storage(document, parent, filename) do
    new_object = %Object{
      id: length(document.objects) + 1,
      name: filename,
      start_sector: 0,
      size: 0,
      storage?: true,
      parent: parent || 0
    }

    {%{document | objects: [new_object | document.objects]}, new_object.id}
  end

  @doc """
  Renders the Compound File Document to a binary format.

  Returns `{:ok, binary()}` containing the complete binary representation of the document.
  You can write this binary to a file or use it as needed.
  """
  @spec render(Document.t()) ::
          {:ok, binary} | {:error, :empty | :file_size_limit_exceeded | :filename_too_long}
  def render(%Document{} = document) do
    {document, first_mini_stream_sector} = add_to_fat(document, document.mini_stream)

    case build_directory(document, first_mini_stream_sector, byte_size(document.mini_stream)) do
      {:ok, directory_sectors} ->
        {document, first_directory_sector} = add_to_fat(document, directory_sectors)

        mini_fat = IO.iodata_to_binary(document.mini_fat) |> pad_to_sectors(0xFF)
        mini_fat_sector_count = byte_size(mini_fat) |> div(@sector_size)

        {document, first_mini_fat_sector} = add_to_fat(document, mini_fat)

        result = add_fat_to_fat_and_complete_sectors(document)

        header =
          build_header(
            first_directory_sector,
            first_mini_fat_sector,
            mini_fat_sector_count,
            result.fat_sector_count,
            result.header_difat,
            result.first_difat_sector,
            result.difat_sector_count
          )

        {:ok, header <> result.binary}

      error ->
        error
    end
  end

  defp build_directory(document, first_mini_stream_sector, mini_stream_size)
  defp build_directory(%{objects: []}, _, _), do: {:error, :empty}

  defp build_directory(document, first_mini_stream_sector, mini_stream_size) do
    objects = Enum.reverse(document.objects)
    links = build_directory_tree_links(objects)

    {:ok, root_entry} =
      create_directory_entry(
        "Root Entry",
        5,
        first_mini_stream_sector,
        mini_stream_size,
        links[0].child,
        @nostream,
        @nostream
      )

    map_while_ok(objects, fn object ->
      %{child: child, left: left, right: right} = Map.fetch!(links, object.id)

      create_directory_entry(
        object.name,
        if(object.storage?, do: 1, else: 2),
        object.start_sector,
        object.size,
        child || @nostream,
        left || @nostream,
        right || @nostream
      )
    end)
    |> case do
      {:ok, entries} ->
        {:ok, IO.iodata_to_binary([root_entry, entries, directory_padding(entries)])}

      error ->
        error
    end
  end

  defp directory_padding(entries) do
    pad_count =
      case rem(length(entries) + 1, 4) do
        0 -> 0
        rem -> 4 - rem
      end

    Enum.map(1..pad_count//1, fn _ ->
      {:ok, entry} = create_directory_entry("", 0, 0, 0, @nostream, @nostream, @nostream)
      entry
    end)
  end

  defp build_directory_tree_links(objects) do
    tree = Enum.group_by(objects, & &1.parent) |> build_tree(0)
    flatten_tree({{0, tree}, nil, nil})
  end

  defp build_tree(by_parent, parent_id) do
    children = Map.get(by_parent, parent_id, [])

    nodes =
      Enum.map(children, fn child ->
        {child, build_tree(by_parent, child.id)}
      end)
      |> Enum.sort_by(fn {child, _} ->
        name =
          String.upcase(child.name) |> :unicode.characters_to_binary(:utf8, {:utf16, :little})

        [byte_size(name), name]
      end)
      |> Enum.map(fn {child, subtree} -> {child.id, subtree} end)

    split_nodes(nodes)
  end

  defp split_nodes([]), do: nil
  defp split_nodes([node]), do: {node, nil, nil}

  defp split_nodes(nodes) do
    {left, [root | right]} = Enum.split(nodes, div(length(nodes), 2))
    {root, split_nodes(left), split_nodes(right)}
  end

  defp flatten_tree(result \\ %{}, node)
  defp flatten_tree(result, nil), do: result

  defp flatten_tree(result, {{node, child}, left, right}) do
    Map.put(result, node, %{
      child: top_node(child),
      left: top_node(left),
      right: top_node(right)
    })
    |> flatten_tree(child)
    |> flatten_tree(left)
    |> flatten_tree(right)
  end

  defp top_node(nil), do: nil
  defp top_node({{node, _}, _, _}), do: node

  defp pack32(values), do: Enum.map(values, &<<&1::little-32>>) |> IO.iodata_to_binary()

  defp add_to_fat(document, <<>>), do: {document, @endofchain}

  defp add_to_fat(document, data) do
    offset = byte_size(document.sectors)
    start_sector = div(offset, @sector_size)
    size = byte_size(data)
    count = sectors_required(size)

    new_fat_entries =
      Enum.to_list((start_sector + 1)..(start_sector + count - 1)//1) ++ [@endofchain]

    {%{
       document
       | sectors: document.sectors <> pad_to_sectors(data, 0),
         fat: [document.fat, pack32(new_fat_entries)]
     }, start_sector}
  end

  defp calculate_fat_sector_count(fat, additional_sectors \\ 0) do
    fat_regular_bytes = byte_size(fat)

    # For every sector's worth of FAT, we need another four bytes of FAT to point to a FAT sector.
    fat_fat_bytes = sectors_required(fat_regular_bytes) * 4

    # In total, there'll be this many FAT sectors, not taking into account DIFAT sectors.
    presumptive_fat_sector_count =
      sectors_required(fat_regular_bytes + fat_fat_bytes) + additional_sectors

    # For every sector's worth of FAT after the first 109 sectors, we need four bytes of DIFAT to
    # point to the FAT.
    difat_bytes = max((presumptive_fat_sector_count - 109) * 4, 0)

    # Let's calculate how many DIFAT sectors that is, remembering that each DIFAT sector is 508
    # bytes as the last four bytes are reserved to point to the next DIFAT sector.
    difat_sector_count = div(difat_bytes + 507, 508)

    # For every DIFAT sector, we need four bytes of FAT to point to the DIFAT.
    fat_difat_bytes = difat_sector_count * 4

    # The total size of the FAT, including DIFAT and FAT sectors.
    new_fat_sector_count = sectors_required(fat_regular_bytes + fat_fat_bytes + fat_difat_bytes)

    # If we've undercounted the number of FAT sectors the first time around, we need to re-run this
    # algorithm with some additional sectors.
    if new_fat_sector_count > presumptive_fat_sector_count do
      calculate_fat_sector_count(fat, new_fat_sector_count - presumptive_fat_sector_count)
    else
      {new_fat_sector_count, div(fat_fat_bytes, 4), difat_sector_count}
    end
  end

  defp add_fat_to_fat_and_complete_sectors(document) do
    offset = byte_size(document.sectors)
    start_sector = div(offset, @sector_size)

    fat = IO.iodata_to_binary(document.fat)

    {fat_sector_count, fatsect_count, difat_sector_count} = calculate_fat_sector_count(fat)

    fat_sector_range = start_sector..(start_sector + fat_sector_count - 1)//1

    fat_sectors =
      Enum.map(1..fatsect_count//1, fn _ -> @fatsect end) ++
        Enum.map(1..difat_sector_count//1, fn _ -> @difsect end)

    fat = (fat <> pack32(fat_sectors)) |> pad_to_sectors(0xFF)

    <<header_difat::binary-436, sector_difat::binary>> =
      pack32(fat_sector_range) |> pad_to_size(109 * 4, 0xFF)

    difat = difat_chunk(sector_difat, start_sector + fat_sector_count + 1)

    %{
      binary: document.sectors <> fat <> difat,
      header_difat: header_difat,
      first_fat_sector: start_sector,
      fat_sector_count: fat_sector_count,
      first_difat_sector:
        if(difat_sector_count > 0, do: start_sector + fat_sector_count, else: @endofchain),
      difat_sector_count: difat_sector_count
    }
  end

  defp difat_chunk(<<>>, _), do: <<>>

  defp difat_chunk(<<head::binary-508, tail::binary>>, next_sector) when byte_size(tail) > 0 do
    <<head::binary, next_sector::little-32>> <> difat_chunk(tail, next_sector + 1)
  end

  defp difat_chunk(rest, _next_sector) do
    <<pad_to_size(rest, 508, 0xFF)::binary, @endofchain::little-32>>
  end

  defp add_to_mini_fat(document, data) do
    offset = byte_size(document.mini_stream)
    start_mini_sector = div(offset, @mini_sector_size)
    size = byte_size(data)
    count = mini_sectors_required(size)

    new_mini_fat_entries =
      Enum.to_list((start_mini_sector + 1)..(start_mini_sector + count - 1)//1) ++ [@endofchain]

    {%{
       document
       | mini_stream: document.mini_stream <> pad_to_mini_sectors(data),
         mini_fat: [document.mini_fat, pack32(new_mini_fat_entries)]
     }, start_mini_sector}
  end

  defp sectors_required(byte_size) do
    div(byte_size + @sector_size - 1, @sector_size)
  end

  defp pad_to_sectors(data, byte) do
    required_sectors = sectors_required(byte_size(data))
    target_size = required_sectors * @sector_size
    pad_to_size(data, target_size, byte)
  end

  defp mini_sectors_required(byte_size) do
    div(byte_size + @mini_sector_size - 1, @mini_sector_size)
  end

  defp pad_to_mini_sectors(data) do
    required_sectors = mini_sectors_required(byte_size(data))
    target_size = required_sectors * @mini_sector_size
    pad_to_size(data, target_size, 0)
  end

  defp build_header(
         first_directory_sector,
         first_mini_fat_sector,
         mini_fat_sector_count,
         fat_sector_count,
         difat_array,
         first_difat_sector,
         difat_sector_count
       ) do
    <<
      # Document File signature
      0xE11AB1A1E011CFD0::little-64,
      # CLSID (16 bytes)  
      0::128,
      # Minor version
      0x003E::little-16,
      # Major version
      0x0003::little-16,
      # Byte order identifier
      0xFFFE::little-16,
      # Sector size (512 bytes = 2^9)
      9::little-16,
      # Mini sector size (64 bytes = 2^6)  
      6::little-16,
      # Reserved fields
      0::48,
      # Number of directory sectors (not used in v3)
      0::little-32,
      # Number of FAT sectors
      fat_sector_count::little-32,
      # Directory first sector
      first_directory_sector::little-32,
      # Transaction signature (not used)
      0::little-32,
      # Mini stream cutoff (4096 bytes)
      @mini_stream_cutoff_size::little-32,
      # First mini FAT sector
      first_mini_fat_sector::little-32,
      # Number of mini FAT sectors
      mini_fat_sector_count::little-32,
      # First DIFAT sector
      first_difat_sector::little-32,
      # Number of DIFAT sectors  
      difat_sector_count::little-32,
      # DIFAT array (first 109 entries)
      difat_array::binary
    >>
  end

  defp create_directory_entry(name, type, start_sector, size, child, left_sibling, right_sibling) do
    {utf16_name, name_length} =
      if name == "" do
        {<<0::512>>, 0}
      else
        utf16 = :unicode.characters_to_binary(name, :utf8, {:utf16, :little})
        null_terminated = utf16 <> <<0, 0>>
        padded = pad_to_size(null_terminated, 64, 0)
        {padded, byte_size(null_terminated)}
      end

    cond do
      size > 2_147_483_647 ->
        {:error, :file_size_limit_exceeded}

      name_length > 64 ->
        {:error, :filename_too_long}

      true ->
        {:ok,
         <<
           # Name (64 bytes, UTF-16LE)
           utf16_name::binary-64,
           # Name length (including null terminator)
           name_length::little-16,
           # Entry type (1=storage, 2=stream, 5=root)
           type::8,
           # Node color (0=red, 1=black) 
           if(name == "", do: 0, else: 1),
           # Left sibling directory entry
           left_sibling::little-32,
           # Right sibling directory entry
           right_sibling::little-32,
           # Child directory entry
           child::little-32,
           # CLSID (16 bytes)
           0::128,
           # State bits
           0::little-32,
           # Creation time
           0::little-64,
           # Modified time  
           0::little-64,
           # Start sector
           start_sector::little-32,
           # Size (8 bytes)
           size::little-64
         >>}
    end
  end

  defp pad_to_size(data, target_size, _byte) when byte_size(data) >= target_size, do: data

  defp pad_to_size(data, target_size, byte) do
    padding_needed = target_size - byte_size(data)
    data <> :binary.copy(<<byte>>, padding_needed)
  end

  defp map_while_ok(enum, fun) do
    Enum.reduce_while(enum, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end
end
