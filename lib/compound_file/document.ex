defmodule CompoundFile.Document do
  alias CompoundFile.File

  defstruct fat: [], mini_fat: [], files: [], mini_stream: <<>>, sectors: <<>>
  
  @type t :: %__MODULE__{
          fat: [integer()],
          mini_fat: [integer()],
          files: [File.t()],
          mini_stream: binary(),
          sectors: binary()
        }
end
