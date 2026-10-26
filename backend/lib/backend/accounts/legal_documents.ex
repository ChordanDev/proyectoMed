defmodule Backend.Accounts.LegalDocuments do
  @moduledoc """
  The terms of use and the privacy policy a learner accepts at sign-up (#336).

  The texts are PLACEHOLDERS: replace the paragraphs with the reviewed legal
  texts and bump `version` whenever a text changes, so every account keeps the
  version it accepted (`users.terms_version` and `users.privacy_version`).
  """

  @type kind :: :terms | :privacy
  @type t :: %{kind: kind(), title: String.t(), version: String.t(), paragraphs: [String.t()]}

  @terms %{
    kind: :terms,
    title: "Termos de Uso",
    version: "2026-10-22-rascunho",
    paragraphs: [
      "Texto provisório. Os Termos de Uso definitivos serão publicados antes do lançamento.",
      "O proyectoMed oferece estações de prática clínica simulada para fins educacionais. " <>
        "O conteúdo não substitui orientação médica nem avaliação oficial.",
      "Ao criar uma conta, você se compromete a usar a plataforma de forma pessoal e a " <>
        "manter a sua senha em sigilo.",
      "Você pode excluir a sua conta a qualquer momento nas configurações da conta."
    ]
  }

  @privacy %{
    kind: :privacy,
    title: "Política de Privacidade",
    version: "2026-10-22-rascunho",
    paragraphs: [
      "Texto provisório. A Política de Privacidade definitiva será publicada antes do lançamento.",
      "Guardamos o seu e-mail, a data e a versão dos documentos que você aceitou e os dados " <>
        "das suas práticas para oferecer o serviço.",
      "Ao excluir a sua conta, apagamos o seu cadastro e todos os dados associados a ele."
    ]
  }

  @doc """
  Returns the current version of a legal document.
  """
  @spec get(kind()) :: t()
  def get(:terms), do: @terms
  def get(:privacy), do: @privacy
end
