defmodule Backend.Stations.Usage.PricesTest do
  # async: false: some tests change the application environment.
  use ExUnit.Case, async: false

  alias Backend.Stations.Usage.Prices

  @snapshot %{
    claude: %{
      "claude-haiku-5-5" => %{
        input_tokens: 1_000,
        output_tokens: 2_000,
        cache_read_input_tokens: 10_000,
        cache_creation_input_tokens: 4_000
      }
    },
    jev_calls: 10,
    voice: %{
      deepgram_audio_seconds: 120.0,
      elevenlabs_characters: 2_500,
      livekit_participant_minutes: 20.0
    }
  }

  defp with_override(override, fun) do
    previous = Application.get_env(:backend, Prices)
    Application.put_env(:backend, Prices, Keyword.put(previous || [], :override, override))

    try do
      fun.()
    after
      Application.put_env(:backend, Prices, previous)
    end
  end

  test "the default table carries the public prices of the models in use (2026-10-25)" do
    table = Prices.table()

    assert table.claude["claude-haiku-5-5"] == %{
             input: 0.10,
             output: 0.50,
             cache_read: 0.01,
             cache_write: 0.125
           }

    assert table.claude["claude-sonnet-5-5"] == %{
             input: 2.0,
             output: 10.0,
             cache_read: 0.10,
             cache_write: 2.50
           }

    assert table.claude["claude-opus-5-5"] == %{
             input: 4.0,
             output: 20.0,
             cache_read: 0.20,
             cache_write: 5.0
           }

    assert table.deepgram_minute == 0.0048
    assert table.elevenlabs_1k_characters == 0.04
    assert table.livekit_participant_minute == 0.0005
    assert table.jev_call == 0.0
  end

  test "estimate/2 prices every provider and sums them" do
    table = %{Prices.table() | jev_call: 0.002}
    estimate = Prices.estimate(@snapshot, table)

    assert_in_delta estimate.by_provider["claude"], 0.0017, 1.0e-9
    assert_in_delta estimate.by_provider["jev"], 0.02, 1.0e-9
    assert_in_delta estimate.by_provider["deepgram"], 0.0096, 1.0e-9
    assert_in_delta estimate.by_provider["elevenlabs"], 0.1, 1.0e-9
    assert_in_delta estimate.by_provider["livekit"], 0.01, 1.0e-9
    assert_in_delta estimate.total_usd, 0.0017 + 0.02 + 0.0096 + 0.1 + 0.01, 1.0e-9
    assert estimate.unpriced_models == []
  end

  test "a model missing from the table is listed as unpriced and adds nothing" do
    snapshot =
      put_in(@snapshot, [:claude, "claude-unknown-1"], %{
        input_tokens: 1_000_000,
        output_tokens: 0,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0
      })

    estimate = Prices.estimate(snapshot, Prices.table())

    assert estimate.unpriced_models == ["claude-unknown-1"]
    assert_in_delta estimate.by_provider["claude"], 0.0017, 1.0e-9
  end

  test "USAGE_PRICES_JSON entries override the defaults, per model and per provider" do
    override = %{
      "claude" => %{
        "claude-haiku-5-5" => %{
          "input" => 1,
          "output" => 5,
          "cache_read" => 0.1,
          "cache_write" => 1.25
        },
        "claude-new-6" => %{
          "input" => 3,
          "output" => 15,
          "cache_read" => 0.3,
          "cache_write" => 3.75
        }
      },
      "jev_call" => 0.001,
      "deepgram_minute" => 0.0042
    }

    with_override(override, fn ->
      table = Prices.table()

      assert table.claude["claude-haiku-5-5"] == %{
               input: 1,
               output: 5,
               cache_read: 0.1,
               cache_write: 1.25
             }

      assert table.claude["claude-new-6"].output == 15
      assert table.claude["claude-opus-5-5"].input == 4.0
      assert table.jev_call == 0.001
      assert table.deepgram_minute == 0.0042
      assert table.livekit_participant_minute == 0.0005
    end)
  end

  test "an override with a negative, non-numeric or unknown entry is rejected" do
    for override <- [
          %{"jev_call" => -1},
          %{"deepgram_minute" => "cheap"},
          %{"claude" => %{"claude-haiku-5-5" => %{"input" => 1}}},
          %{"openai" => 1}
        ] do
      with_override(override, fn ->
        assert_raise ArgumentError, ~r/USAGE_PRICES_JSON/, fn -> Prices.table() end
      end)
    end
  end
end
