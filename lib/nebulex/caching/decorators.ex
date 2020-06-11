defmodule Nebulex.Caching.Decorators do
  @moduledoc ~S"""
  Function decorators which provide a way of annotating functions to be cached
  or evicted. By means of these decorators, it is possible the implementation
  of cache usage patterns like  **Read-through**, **Write-through**,
  **Cache-as-SoR**, etc.

  ## Shared Options

  All of the caching macros below accept the following options:

    * `:cache` - Defines what cache to use (required). Raises `ArgumentError`
      if the option is not present.

    * `:key` - Defines the cache access key (optional). If this option
      is not present, a default key is generated by hashing a two-elements
      tuple; first element is the function's name and the second one the
      list of arguments (e.g: `:erlang.phash2({name, args})`).

    * `:opts` - Defines the cache options that will be passed as argument
      to the invoked cache function (optional).

    * `:match` - Defines a function that takes one argument and will be used to decide
      if the cache should be updated or not (optional). If this option is not present,
      the value will always be updated. Does not have any effect upon eviction
      since values are always evicted before executing the function logic.

  ## Example

  Suppose we are using `Ecto` and we want to define some caching functions in
  the context `MyApp.Accounts`.

      defmodule MyApp.Accounts do
        use Nebulex.Caching.Decorators

        import Ecto.Query

        alias MyApp.Accounts.User
        alias MyApp.Cache
        alias MyApp.Repo

        @decorate cache(cache: Cache, key: {User, id}, opts: [ttl: 3600])
        def get_user!(id) do
          Repo.get!(User, id)
        end

        @decorate cache(cache: Cache, key: {User, clauses})
        def get_user_by!(clauses) do
          Repo.get_by!(User, clauses)
        end

        @decorate cache(cache: Cache)
        def users_by_segment(segment \\\\ "standard") do
          query = from(q in User, where: q.segment == ^segment)
          Repo.all(query)
        end

        @decorate cache(cache: Cache, key: {User, :latest}, match: &(not is_nil(&1)))
        def get_newest_user() do
          Repo.get_newest(User)
        end

        @decorate update(cache: Cache, key: {User, user.id})
        def update_user!(%User{} = user, attrs) do
          user
          |> User.changeset(attrs)
          |> Repo.update!()
        end

        @decorate evict(cache: Cache, keys: [{User, user.id}, {User, [username: user.username]}])
        def delete_user(%User{} = user) do
          Repo.delete(user)
        end
      end
  """

  use Decorator.Define, cache: 1, evict: 1, update: 1

  @doc """
  Provides a way of annotating functions to be cached (cacheable aspect).

  The returned value by the code block is cached if it doesn't exist already
  in cache, otherwise, it is returned directly from cache and the code block
  is not executed.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Examples

      defmodule MyApp.Example do
        use Nebulex.Caching.Decorators

        alias MyApp.Cache

        @decorate cache(cache: Cache, key: name)
        def get_by_name(name, age) do
          # your logic (maybe the loader to retrieve the value from the SoR)
        end

        @decorate cache(cache: Cache, key: age, opts: [ttl: 3600])
        def get_by_age(age) do
          # your logic (maybe the loader to retrieve the value from the SoR)
        end

        @decorate cache(cache: Cache)
        def all(query) do
          # your logic (maybe the loader to retrieve the value from the SoR)
        end

        @decorate cache(cache: Cache, key: {User, :latest}, match: &(not is_nil(&1)))
        def get_newest_user() do
          Repo.get_newest(User)
        end
      end

  The **Read-through** pattern is supported by this decorator. The loader to
  retrieve the value from the system-of-record (SoR) is your function's logic
  and the rest is provided by the macro under-the-hood.
  """
  def cache(attrs, block, context) do
    caching_action(:cache, attrs, block, context)
  end

  @doc """
  Provides a way of annotating functions to be evicted (eviction aspect).

  On function's completion, the given key or keys (depends on the `:key` and
  `:keys` options) are deleted from the cache.

  ## Options

    * `:keys` - Defines the set of keys meant to be evicted from cache
      on function completion.

    * `:all_entries` - Defines if all entries must be removed on function
      completion. Defaults to `false`.

  See the "Shared options" section at the module documentation.

  ## Examples

      defmodule MyApp.Example do
        use Nebulex.Caching.Decorators

        alias MyApp.Cache

        @decorate evict(cache: Cache, key: name)
        def evict(name) do
          # your logic (maybe write/delete data to the SoR)
        end

        @decorate evict(cache: Cache, keys: [name, id])
        def evict_many(name) do
          # your logic (maybe write/delete data to the SoR)
        end

        @decorate evict(cache: Cache, all_entries: true)
        def evict_all(name) do
          # your logic (maybe write/delete data to the SoR)
        end
      end

  The **Write-through** pattern is supported by this decorator. Your function
  provides the logic to write data to the system-of-record (SoR) and the rest
  is provided by the decorator under-the-hood. But in contrast with `update`
  decorator, when the data is written to the SoR, the key for that value is
  deleted from cache instead of updated.
  """
  def evict(attrs, block, context) do
    caching_action(:evict, attrs, block, context)
  end

  @doc """
  Provides a way of annotating functions to be evicted; but updating the cached
  key instead of deleting it.

  The content of the cache is updated without interfering with the function
  execution. That is, the method would always be executed and the result
  cached.

  The difference between `cache/3` and `update/3` is that `cache/3` will skip
  running the function if the key exists in the cache, whereas `update/3` will
  actually run the function and then put the result in the cache.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Examples

      defmodule MyApp.Example do
        use Nebulex.Caching.Decorators

        alias MyApp.Cache

        @decorate update(cache: Cache, key: name)
        def update(name) do
          # your logic (maybe write data to the SoR)
        end

        @decorate update(cache: Cache, opts: [ttl: 3600])
        def update_with_ttl(name) do
          # your logic (maybe write data to the SoR)
        end

        @decorate update(cache: Cache, match: &match_function/1)
        def update_when_not_nil() do
          # your logic (maybe write data to the SoR)
        end

        defp match_function(value) do
          # your condition to skip updating the cache
        edn
      end

  The **Write-through** pattern is supported by this decorator. Your function
  provides the logic to write data to the system-of-record (SoR) and the rest
  is provided by the decorator under-the-hood.
  """
  def update(attrs, block, context) do
    caching_action(:update, attrs, block, context)
  end

  ## Private Functions

  defp caching_action(action, attrs, block, context) do
    cache = attrs[:cache] || raise ArgumentError, "expected cache: to be given as argument"

    key_var =
      Keyword.get(
        attrs,
        :key,
        quote(do: :erlang.phash2({unquote(context.module), unquote(context.name)}))
      )

    keys_var = Keyword.get(attrs, :keys, [])
    match_var = Keyword.get(attrs, :match, quote(do: fn _ -> true end))

    opts_var =
      attrs
      |> Keyword.get(:opts, [])
      |> Keyword.put(:return, :value)

    action_logic = action_logic(action, block, attrs)

    quote do
      cache = unquote(cache)
      key = unquote(key_var)
      keys = unquote(keys_var)
      opts = unquote(opts_var)
      match = unquote(match_var)

      unquote(action_logic)
    end
  end

  defp action_logic(:cache, block, _attrs) do
    quote do
      if value = cache.get(key, opts) do
        value
      else
        value = unquote(block)

        with true <- apply(match, [value]),
             value <- cache.set(key, value, opts) do
          value
        else
          false -> value
        end
      end
    end
  end

  defp action_logic(:evict, block, attrs) do
    all_entries? = Keyword.get(attrs, :all_entries, false)

    quote do
      :ok =
        if unquote(all_entries?) do
          cache.flush()
        else
          Enum.each([key | keys], fn k ->
            if k, do: cache.delete(k)
          end)
        end

      unquote(block)
    end
  end

  defp action_logic(:update, block, _attrs) do
    quote do
      value = unquote(block)

      with true <- apply(match, [value]),
           value <- cache.set(key, value, opts) do
        value
      else
        false -> value
      end
    end
  end
end
