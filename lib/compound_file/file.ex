defmodule CompoundFile.File do
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
