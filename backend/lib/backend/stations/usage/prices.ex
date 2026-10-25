defmodule Backend.Stations.Usage.Prices do
  @moduledoc """
  The provider price table and the estimated cost of a session's usage
  (issue #342). All prices are USD.

  `config :backend, Backend.Stations.Usage.Prices` holds `:table` (the
  defaults, with their sources, in `config/runtime.exs`) and an optional
  `:override` (the decoded `USAGE_PRICES_JSON` object). The table has:

    * `:claude` - per model id, `:input`, `:output`, `:cache_read` and
      `:cache_write` (5-minute) prices per million tokens;
    * `:jev_call` - per Jev (TypeSafe) request;
    * `:deepgram_minute` - per streamed audio minute;
    * `:elevenlabs_1k_characters` - per 1,000 synthesized characters;
    * `:livekit_participant_minute` - per participant minute in the room.

  A Claude model without a price is reported in `unpriced_models` and adds
  nothing to the estimate, so an unexpected model shows up instead of being
  priced as another one.
  """

  @rates [:jev_call, :deepgram_minute, :elevenlabs_1k_characters, :livekit_participant_minute]
  @claude_prices [:input, :output, :cache_read, :cache_write]
  @token_prices %{
    input_tokens: :input,
    output_tokens: :output,
    cache_read_input_tokens: :cache_read,
    cache_creation_input_tokens: :cache_write
  }

  @type model_prices :: %{
          input: number(),
          output: number(),
          cache_read: number(),
          cache_write: number()
        }

  @type table :: %{
          claude: %{optional(String.t()) => model_prices()},
          jev_call: number(),
          deepgram_minute: number(),
          elevenlabs_1k_characters: number(),
          livekit_participant_minute: number()
        }

  @type estimate :: %{
          total_usd: float(),
          by_provider: %{String.t() => float()},
          unpriced_models: [String.t()]
        }

  @doc """
  The configured table with the `USAGE_PRICES_JSON` override applied.

  Raises `ArgumentError` naming `USAGE_PRICES_JSON` when the override has an
  unknown key, a model without all four prices, or a price that is not a
  non-negative number.
  """
  @spec table() :: table()
  def table do
    config = Application.get_env(:backend, __MODULE__, [])
    base = Keyword.get(config, :table, %{})

    base = %{
      claude: Map.get(base, :claude, %{}),
      jev_call: Map.get(base, :jev_call, 0.0),
      deepgram_minute: Map.get(base, :deepgram_minute, 0.0),
      elevenlabs_1k_characters: Map.get(base, :elevenlabs_1k_characters, 0.0),
      livekit_participant_minute: Map.get(base, :livekit_participant_minute, 0.0)
    }

    case Keyword.get(config, :override) do
      nil -> base
      override when is_map(override) -> Enum.reduce(override, base, &apply_override/2)
      _other -> invalid!("it must be a JSON object")
    end
  end

  defp apply_override({"claude", models}, table) when is_map(models) do
    Enum.reduce(models, table, fn {model, prices}, acc ->
      put_in(acc, [:claude, model], model_prices!(model, prices))
    end)
  end

  defp apply_override({key, value}, table) when is_binary(key) do
    case Enum.find(@rates, &(Atom.to_string(&1) == key)) do
      nil -> invalid!("unknown key #{inspect(key)}")
      rate -> Map.put(table, rate, price!(key, value))
    end
  end

  defp apply_override({key, _value}, _table), do: invalid!("unknown key #{inspect(key)}")

  defp model_prices!(model, prices) when is_binary(model) and is_map(prices) do
    keys = Enum.map(@claude_prices, &Atom.to_string/1)

    if Enum.sort(Map.keys(prices)) == Enum.sort(keys) do
      Map.new(@claude_prices, fn price ->
        {price, price!("#{model}.#{price}", prices[Atom.to_string(price)])}
      end)
    else
      invalid!("model #{inspect(model)} needs exactly #{Enum.join(keys, ", ")}")
    end
  end

  defp model_prices!(model, _prices), do: invalid!("model #{inspect(model)} needs a price object")

  defp price!(_name, value) when is_number(value) and value >= 0, do: value
  defp price!(name, _value), do: invalid!("#{name} must be a non-negative number")

  defp invalid!(reason), do: raise(ArgumentError, "invalid USAGE_PRICES_JSON: #{reason}")

  @doc "The estimated USD cost of a `Backend.Stations.Usage` snapshot under `table`."
  @spec estimate(Backend.Stations.Usage.snapshot(), table()) :: estimate()
  def estimate(snapshot, table \\ table()) do
    {claude, unpriced} = claude_cost(snapshot.claude, table.claude)
    voice = snapshot.voice

    by_provider = %{
      "claude" => claude,
      "jev" => snapshot.jev_calls * table.jev_call,
      "deepgram" => voice.deepgram_audio_seconds / 60 * table.deepgram_minute,
      "elevenlabs" => voice.elevenlabs_characters / 1_000 * table.elevenlabs_1k_characters,
      "livekit" => voice.livekit_participant_minutes * table.livekit_participant_minute
    }

    by_provider = Map.new(by_provider, fn {provider, cost} -> {provider, cost * 1.0} end)

    %{
      total_usd: by_provider |> Map.values() |> Enum.sum(),
      by_provider: by_provider,
      unpriced_models: Enum.sort(unpriced)
    }
  end

  defp claude_cost(models, prices) do
    Enum.reduce(models, {0.0, []}, fn {model, tokens}, {cost, unpriced} ->
      case Map.fetch(prices, model) do
        {:ok, model_prices} ->
          model_cost =
            Enum.reduce(@token_prices, 0.0, fn {field, price}, acc ->
              acc + Map.get(tokens, field, 0) * Map.fetch!(model_prices, price) / 1_000_000
            end)

          {cost + model_cost, unpriced}

        :error ->
          {cost, [model | unpriced]}
      end
    end)
  end
end
