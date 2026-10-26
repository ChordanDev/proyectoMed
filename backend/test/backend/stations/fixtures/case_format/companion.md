# Fixture: a case with a patient and a companion (issue #330)

Minimal, not clinically reviewed. It exists to prove that the format declares
a companion with its own profile, voice, facts and mandatory question.

[ESTAÇÃO febre-lactente]
[ÁREA] Pediatria
[TEMA] Febre em lactente
[CENÁRIO] Você é o médico ou a médica de uma unidade básica de saúde. Lucas, 2 anos, chega com a mãe por febre.
[TAREFA tarefa-1] Obter a anamnese com a acompanhante.
[TAREFA tarefa-2] Orientar a acompanhante sobre os sinais de alarme.

[ATOR paciente papel=paciente idade=2 voz=infantil] Lucas Souza
[PERFIL] Lucas está no colo da mãe, choroso, e não responde a perguntas.
[TOM] Não fala; apenas chora quando examinado.
[CONTEXTO] Lucas Souza, 2 anos, trazido pela mãe por febre há dois dias.

[ATOR mae papel=acompanhante idade=34 voz=feminina-adulta] Juliana Souza
[PERFIL] Mãe de Lucas, preocupada e colaborativa.
[TOM] Fala de forma direta, com vocabulário simples.

[TÓPICO] HDA — respostas da acompanhante
[FATO febre-inicio ator=mae pep=item-01.criterio-1] A febre começou há dois dias.
[FATO febre-maxima ator=mae pep=item-01.criterio-2 EXPLÍCITO] A maior temperatura medida foi 39 °C.
[FATO choro ator=paciente] Chora ao ser examinado.

[TÓPICO] Dúvidas obrigatórias da acompanhante
[PERGUNTA-OBRIGATÓRIA duvida-mae-01 ator=mae] “Doutor, quando eu devo voltar com ele?”

[ITEM item-01] Anamnese da febre
[CRITÉRIO criterio-1 tipo=PERGUNTA] tempo de febre
[CRITÉRIO criterio-2 tipo=PERGUNTA] temperatura máxima
[NÍVEL adequado pontos=5 mínimo=2] Investiga os dois itens.
[NÍVEL parcialmente_adequado pontos=2,5 mínimo=1] Investiga um item.
[NÍVEL inadequado pontos=0 mínimo=0] Não investiga.

[ITEM item-02] Orientação sobre sinais de alarme
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO perguntas=duvida-mae-01] responde à dúvida da mãe sobre quando retornar
[NÍVEL adequado pontos=5 mínimo=1] Responde à dúvida.
[NÍVEL inadequado pontos=0 mínimo=0] Não responde.
