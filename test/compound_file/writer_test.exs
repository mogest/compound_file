defmodule CompoundFile.WriterTest do
  use ExUnit.Case

  alias CompoundFile.Reader
  alias CompoundFile.Writer

  test "nothing has changed since I last manually tested it" do
    long_content = "START" <> String.duplicate("a", 4200) <> "END"

    document = Writer.new()
    document = Writer.add_stream(document, nil, "example.txt", "Hello, World!")
    {document, dir} = Writer.add_storage(document, nil, "DirectoryA")
    document = Writer.add_stream(document, dir, "example2.txt", long_content)
    assert {:ok, binary} = Writer.render(document)

    assert Base.encode64(:zlib.gzip(binary)) ==
             "H4sIAAAAAAAAE+3ZT0rDQBQG8G+S/rHWQtwU6ardiwsPIBZacNVFLLgumoUQm1K6aI/jETxJPYIexEzfmKmNXSUQEoXvFx6TDDwyL8xsXt635x+vb71PHLmBi1i30EjNKYnT/YMHtO1crLU2U2cSmv6V++nQn86IiIiIiIiIiAoynoyO+0xUrbsgDKPL/kO0DJ8GVS+GSucjkmuFPsaYy7jEJld+F3W17yWqjDktiVt7H2CNGV6wQCj3V7KCtUR2F3CUg0PfOWtex44jPEvNAR7lrdF39cMcbzf1q5/63VyZid/1X+f+Aj2pP93PzZq38JIxLqfNTH+UObPm/Ji9W5OoS5h/Pk2JE7s/0vFV7XKpYDuyOpRcABwAAA=="

    assert {:ok, streams} = Reader.files(binary)

    assert streams == [
             %CompoundFile.Reader.FileEntry{
               size: 4208,
               path: "Root Entry/DirectoryA/example2.txt",
               start_sector: 0,
               creation_time: nil,
               modified_time: nil,
               clsid: "00000000000000000000000000000000",
               mini_stream_sector: nil
             },
             %CompoundFile.Reader.FileEntry{
               size: 13,
               path: "Root Entry/example.txt",
               start_sector: 0,
               creation_time: nil,
               modified_time: nil,
               clsid: "00000000000000000000000000000000",
               mini_stream_sector: 9
             }
           ]

    assert Reader.file_data(binary, streams |> Enum.at(0)) == {:ok, long_content}
    assert Reader.file_data(binary, streams |> Enum.at(1)) == {:ok, "Hello, World!"}
  end

  test "large files that force DIFAT outside of the header" do
    long_content = "START" <> String.duplicate("a", 58_000_000) <> "END"

    document = Writer.new()
    document = Writer.add_stream(document, nil, "example.txt", long_content)
    assert {:ok, _binary} = Writer.render(document)

    # This test is too slow to read back in :(
  end

  test "edge case for FAT allocation" do
    long_content = "START" <> String.duplicate("a", 7_000_000) <> "END"

    document = Writer.new()
    document = Writer.add_stream(document, nil, "example.txt", long_content)
    assert {:ok, binary} = Writer.render(document)

    assert {:ok, [stream]} = Reader.files(binary)

    assert stream == %CompoundFile.Reader.FileEntry{
             size: 7_000_008,
             path: "Root Entry/example.txt",
             start_sector: 0,
             creation_time: nil,
             modified_time: nil,
             clsid: "00000000000000000000000000000000",
             mini_stream_sector: nil
           }

    assert Reader.file_data(binary, stream) == {:ok, long_content}
  end

  test "mini files only" do
    short_content = "START" <> String.duplicate("a", 3000) <> "END"

    document = Writer.new()
    document = Writer.add_stream(document, nil, "example.txt", "abc")
    document = Writer.add_stream(document, nil, "example2.txt", short_content)
    document = Writer.add_stream(document, nil, "example3.txt", "hello")
    document = Writer.add_stream(document, nil, "example4.txt", String.duplicate("b", 65))
    assert {:ok, binary} = Writer.render(document)

    assert Base.encode64(:zlib.gzip(binary)) ==
             "H4sIAAAAAAAAE+2YWU4CQRCGf0AU3HEXN9x3VPTZhERefUAuAIbEh1GM8QGP4xG8ATfQI+hBZPxLZhIkkzg9o1GS+siXHjp0qtLLhK6X59Tr41P6DR2cIoamnURvW1+E9rlfRoGk09e0bVu6+qmtdBXlymXn0htxUcoXS2VFURRFURRFUf49hfOzq6pl1UL8/6+EJdTtQwlLETV+7pFBATds7/BgNH4K8Yh7l4wZjGsMttoq6ijjGrew+JxlBnXqnxlEI+33Wb/j3Fy/xs8ZZ5BmfKmBmMSX3zcGvOIfB4ofZdvj5OBnzCGNwyv+SaD4pvN/RPO+I3xPkPX/Sbo5vtTuZP/IeZA9JPtCan5S50ugVeOTup5sVzmyQ3SYjuCzBIgUHaPjdIJOQt4JwDTkbAKzkD0CzNF5ukAX6RLN0GW6QlfpGl2nG3STbtFtukN36R7dp1l64OQu5pxnxRx5F3mtv8xnom2O3/84T+V3+ADU2TCqABgAAA=="

    assert {:ok, streams} = Reader.files(binary)

    assert streams == [
             %CompoundFile.Reader.FileEntry{
               size: 3,
               path: "Root Entry/example.txt",
               start_sector: 0,
               creation_time: nil,
               modified_time: nil,
               clsid: "00000000000000000000000000000000",
               mini_stream_sector: 0
             },
             %CompoundFile.Reader.FileEntry{
               size: 3008,
               path: "Root Entry/example2.txt",
               start_sector: 1,
               creation_time: nil,
               modified_time: nil,
               clsid: "00000000000000000000000000000000",
               mini_stream_sector: 0
             },
             %CompoundFile.Reader.FileEntry{
               size: 5,
               path: "Root Entry/example3.txt",
               start_sector: 48,
               creation_time: nil,
               modified_time: nil,
               clsid: "00000000000000000000000000000000",
               mini_stream_sector: 0
             },
             %CompoundFile.Reader.FileEntry{
               size: 65,
               path: "Root Entry/example4.txt",
               start_sector: 49,
               creation_time: nil,
               modified_time: nil,
               clsid: "00000000000000000000000000000000",
               mini_stream_sector: 0
             }
           ]

    assert Reader.file_data(binary, streams |> Enum.at(0)) == {:ok, "abc"}
    assert Reader.file_data(binary, streams |> Enum.at(1)) == {:ok, short_content}
    assert Reader.file_data(binary, streams |> Enum.at(2)) == {:ok, "hello"}
    assert Reader.file_data(binary, streams |> Enum.at(3)) == {:ok, String.duplicate("b", 65)}
  end
end
