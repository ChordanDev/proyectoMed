defmodule Backend.Config.PatientVerificationConfigTest do
  # Edits application and OS environment: not async.
  use ExUnit.Case, async: false

  alias Backend.Stations.PatientVerification

  @runtime_config Path.expand("../../../config/runtime.exs", __DIR__)
  @compile_config Path.expand("../../../config/config.exs", __DIR__)

  setup do
    original_env = System.get_env("PATIENT_VERIFICATION")
    original_app = Application.fetch_env(:backend, :patient_verification)

    on_exit(fn ->
      if original_env,
        do: System.put_env("PATIENT_VERIFICATION", original_env),
        else: System.delete_env("PATIENT_VERIFICATION")

      case original_app do
        {:ok, value} -> Application.put_env(:backend, :patient_verification, value)
        :error -> Application.delete_env(:backend, :patient_verification)
      end
    end)

    :ok
  end

  describe "PatientVerification.mode/0" do
    test "returns each valid configured mode" do
      for mode <- [:blocking, :audit, :off] do
        Application.put_env(:backend, :patient_verification, mode)
        assert PatientVerification.mode() == mode
      end
    end

    test "is audit when nothing is configured" do
      Application.delete_env(:backend, :patient_verification)
      assert PatientVerification.mode() == :audit
    end

    test "rejects an invalid configured mode" do
      Application.put_env(:backend, :patient_verification, :maybe)

      error = assert_raise ArgumentError, fn -> PatientVerification.mode() end
      assert error.message =~ "patient_verification"
      assert error.message =~ ":maybe"
    end
  end

  test "the compiled default is audit" do
    config = Config.Reader.read!(@compile_config, env: :dev, target: :host)
    assert config[:backend][:patient_verification] == :audit
  end

  describe "PATIENT_VERIFICATION in config/runtime.exs" do
    test "selects each valid mode, ignoring case and surrounding whitespace" do
      for {raw, mode} <- [{"blocking", :blocking}, {" Audit\n", :audit}, {"OFF", :off}] do
        System.put_env("PATIENT_VERIFICATION", raw)
        assert runtime_mode(:dev) == mode
        assert runtime_mode(:prod) == mode
      end
    end

    test "leaves the compiled default in place when unset or blank" do
      System.delete_env("PATIENT_VERIFICATION")
      assert runtime_mode(:dev) == nil

      System.put_env("PATIENT_VERIFICATION", "  ")
      assert runtime_mode(:dev) == nil
    end

    test "rejects an invalid value, naming it" do
      System.put_env("PATIENT_VERIFICATION", "sometimes")

      error = assert_raise ArgumentError, fn -> runtime_mode(:dev) end
      assert error.message =~ "PATIENT_VERIFICATION"
      assert error.message =~ ~s("sometimes")
    end

    test "is ignored in test so the suite stays deterministic" do
      System.put_env("PATIENT_VERIFICATION", "off")
      assert runtime_mode(:test) == nil
    end
  end

  defp runtime_mode(env) do
    # `:prod` requires a secret and a database URL; give them only for the
    # duration of the read.
    secret = System.get_env("SECRET_KEY_BASE")
    database_url = System.get_env("DATABASE_URL")
    System.put_env("SECRET_KEY_BASE", String.duplicate("a", 64))
    System.put_env("DATABASE_URL", "ecto://app:example@db.example.test/proyectomed")

    try do
      @runtime_config
      |> Config.Reader.read!(env: env, target: :host)
      |> Keyword.get(:backend, [])
      |> Keyword.get(:patient_verification)
    after
      if secret,
        do: System.put_env("SECRET_KEY_BASE", secret),
        else: System.delete_env("SECRET_KEY_BASE")

      if database_url,
        do: System.put_env("DATABASE_URL", database_url),
        else: System.delete_env("DATABASE_URL")
    end
  end
end
