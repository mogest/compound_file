defmodule CompoundFile do
  @moduledoc """
  A library for reading and writing Microsoft Compound File Binary Format (CFBF) files, also known
  as Composite Document File v2 (CDF).

  This module provides functions to create and read CFBF documents.

  See `CompoundFile.Writer` for documentation on creating documents, and `CompoundFile.Reader` for
  reading existing documents.

  ## Example

      iex> alias CompoundFile.{Reader, Writer}
      iex>
      iex> {:ok, binary} =
      iex>   Writer.new()
      iex>   |> Writer.add_file("example.txt", "Hello, World!")
      iex>   |> Writer.render()
      iex>
      iex> {:ok, [entry]} = Reader.files(binary)
      iex>
      iex> Reader.file_data(binary, entry)
      {:ok, "Hello, World!"}
  """
end
