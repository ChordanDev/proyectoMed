defmodule Backend.Stations.CaseFormat.Tags do
  @moduledoc """
  Splits a tagged case (issue #330) into its tags.

  A tag line starts with `[NAME args]`, where `NAME` is an uppercase tag name
  and `args` are whitespace-separated tokens: at most one lowercase id, any
  number of `key=value` attributes and any number of uppercase flags. The rest
  of the line, followed by every later line up to the next tag line or Markdown
  heading, is the tag's value. Tag names, attribute keys and flags are compared
  without accents, so `[ESTAÇÃO]` and `[ESTACAO]` are the same tag.

  Lines before the first tag and Markdown headings are not part of any value.
  The module is pure: it reads no file and calls no service.
  """

  @tag_line ~r/^\[(\p{Lu}[\p{Lu}\p{Mn}-]*)(?:\s+([^\]]*))?\]\s*(.*)$/u
  @suspect_tag ~r/^\[\p{Lu}/u
  @heading ~r/^#/
  @id ~r/^[a-z0-9][a-z0-9_-]*$/
  @flag ~r/^\p{Lu}[\p{Lu}\p{Mn}-]*$/u

  @typedoc "One tag: its accent-free `name`, the `label` as written and its 1-based line."
  @type tag :: %{
          name: String.t(),
          label: String.t(),
          id: String.t() | nil,
          attrs: %{String.t() => String.t()},
          flags: [String.t()],
          value: String.t(),
          line: pos_integer()
        }

  @typedoc "A format error located at a 1-based line."
  @type error :: %{line: pos_integer(), message: String.t()}

  @doc "Returns the tags of `text` in document order and the tag-syntax errors."
  @spec scan(String.t()) :: {[tag()], [error()]}
  def scan(text) when is_binary(text) do
    {tags, errors, current} =
      text
      |> String.split(~r/\r?\n/)
      |> Enum.with_index(1)
      |> Enum.reduce({[], [], nil}, &scan_line/2)

    {Enum.reverse(close(tags, current)), Enum.reverse(errors)}
  end

  @doc "Upper-cases `value` and strips its accents (`ESTAÇÃO` becomes `ESTACAO`)."
  @spec normalize(String.t()) :: String.t()
  def normalize(value) do
    value
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.upcase()
  end

  defp scan_line({line, number}, {tags, errors, current}) do
    cond do
      match = Regex.run(@tag_line, line) ->
        {tag, tag_errors} = tag(match, number)
        {close(tags, current), Enum.reverse(tag_errors) ++ errors, tag}

      Regex.match?(@suspect_tag, line) ->
        error = %{line: number, message: "malformed tag line: #{String.trim(line)}"}
        {close(tags, current), [error | errors], nil}

      Regex.match?(@heading, line) ->
        {close(tags, current), errors, nil}

      current == nil ->
        {tags, errors, nil}

      true ->
        {tags, errors, Map.update!(current, :body, &[line | &1])}
    end
  end

  defp tag([_line, name, args, inline], number) do
    {fields, errors} = args(String.split(args), number)

    tag =
      Map.merge(fields, %{
        name: normalize(name),
        label: name,
        line: number,
        inline: String.trim(inline),
        body: []
      })

    {tag, errors}
  end

  defp args(tokens, number) do
    initial = {%{id: nil, attrs: %{}, flags: []}, []}

    {fields, errors} =
      Enum.reduce(tokens, initial, fn token, {fields, errors} ->
        arg(token, fields, errors, number)
      end)

    {Map.update!(fields, :flags, &Enum.reverse/1), errors}
  end

  defp arg(token, fields, errors, number) do
    cond do
      String.contains?(token, "=") ->
        [key, value] = String.split(token, "=", parts: 2)
        key = key |> normalize() |> String.downcase()
        {put_in(fields, [:attrs, key], value), errors}

      Regex.match?(@flag, token) ->
        {Map.update!(fields, :flags, &[normalize(token) | &1]), errors}

      Regex.match?(@id, token) and fields.id == nil ->
        {%{fields | id: token}, errors}

      Regex.match?(@id, token) ->
        {fields, [%{line: number, message: "unexpected second id: #{token}"} | errors]}

      true ->
        {fields, [%{line: number, message: "invalid id: #{token}"} | errors]}
    end
  end

  defp close(tags, nil), do: tags

  defp close(tags, current) do
    body =
      current.body
      |> Enum.reverse()
      |> Enum.map(&String.trim_trailing/1)
      |> trim_blank_lines()

    lines = if current.inline == "", do: body, else: [current.inline | body]

    [current |> Map.drop([:inline, :body]) |> Map.put(:value, Enum.join(lines, "\n")) | tags]
  end

  defp trim_blank_lines(lines) do
    lines
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end
end
