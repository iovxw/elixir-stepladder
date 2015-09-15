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
    data = client |> Stepladder.Socket.recv!(1)
    <<req_type>> = data

    case req_type do
      0 ->
        proxy_tcp(client)
      1 ->
        client |> Stepladder.Socket.send!(<<2>>)
        client |> Stepladder.Socket.close
      n ->
        client |> Stepladder.Socket.close
        IO.puts "Unknown req_type: #{n}"
    end
  end

  def proxy_tcp(client) do
    data = client |> Stepladder.Socket.recv!(1)
    <<host_len>> = data
    host = client |> Stepladder.Socket.recv!(host_len)
    data = client |> Stepladder.Socket.recv!(2)
    <<port::big-integer-size(16)>> = data
    IO.puts "[TCP] #{host}:#{port} [+]"

    case Socket.TCP.connect(host, port) do
      {:ok, server} ->
        client |> Stepladder.Socket.send!(<<0>>)
        s = self()
        spawn fn ->
          copy_as_to_ts(client, server)
          client |> Stepladder.Socket.close
          server |> Socket.close
          send(s, :done)
        end
        spawn fn ->
          copy_ts_to_as(server, client)
          client |> Stepladder.Socket.close
          server |> Socket.close
          send(s, :done)
        end

        wait_all_done(2)
      {:error, err} ->
        IO.puts err
        client |> Stepladder.Socket.send!(<<3>>)
    end
    client |> Stepladder.Socket.close
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

  defp copy_as_to_ts(aessocket, tcpsocket) do
    case aessocket |> Stepladder.Socket.recv do
      {:ok, data} ->
        IO.inspect data
        if data != nil do
          case tcpsocket |> Socket.Stream.send(data) do
            :ok ->
              copy_as_to_ts(aessocket, tcpsocket)
            {:error, err} ->
              IO.puts err
          end
        end
      {:error, err} ->
        IO.puts err
    end
  end

  defp copy_ts_to_as(tcpsocket, aessocket) do
    case tcpsocket |> Socket.Stream.recv do
      {:ok, data} ->
        IO.inspect data
        if data != nil do
          case aessocket |> Stepladder.Socket.send(data) do
            :ok ->
              copy_ts_to_as(tcpsocket, aessocket)
            {:error, err} ->
              IO.puts err
          end
        end
      {:error, err} ->
        IO.puts err
    end
  end
end
