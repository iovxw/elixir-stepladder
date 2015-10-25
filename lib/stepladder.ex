defmodule Stepladder do
  require Logger
  use Application

  def start(_type, [port: port, key: key]) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Task.Supervisor, [[name: Stepladder.TaskSupervisor]]),
      worker(Task, [Stepladder, :main, [port, key]]),
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Stepladder.Supervisor)
  end

  def main(port, key) do
    Logger.info "Ver: #{Mix.Project.config[:version]} " <>
                "Port: #{port} " <>
                "Key: #{key}"
    server = Socket.TCP.listen!(port)

    server |> serve(key)
  end

  def serve(server, key) do
      case server |> Socket.TCP.accept do
        {:ok, client} ->
          spawn fn ->
            case Stepladder.Socket.init(client, key, :server) do
              {:ok, client} ->
                handle(client)
              {:error, err} ->
                IO.inspect err
            end
          end
        {:error, err} ->
          IO.inspect err
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
    addr = parse_addr(client |> Socket.remote!)
    IO.puts "[TCP] #{addr} #{host}:#{port} [+]"

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
          IO.puts "[TCP] #{addr} #{host}:#{port} [-]"
        end
      {:error, err} ->
        IO.inspect err
        client |> Socket.Stream.send!(<<3>>)
        IO.puts "[TCP] #{addr} #{host}:#{port} [x]"
    end
  end

  defp parse_addr(src) do
    {addr, port} = src
    s = :inet_parse.ntoa(addr)
    "#{s}:#{port}"
  end

  defp wait_all_done(all) do
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
