defmodule Backend.Accounts.MailerConfigTest do
  @moduledoc """
  The account email provider (#336) is chosen in config/runtime.exs by
  `MAILER_PROVIDER`. Reads config/runtime.exs with a controlled environment:
  not async, because the operating system environment is global.
  """

  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../../config/runtime.exs", __DIR__)
  @variables ~w(MAILER_PROVIDER MAILER_API_KEY MAILER_DOMAIN MAILER_FROM_EMAIL MAILER_FROM_NAME
                DATABASE_URL DATABASE_SSL SECRET_KEY_BASE)
  # The other variables `:prod` requires to boot.
  @prod_boot %{
    "DATABASE_URL" => "ecto://user:pass@localhost/backend_prod",
    "DATABASE_SSL" => "false",
    "SECRET_KEY_BASE" => String.duplicate("a", 64)
  }
  @resend %{
    "MAILER_PROVIDER" => "resend",
    "MAILER_API_KEY" => "re_test_key",
    "MAILER_FROM_EMAIL" => "conta@proyectomed.example"
  }

  setup do
    saved = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  defp read(env, config_env) do
    env = if config_env == :prod, do: Map.merge(@prod_boot, env), else: env
    Enum.each(@variables, &System.delete_env/1)
    System.put_env(env)
    Config.Reader.read!(@runtime_config, env: config_env, target: :host)
  end

  defp mailer(config), do: get_in(config, [:backend, Backend.Accounts.Mailer])

  test "without MAILER_PROVIDER, dev keeps the local adapter from config.exs" do
    config = read(%{}, :dev)

    assert mailer(config) == nil
    assert get_in(config, [:backend, :mailer_from]) == nil
  end

  test "an API provider sets the adapter, its key, the HTTP client and the sender" do
    config = read(Map.put(@resend, "MAILER_FROM_NAME", "Equipe proyectoMed"), :prod)

    assert mailer(config) == [adapter: Swoosh.Adapters.Resend, api_key: "re_test_key"]
    assert get_in(config, [:swoosh, :api_client]) == Swoosh.ApiClient.Req
    assert get_in(config, [:swoosh, :local]) == false

    assert get_in(config, [:backend, :mailer_from]) ==
             {"Equipe proyectoMed", "conta@proyectomed.example"}
  end

  test "each supported provider maps to its Swoosh adapter, case-insensitively" do
    for {name, adapter} <- [
          {" Postmark ", Swoosh.Adapters.Postmark},
          {"SENDGRID", Swoosh.Adapters.Sendgrid},
          {"brevo", Swoosh.Adapters.Brevo}
        ] do
      config = read(Map.put(@resend, "MAILER_PROVIDER", name), :prod)
      assert Keyword.fetch!(mailer(config), :adapter) == adapter
    end
  end

  test "mailgun also needs MAILER_DOMAIN" do
    mailgun = Map.put(@resend, "MAILER_PROVIDER", "mailgun")

    assert_raise ArgumentError, ~r/MAILER_DOMAIN/, fn -> read(mailgun, :prod) end

    config = read(Map.put(mailgun, "MAILER_DOMAIN", "mg.proyectomed.example"), :prod)

    assert mailer(config) == [
             adapter: Swoosh.Adapters.Mailgun,
             api_key: "re_test_key",
             domain: "mg.proyectomed.example"
           ]
  end

  test "the sender name defaults to proyectoMed" do
    config = read(@resend, :prod)

    assert get_in(config, [:backend, :mailer_from]) ==
             {"proyectoMed", "conta@proyectomed.example"}
  end

  test "unset or local keeps the local adapter, also in production" do
    assert mailer(read(%{}, :prod)) == nil
    assert mailer(read(%{"MAILER_PROVIDER" => " Local "}, :prod)) == nil
  end

  test "refuses an unknown provider, an API provider without a key or without a sender" do
    assert_raise ArgumentError, ~r/MAILER_PROVIDER.*"pigeon"/s, fn ->
      read(Map.put(@resend, "MAILER_PROVIDER", "pigeon"), :prod)
    end

    assert_raise ArgumentError, ~r/MAILER_API_KEY/, fn ->
      read(Map.delete(@resend, "MAILER_API_KEY"), :prod)
    end

    assert_raise ArgumentError, ~r/MAILER_FROM_EMAIL/, fn ->
      read(Map.delete(@resend, "MAILER_FROM_EMAIL"), :prod)
    end
  end

  test "the error never echoes the API key" do
    error =
      assert_raise ArgumentError, fn ->
        read(Map.merge(@resend, %{"MAILER_PROVIDER" => "pigeon"}), :prod)
      end

    refute Exception.message(error) =~ "re_test_key"
  end

  test "the test environment reads none of it" do
    config = read(@resend, :test)

    assert mailer(config) == nil
    assert get_in(config, [:swoosh, :api_client]) == nil
  end

  describe "the configured HTTP client" do
    setup do
      previous = Application.get_env(:swoosh, :api_client)
      Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)
      on_exit(fn -> Application.put_env(:swoosh, :api_client, previous) end)
    end

    test "delivers through the provider API with the key" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:request, conn.request_path, Plug.Conn.get_req_header(conn, "authorization")}
        )

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s({"id":"email-1"}))
      end

      email =
        Swoosh.Email.new(
          to: "aluno@example.com",
          from: {"proyectoMed", "conta@proyectomed.example"},
          subject: "Oi",
          text_body: "Oi"
        )
        |> Swoosh.Email.put_private(:client_options, plug: plug)

      assert {:ok, %{id: "email-1"}} =
               Swoosh.Adapters.Resend.deliver(email, api_key: "re_test_key")

      assert_received {:request, "/emails", ["Bearer re_test_key"]}
    end
  end
end
