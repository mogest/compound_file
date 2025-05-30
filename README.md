# CompoundFile

CompoundFile is an Elixir library for reading and writing Compound File Binary Format (CFBF) files, also known as
Compound Document format, Composite Document File V2, or OLE2.0 files.

## Installation

Add `compound_file` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:compound_file, "~> 0.1"}
  ]
end
```

Then, run `mix deps.get` to install the dependency.

## Usage

Documentation available at [https://hexdocs.pm/compound_file](https://hexdocs.pm/compound_file).

Constructing a CFBF file might look something like this:

```elixir
alias CompoundFile.Writer

Writer.new()
|> Writer.add_file("example.txt", "Hello, World!")
|> Writer.add_file("data/text/example2.txt", "Another file")
|> Writer.render()
|> case do
  {:ok, binary} ->
    File.write!("example.cfbf", binary)

  {:error, reason} ->
    IO.puts("Error writing CFBF file: #{reason}")
end
```

Reading a CFBF file can be performed like this:

```elixir
alias CompoundFile.Reader

binary = File.read!("example.cfbf")

{:ok, [file_entry | _]} = Reader.files(binary)
{:ok, content} = Reader.file_data(binary, file_entry)

IO.puts("First filename: #{file_entry.path}")
IO.puts("First file content: #{content}")
```

## Maturity

This library is in an early stage of development. File writing is relatively stable, but reading does not have
any error handling yet. Please contribute if you find bugs or have suggestions for improvements.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request on GitHub.

## License

MIT license, copyright 2025- Mog Nesbitt.
