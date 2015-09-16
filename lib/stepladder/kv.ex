defmodule Stepladder.KV do
  def new(map) do
    spawn fn -> loop(map) end
  end

  defp loop(map) do
    receive do
      {:get, key, pid} ->
        data = Dict.get(map, key)
        send(pid, data)
        loop(map)
      {:put, key, data} ->
        map = Dict.put(map, key, data)
        loop(map)
      :close ->
        :ok
    end
  end

  def put(self, key, data) do
    if Process.alive?(self) do
      send(self, {:put, key, data})
    else
      raise "closed"
    end
  end

  def get(self, key) do
    if Process.alive?(self) do
      send(self, {:get, key, self()})
      receive do
        data ->
          data
      end
    else
      raise "closed"
    end
  end

  def close(self) do
    send(self, :close)
  end
end
