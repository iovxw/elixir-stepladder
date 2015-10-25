defmodule StepladderTest do
  use ExUnit.Case

  def handle(client) do
    {:ok, client} = Stepladder.Socket.init(client, <<"0000000000000000">>, :server)

    data = client |> Socket.Stream.recv!
    IO.inspect data
    client |> Socket.Stream.send!("OK!")
    data = client |> Socket.Stream.recv!
    IO.inspect data
    client |> Socket.Stream.send!("OK!")
    data = client |> Socket.Stream.recv!
    IO.inspect data
    client |> Socket.Stream.send!("OK!")
    client |> Socket.close
  end

  def serve(server) do
      client = server |> Socket.TCP.accept!
      handle(client)
  end

  test "ase stream" do
    server = Socket.TCP.listen!(8082)

    spawn(fn -> server |> serve end)

    server = Socket.TCP.connect!("127.0.0.1", 8082)
    {:ok, server} = Stepladder.Socket.init(server, <<"0000000000000000">>, :client)

    server |> Socket.Stream.send!("OK?")
    data = server |> Socket.Stream.recv!
    IO.inspect data
    server |> Socket.Stream.send!("OK?")
    data = server |> Socket.Stream.recv!
    IO.inspect data
    server |> Socket.Stream.send!("OK?")
    data = server |> Socket.Stream.recv!
    IO.inspect data
    server |> Socket.close
  end
end
