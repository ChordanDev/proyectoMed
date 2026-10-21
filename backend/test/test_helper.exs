# The suite was written against the blocking pre-delivery Jev gate, so it keeps
# `:blocking` (issue #307). Tests of `:audit` and `:off` set the mode themselves.
Application.put_env(:backend, :patient_verification, :blocking)

ExUnit.start()
