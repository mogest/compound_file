defmodule CompoundFile.Writer.Object do
  @moduledoc """
  Represents a storage or stream object in a Microsoft Compound File Binary Format (CFBF) document.

  Create a new object with `CompoundFile.Writer.add_stream/3` or `CompoundFile.Writer.add_storage/3`.
  """

  defstruct [:id, :name, :size, :start_sector, :storage?, :parent]

  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          size: pos_integer(),
          start_sector: pos_integer(),
          storage?: boolean(),
          parent: non_neg_integer()
        }
end
