defmodule Stepladder.Socket do
  import Kernel, except: [send: 2]

  @block_size 16

  defstruct kv: nil, key: nil, raw: nil

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
    state = %{recv_state: nil, send_state: nil}
    kv = Stepladder.KV.new(state)
    %Stepladder.Socket{kv: kv, key: key, raw: socket}
  end

  def recv(self, length) do
    state = self.kv |> Stepladder.KV.get(:recv_state)
    socket = self.raw
    if state == nil do
      key = self.key
      iv = socket |> Socket.Stream.recv!(@block_size)
      iv = block_decrypt(key, iv)
      state = stream_init(key, iv)
    end
    case socket |> Socket.Stream.recv(length) do
      {:ok, data} ->
        if data != nil do
          {new_state, data} = stream_decrypt(state, data)
          self.kv |> Stepladder.KV.put(:recv_state, new_state)
        end
        {:ok, data}
      {:error, _} = err ->
        err
    end
  end

  def recv(self) do
    self |> recv(0)
  end

  def send(self, data) do
    state = self.kv |> Stepladder.KV.get(:send_state)
    socket = self.raw
    if state == nil do
      key = self.key
      iv = rand_bytes(@block_size)
      state = stream_init(key, iv)

      {new_state, data} = stream_encrypt(state, data)
      data = block_encrypt(key, iv) <> data
    else
      {new_state, data} = stream_encrypt(state, data)
    end
    self.kv |> Stepladder.KV.put(:send_state, new_state)
    case socket |> Socket.Stream.send(data) do
      :ok ->
        :ok
      {:error, _} = err ->
        err
    end
  end

  def close(self) do
    self.kv |> Stepladder.KV.close
    self.raw |> Socket.close
  end
end

defimpl Socket.Protocol, for: Stepladder.Socket do
  def local(self) do
    self.raw |> Socket.local
  end

  def remote(self) do
    self.raw |> Socket.remote
  end

  def close(self) do
    self |> Stepladder.Socket.close
  end
end

defimpl Socket.Stream.Protocol, for: Stepladder.Socket do
  def send(self, data) do
    self |> Stepladder.Socket.send(data)
  end

  def recv(self) do
    self |> Stepladder.Socket.recv
  end

  def recv(self, length_or_options) do
    self |> Stepladder.Socket.recv(length_or_options)
  end

  def close(self) do
    self |> Stepladder.Socket.close
  end
end
