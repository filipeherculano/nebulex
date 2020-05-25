defmodule Nebulex.Cache.Persistence do
  @moduledoc false

  import Nebulex.Helpers

  @doc """
  Implementation for `c:Nebulex.Cache.dump/2`.
  """
  def dump(name, path, opts) do
    with_meta(name, & &1.dump(&2, path, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.load/2`.
  """
  def load(name, path, opts) do
    with_meta(name, & &1.load(&2, path, opts))
  end
end
