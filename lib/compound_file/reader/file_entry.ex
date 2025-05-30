defmodule CompoundFile.Reader.FileEntry do
  @moduledoc """
  Represents a file entry in a Microsoft Compound File Binary Format (CFBF) document.

  This module is used by `CompoundFile.Reader` to represent files within the compound file.
  """

  defstruct [
    :path,
    :start_sector,
    :size,
    :clsid,
    :creation_time,
    :modified_time,
    :mini_stream_sector
  ]

  @type t :: %__MODULE__{
          path: String.t(),
          start_sector: non_neg_integer(),
          size: non_neg_integer(),
          clsid: String.t(),
          creation_time: DateTime.t() | nil,
          modified_time: DateTime.t() | nil,
          mini_stream_sector: non_neg_integer() | nil
        }
end
