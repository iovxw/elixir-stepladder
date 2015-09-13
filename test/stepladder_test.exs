defmodule StepladderTest do
  use ExUnit.Case

  def handle(client) do
    client = Stepladder.Stream.init(client, <<"0000000000000000">>)

    data = client |> Stepladder.Stream.recv!
    IO.inspect data
    client |> Stepladder.Stream.send!("OK!")
    client |> Stepladder.Stream.close
  end

  def serve(server) do
      client = server |> Socket.TCP.accept!
      handle(client)
  end

  test "ase stream" do
    server = Socket.TCP.listen!(8082)

    spawn(fn -> server |> serve end)

    client = Socket.TCP.connect!("127.0.0.1", 8082)
    client = Stepladder.Stream.init(client, <<"0000000000000000">>)

    client |> Stepladder.Stream.send!("OK?")
    data = client |> Stepladder.Stream.recv!
    IO.inspect data
    client |> Stepladder.Stream.close
  end
end
