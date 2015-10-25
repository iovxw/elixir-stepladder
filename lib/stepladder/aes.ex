defmodule Stepladder.Socket do
  import Kernel, except: [send: 2]
  use Bitwise

  @block_size 16

  defstruct kv: nil, key: nil, raw: nil

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

  defp xor_byte_by_key(b, <<>>) do
    b
  end

  defp xor_byte_by_key(b, key) do
    <<k, key::binary>> = key
    xor_byte_by_key(b ^^^ k, key)
  end

  defp read_placeholder(socket, key) do
    case socket |> Socket.Stream.recv(1) do
      {:ok, <<len>>} ->
        len = xor_byte_by_key(len, key)
        case socket |> Socket.Stream.recv(len) do
          {:ok, _} ->
            {:ok, len}
          {:error, _} = err ->
            err
        end
      {:error, _} = err ->
        err
    end
  end

  def init(socket, key, side) when side == :server or side == :client do
    if :random.seed == :random.seed0 do
      :random.seed(:os.timestamp)
    end
    case side do
      :client ->
        {private_key, public_key} = Stepladder.ECDH.generate_key(rand_bytes(32))

        l1 = :random.uniform(32)
        r1 = rand_bytes(l1)
        r_head = <<xor_byte_by_key(l1, key)>> <> r1

        l2 = :random.uniform(32)
        r2 = rand_bytes(l2)
        r_tail = <<xor_byte_by_key(l2, key)>> <> r2

        handshake = r_head <> public_key <> r_tail

        try do
          socket |> Socket.Stream.send!(handshake)

          {:ok, _} = socket |> read_placeholder(key)
          data = socket |> Socket.Stream.recv!(32+32)
          <<server_public_key::binary-size(32), hash::binary-size(32)>> = data
          {:ok, _} = socket |> read_placeholder(key)

          result = Stepladder.ECDH.generate_shared_secret(private_key, server_public_key)
          aes_key = result
          <<iv1::binary-size(16), iv2::binary-size(16)>> = result

          if :crypto.hash(:sha256, key <> result) != hash do
            raise "Hash values do not match"
          end

          state = %{recv_state: stream_init(aes_key, iv1),
                    send_state: stream_init(aes_key, iv2)}
          kv = Stepladder.KV.new(state)
          {:ok, %Stepladder.Socket{kv: kv, key: key, raw: socket}}
        rescue
          e -> {:error, e}
        end
      :server ->
        try do
          {:ok, _} = socket |> read_placeholder(key)
          client_public_key = socket |> Socket.Stream.recv!(32)
          {:ok, _} = socket |> read_placeholder(key)

          {private_key, public_key} = Stepladder.ECDH.generate_key(rand_bytes(32))

          result = Stepladder.ECDH.generate_shared_secret(private_key, client_public_key)
          aes_key = result
          <<iv1::binary-size(16), iv2::binary-size(16)>> = result

          hash = :crypto.hash(:sha256, key <> result)

          l1 = :random.uniform(32)
          r1 = rand_bytes(l1)
          r_head = <<xor_byte_by_key(l1, key)>> <> r1

          l2 = :random.uniform(32)
          r2 = rand_bytes(l2)
          r_tail = <<xor_byte_by_key(l2, key)>> <> r2

          handshake = r_head <> public_key <> hash <> r_tail

          socket |> Socket.Stream.send!(handshake)

          state = %{recv_state: stream_init(aes_key, iv2),
                    send_state: stream_init(aes_key, iv1)}
          kv = Stepladder.KV.new(state)
          {:ok, %Stepladder.Socket{kv: kv, key: key, raw: socket}}
        rescue
          e -> {:error, e}
        end
    end
  end

  def recv(self, length) do
    state = self.kv |> Stepladder.KV.get(:recv_state)
    socket = self.raw
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
    {new_state, data} = stream_encrypt(state, data)
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
