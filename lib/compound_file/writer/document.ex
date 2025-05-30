defmodule CompoundFile.Writer.Document do
  @moduledoc """
  Represents a Microsoft Compound File Binary Format (CFBF) document.

  Create a new document with `CompoundFile.Writer.new/0`, and add stream and storage objects using
  the `CompoundFile.Writer` module.
  """

  alias CompoundFile.Writer.Object

  defstruct fat: [], mini_fat: [], objects: [], mini_stream: <<>>, sectors: <<>>

  @type t :: %__MODULE__{
          fat: [integer()],
          mini_fat: [integer()],
          objects: [Object.t()],
          mini_stream: binary(),
          sectors: binary()
        }
end
