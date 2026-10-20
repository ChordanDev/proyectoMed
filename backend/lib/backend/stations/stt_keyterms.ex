defmodule Backend.Stations.SttKeyterms do
  @moduledoc """
  Derives the speech-to-text keyterm list for a Station Package (#292).

  Deepgram nova-3 Keyterm Prompting boosts recognition of the terms it is
  given. Authoring them by hand for every station does not scale, so the list
  is derived deterministically from the package, in priority order:

    1. the optional authored `stt_keyterms`, kept first and in order;
    2. eponyms named after a clinical anchor noun anywhere in the package text
       (`ponto de McBurney`, `sinal de Blumberg`, `escala de Glasgow`);
    3. terms of a small shared pt-BR clinical lexicon that the package text
       mentions as whole words (`palpação`, `fossa ilíaca direita`, ...);
    4. the impresso request keywords, in authored order.

  Terms are deduplicated case-insensitively (first spelling wins) and capped.
  Deepgram limits keyterms to 500 tokens per request and recommends 20-50
  terms (https://developers.deepgram.com/docs/keyterm). Its tokenizer is not
  published, so the cap is `max_terms/0` terms and a conservative estimate of
  `ceil(characters / 2)` tokens per term within `token_budget/0`.
  """

  @max_terms 50
  @token_budget 450

  @anchor_nouns ~w(sinal sinais ponto pontos manobra manobras teste testes
                   tríade escala escore critério critérios classificação)

  # Shared pt-BR clinical vocabulary. A term is used only when the package
  # mentions it, so the list can stay broad without spending the budget on
  # vocabulary foreign to the station. Matched case-insensitively.
  @lexicon [
    "palpação",
    "palpação superficial",
    "palpação profunda",
    "percussão",
    "ausculta",
    "inspeção",
    "descompressão brusca",
    "defesa abdominal",
    "defesa voluntária",
    "rigidez abdominal",
    "peritonite",
    "irritação peritoneal",
    "fossa ilíaca direita",
    "fossa ilíaca esquerda",
    "quadrante inferior direito",
    "quadrante inferior esquerdo",
    "hipocôndrio direito",
    "epigástrio",
    "mesogástrio",
    "hipogástrio",
    "periumbilical",
    "ruídos hidroaéreos",
    "punho-percussão",
    "psoas",
    "obturador",
    "apendicite",
    "apendicectomia",
    "videolaparoscopia",
    "laparotomia",
    "anorexia",
    "inapetência",
    "náusea",
    "vômito",
    "febre",
    "taquicardia",
    "leucocitose",
    "hemograma",
    "leucograma",
    "proteína C reativa",
    "ultrassonografia",
    "tomografia computadorizada",
    "antibioticoterapia",
    "analgesia",
    "dipirona",
    "hidratação venosa",
    "jejum",
    "dor torácica",
    "precordial",
    "irradiação",
    "dispneia",
    "sudorese",
    "infarto",
    "angina",
    "troponina",
    "eletrocardiograma",
    "murmúrio vesicular",
    "bulhas"
  ]

  @doc "Maximum number of keyterms sent per request."
  @spec max_terms() :: pos_integer()
  def max_terms, do: @max_terms

  @doc "Estimated-token budget, kept below Deepgram's 500-token keyterm limit."
  @spec token_budget() :: pos_integer()
  def token_budget, do: @token_budget

  @doc "Conservative token estimate for a keyterm list: ceil(chars / 2) per term."
  @spec estimated_tokens([String.t()]) :: non_neg_integer()
  def estimated_tokens(terms), do: terms |> Enum.map(&term_tokens/1) |> Enum.sum()

  @doc """
  Returns the ordered, deduplicated and capped keyterm list for `package`.
  """
  @spec for_package(map()) :: [String.t()]
  def for_package(package) when is_map(package) do
    text = package |> strings() |> Enum.join("\n")

    (explicit(package) ++ eponyms(text) ++ lexicon_terms(text) ++ impresso_keywords(package))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
    |> cap()
  end

  defp explicit(package), do: package |> Map.get("stt_keyterms") |> only_strings()

  defp impresso_keywords(package) do
    package
    |> Map.get("impressos")
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"keywords" => keywords} -> only_strings(keywords)
      _ -> []
    end)
  end

  defp only_strings(value), do: value |> List.wrap() |> Enum.filter(&is_binary/1)

  defp eponyms(text) do
    anchors = Enum.join(@anchor_nouns, "|")

    regex =
      Regex.compile!(
        "(?<!\\p{L})(?i:#{anchors})\\s+d(?:e|o|a|os|as)\\s+(\\p{Lu}[\\p{L}'-]+)",
        "u"
      )

    regex
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
  end

  defp lexicon_terms(text) do
    downcased = String.downcase(text)

    Enum.filter(@lexicon, fn term ->
      Regex.match?(~r/(?<!\p{L})#{Regex.escape(String.downcase(term))}(?!\p{L})/u, downcased)
    end)
  end

  defp cap(terms) do
    terms
    |> Enum.reduce_while({[], 0}, fn term, {kept, tokens} ->
      next = tokens + term_tokens(term)

      if length(kept) < @max_terms and next <= @token_budget,
        do: {:cont, {[term | kept], next}},
        else: {:halt, {kept, tokens}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp term_tokens(term), do: div(String.length(term) + 1, 2)

  # Every string in the package, maps walked in sorted key order so the
  # first-occurrence order of eponyms is stable.
  defp strings(value) when is_binary(value), do: [value]
  defp strings(value) when is_list(value), do: Enum.flat_map(value, &strings/1)

  defp strings(value) when is_map(value),
    do: value |> Enum.sort_by(&elem(&1, 0)) |> Enum.flat_map(fn {_key, v} -> strings(v) end)

  defp strings(_value), do: []
end
