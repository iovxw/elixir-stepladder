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
    send(self, {:put, key, data})
  end

  def get(self, key) do
    send(self, {:get, key, self()})
    receive do
      data ->
        data
    end
  end

  def close(self) do
    send(self, :close)
  end
end
