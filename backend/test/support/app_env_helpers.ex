defmodule Backend.AppEnvHelpers do
  @moduledoc """
  Saves and restores `:backend` application env in tests (#363).

  `Application.get_env(:backend, key, default)` falls back to `default` only
  when the key is absent, not when it holds `nil`. Saving a key with
  `get_env/2` and restoring it with `put_env/3` turns an unset key into an
  explicit `nil` that leaks into later tests. Save with `snapshot/1` and
  restore with `restore/2` instead:

      previous = AppEnvHelpers.snapshot(:station_ai_adapter)
      Application.put_env(:backend, :station_ai_adapter, MyAdapter)
      on_exit(fn -> AppEnvHelpers.restore(:station_ai_adapter, previous) end)
  """

  @type snapshot :: {:ok, term()} | :error

  @doc "Returns the current `:backend` value of `key` as `{:ok, value}`, or `:error` when unset."
  @spec snapshot(term()) :: snapshot()
  def snapshot(key), do: snapshot(:backend, key)

  @doc "Like `snapshot/1`, for the env of another application `app`."
  @spec snapshot(atom(), term()) :: snapshot()
  def snapshot(app, key), do: Application.fetch_env(app, key)

  @doc """
  Puts back a `:backend` value saved by `snapshot/1`: the saved value when the
  key was set (an explicit `nil` included), or deletes the key when it was unset.
  """
  @spec restore(term(), snapshot()) :: :ok
  def restore(key, snapshot), do: restore(:backend, key, snapshot)

  @doc "Like `restore/2`, for the env of another application `app`."
  @spec restore(atom(), term(), snapshot()) :: :ok
  def restore(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  def restore(app, key, :error), do: Application.delete_env(app, key)

  @doc """
  Lists, sorted, the keys of `env` that hold `nil` but were absent or held
  another value in `before` (a map of the `:backend` env taken earlier).
  """
  @spec leaked_nils(map(), keyword()) :: [atom()]
  def leaked_nils(before, env \\ Application.get_all_env(:backend)) do
    env
    |> Enum.filter(fn {key, value} -> is_nil(value) and Map.get(before, key, :absent) != nil end)
    |> Enum.map(fn {key, _value} -> key end)
    |> Enum.sort()
  end
end
