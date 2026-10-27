# The suite was written against the blocking pre-delivery Jev gate, so it keeps
# `:blocking` (issue #307). Tests of `:audit` and `:off` set the mode themselves.
Application.put_env(:backend, :patient_verification, :blocking)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Backend.Repo, :manual)

# Fails the run when a test leaves a :backend key holding an explicit `nil` it
# did not hold before the suite (#363): `get_env/3` would ignore its default.
# Restore app env with `Backend.AppEnvHelpers.snapshot/1` and `restore/2`.
backend_env_before_suite = Map.new(Application.get_all_env(:backend))

ExUnit.after_suite(fn _result ->
  case Backend.AppEnvHelpers.leaked_nils(backend_env_before_suite) do
    [] ->
      :ok

    keys ->
      raise "tests left these :backend app env keys as an explicit nil: #{inspect(keys)}. " <>
              "Restore them with Backend.AppEnvHelpers.restore/2."
  end
end)
