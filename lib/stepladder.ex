defmodule Stepladder do
  def main(args) do
    [key, port] = args
    IO.puts "port: #{port}\nkey: #{key}"

    server = Socket.TCP.listen!(8082)

    server |> serve(key)
  end

  def serve(server, key) do
      case server |> Socket.TCP.accept do
        {:ok, client} ->
          client = Stepladder.Socket.init(client, key)
          spawn fn -> handle(client) end
        {:error, err} ->
          IO.puts err
      end
      serve(server, key)
  end

  def handle(client) do
    try do
      data = client |> Socket.Stream.recv!(1)
      <<req_type>> = data

      case req_type do
        0 ->
          proxy_tcp(client)
        1 ->
          client |> Socket.Stream.send!(<<2>>)
        n ->
          IO.puts "Unknown req_type: #{n}"
      end
    after
      client |> Socket.close
    end
  end

  def proxy_tcp(client) do
    data = client |> Socket.Stream.recv!(1)
    <<host_len>> = data
    host = client |> Socket.Stream.recv!(host_len)
    data = client |> Socket.Stream.recv!(2)
    <<port::big-integer-size(16)>> = data
    IO.inspect client |> Socket.remote!
    IO.puts "[TCP] #{host}:#{port} [+]"

    case Socket.TCP.connect(host, port) do
      {:ok, server} ->
        try do
          client |> Socket.Stream.send!(<<0>>)
          s = self()
          spawn fn ->
            copy(client, server)
            client |> Socket.close
            server |> Socket.close
            send(s, :done)
          end
          spawn fn ->
            copy(server, client)
            client |> Socket.close
            server |> Socket.close
            send(s, :done)
          end

          wait_all_done(2)
        after
          server |> Socket.close
        end
      {:error, err} ->
        IO.puts err
        client |> Socket.Stream.send!(<<3>>)
    end
    IO.puts "[TCP] #{host}:#{port} [-]"
  end

  defp wait_all_done(all)do
    receive do
      _ ->
        all = all-1
        if all > 0 do
          wait_all_done(all)
        end
    end
  end

  defp copy(src, dst) do
    case src |> Socket.Stream.recv do
      {:ok, data} ->
        if data != nil do
          case dst |> Socket.Stream.send(data) do
            :ok ->
              copy(src, dst)
            {:error, err} ->
              IO.puts err
          end
        end
      {:error, err} ->
        IO.puts err
    end
  end
end
