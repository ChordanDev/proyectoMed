defmodule Backend.Config.DatabaseConfigTest do
  @moduledoc """
  `DATABASE_URL`, `DATABASE_SSL`, `POOL_SIZE` and `ECTO_IPV6` in
  config/runtime.exs (issue #329, ADR-014 #346).
  """

  # Mutates operating system environment variables.
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../../config/runtime.exs", __DIR__)
  @variables ~w(DATABASE_URL DATABASE_SSL POOL_SIZE ECTO_IPV6 SECRET_KEY_BASE MAILER_PROVIDER)
  @url "ecto://app:example@db.example.test/proyectomed"

  setup do
    original = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      for {name, value} <- original do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    :ok
  end

  test "prod refuses to boot without DATABASE_URL" do
    error = assert_raise RuntimeError, fn -> repo_config(:prod) end
    assert error.message =~ "DATABASE_URL"
  end

  test "prod connects to DATABASE_URL with verified TLS by default" do
    System.put_env("DATABASE_URL", @url)

    config = repo_config(:prod)

    assert config[:url] == @url
    assert config[:pool_size] == 10
    assert config[:socket_options] == []
    assert config[:ssl][:verify] == :verify_peer
    assert config[:ssl][:server_name_indication] == ~c"db.example.test"
    assert is_list(config[:ssl][:cacerts])
  end

  test "dev keeps the local database unless DATABASE_URL is set" do
    assert repo_config(:dev) == nil

    System.put_env("DATABASE_URL", "  ")
    assert repo_config(:dev) == nil
  end

  test "dev uses DATABASE_URL without TLS unless DATABASE_SSL asks for it" do
    System.put_env("DATABASE_URL", @url)
    assert repo_config(:dev)[:ssl] == false

    System.put_env("DATABASE_SSL", "true")
    assert repo_config(:dev)[:ssl][:verify] == :verify_peer
  end

  test "DATABASE_SSL=false turns TLS off in prod" do
    System.put_env("DATABASE_URL", @url)
    System.put_env("DATABASE_SSL", "false")

    assert repo_config(:prod)[:ssl] == false
  end

  test "DATABASE_SSL accepts boolean spellings regardless of case and whitespace" do
    System.put_env("DATABASE_URL", @url)

    for value <- ["TRUE", "True", " yes ", "On", "1"] do
      System.put_env("DATABASE_SSL", value)

      assert repo_config(:prod)[:ssl][:verify] == :verify_peer,
             "expected TLS for #{inspect(value)}"
    end

    for value <- ["FALSE", "False", " no ", "Off", "0"] do
      System.put_env("DATABASE_SSL", value)
      assert repo_config(:prod)[:ssl] == false, "expected no TLS for #{inspect(value)}"
    end
  end

  test "DATABASE_SSL refuses to boot on an unrecognized value instead of disabling TLS" do
    System.put_env("DATABASE_URL", @url)

    for value <- ["ture", "enabled", ""] do
      System.put_env("DATABASE_SSL", value)
      error = assert_raise RuntimeError, fn -> repo_config(:prod) end
      assert error.message =~ "DATABASE_SSL"
    end
  end

  test "an ssl query parameter in DATABASE_URL refuses to boot instead of overriding DATABASE_SSL" do
    for query <- ["ssl=false", "ssl=true", "sslmode=require&ssl=false"] do
      System.put_env("DATABASE_URL", "#{@url}?#{query}")

      error = assert_raise RuntimeError, fn -> repo_config(:prod) end
      assert error.message =~ "DATABASE_SSL"
      refute error.message =~ "example", "the error must not echo the URL credentials"
    end
  end

  test "Neon's sslmode and channel_binding query parameters keep verified TLS" do
    url = "#{@url}?sslmode=require&channel_binding=require"
    System.put_env("DATABASE_URL", url)

    config = repo_config(:prod)

    assert config[:url] == url
    assert config[:ssl][:verify] == :verify_peer
  end

  test "POOL_SIZE and ECTO_IPV6 tune the pool" do
    System.put_env("DATABASE_URL", @url)
    System.put_env("POOL_SIZE", "4")
    System.put_env("ECTO_IPV6", "true")

    config = repo_config(:prod)

    assert config[:pool_size] == 4
    assert config[:socket_options] == [:inet6]
  end

  test "test never reads DATABASE_URL" do
    System.put_env("DATABASE_URL", @url)

    assert repo_config(:test) == nil
  end

  defp repo_config(env) do
    # `:prod` also requires a secret key base and a mail provider.
    System.put_env("SECRET_KEY_BASE", String.duplicate("a", 64))
    System.put_env("MAILER_PROVIDER", "local")

    @runtime_config
    |> Config.Reader.read!(env: env, target: :host)
    |> Keyword.get(:backend, [])
    |> Keyword.get(Backend.Repo)
  end
end
