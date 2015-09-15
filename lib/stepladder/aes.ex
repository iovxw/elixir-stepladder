defmodule Stepladder.Socket do
  import Kernel, except: [send: 2]

  @block_size 16

  defp block_encrypt(key, data) do
    :crypto.block_encrypt(:aes_ecb, key, data)
  end

  defp block_decrypt(key, data) do
    :crypto.block_decrypt(:aes_ecb, key, data)
  end

  defp stream_init(key, iv) do
    :crypto.stream_init(:aes_ctr, key, iv)
  end

  defp stream_encrypt(state, data) do
    :crypto.stream_encrypt(state, data)
  end

  defp stream_decrypt(state, data) do
    :crypto.stream_decrypt(state, data)
  end

  defp rand_bytes(n) do
    :crypto.strong_rand_bytes(n)
  end

  def init(socket, key) do
    # socket, key, recv_state, send_state
    self = {socket, key, nil, nil}
    pid = spawn fn -> loop(self) end
    pid
  end

  defp loop(self) do
    receive do
      {:send, data, pid} ->
        case self |> send_p(data) do
          {:ok, self} ->
            Kernel.send(pid, :ok)
            loop(self)
          {:error, _} = err ->
            Kernel.send(pid, err)
            loop(self)
        end
      {:recv, length, pid} ->
        case self |> recv_p(length) do
          {:ok, self, data} ->
            Kernel.send(pid, {:ok, data})
            loop(self)
          {:error, _} = err ->
            Kernel.send(pid, err)
            loop(self)
        end
      :close ->
        socket = elem(self, 0)
        socket |> Socket.close
    end
  end

  defp recv_p(self, length) do
    {socket, _, state, _} = self
    if state == nil do
      key = elem(self, 1)
      iv = socket |> Socket.Stream.recv!(@block_size)
      iv = block_decrypt(key, iv)
      state = stream_init(key, iv)
    end
    case socket |> Socket.Stream.recv(length) do
      {:ok, data} ->
        if data != nil do
          {new_state, data} = stream_decrypt(state, data)
          self = put_elem(self, 2, new_state) # update state
        end
        {:ok, self, data}
      {:error, _} = err ->
        err
    end
  end

  def recv(socket, length) do
    Kernel.send(socket, {:recv, length, self()})
    receive do
      result ->
        result
    end
  end

  def recv!(socket, length) do
    case socket |> recv(length) do
      {:ok, data} ->
        data
      {:error, err} ->
        socket |> close
        raise Socket.Error, reason: err
    end
  end

  def recv(socket) do
    socket |> recv(0)
  end

  def recv!(socket) do
    case socket |> recv do
      {:ok, data} ->
        data
      {:error, err} ->
        socket |> close
        raise Socket.Error, reason: err
    end
  end

  defp send_p(self, data) do
    {socket, _, _, state} = self
    if state == nil do
      key = elem(self, 1)
      iv = rand_bytes(@block_size)
      state = stream_init(key, iv)

      {new_state, data} = stream_encrypt(state, data)
      data = block_encrypt(key, iv) <> data
    else
      {new_state, data} = stream_encrypt(state, data)
    end
    self = put_elem(self, 3, new_state) # update state
    case socket |> Socket.Stream.send(data) do
      :ok ->
        {:ok, self}
      {:error, _} = err ->
        err
    end
  end

  def send(socket, data) do
    Kernel.send(socket, {:send, data, self()})
    receive do
      result ->
        result
    end
  end

  def send!(socket, data) do
    case socket |> send(data) do
      :ok ->
        data
      {:error, err} ->
        socket |> close
        raise Socket.Error, reason: err
    end
  end

  def close(socket) do
    Kernel.send(socket, :close)
  end
end
