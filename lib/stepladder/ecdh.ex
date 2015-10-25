defmodule Stepladder.ECDH do
  def generate_key(rand) do
    private_key = :curve25519.make_private(rand)
    public_key = :curve25519.make_public(private_key)
    {private_key, public_key}
  end

  def generate_shared_secret(private_key, public_key) do
    :curve25519.make_shared(public_key, private_key)
  end
end
