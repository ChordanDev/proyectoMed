# ESTAÇÃO

[ESTAÇÃO bronquiolite-viral-lactente]
[ÁREA] Pediatria
[TEMA] Bronquiolite viral aguda em lactente, atendida com a mãe como acompanhante
[PROVISÓRIO] sim

# 1. CENÁRIO DE ATUAÇÃO E INSTRUÇÕES AO PARTICIPANTE

[CENÁRIO] Você é o médico ou a médica plantonista de uma Unidade de Pronto Atendimento (UPA 24 horas). A unidade dispõe de sala de emergência pediátrica, oxigênio, oxímetro de pulso, laboratório e radiologia básicos. Há leitos pediátricos de referência no hospital municipal, com transporte sanitário disponível. Helena, uma lactente de 4 meses, é trazida pela mãe por tosse e "cansaço".
[TAREFA tarefa-1] Realizar a anamnese dirigida com a acompanhante.
[TAREFA tarefa-2] Solicitar e interpretar o exame físico e os exames que julgar necessários.
[TAREFA tarefa-3] Formular a hipótese diagnóstica e classificar a gravidade do quadro.
[TAREFA tarefa-4] Definir e explicar a conduta à acompanhante.
[TAREFA tarefa-5] Responder às dúvidas da acompanhante e fazer as orientações pertinentes.

# 2. ATORES

[ATOR paciente papel=paciente idade=0 voz=infantil] Helena Souza Prado
[PERFIL] Lactente de 4 meses, no colo da mãe, acordada, com respiração rápida e esforço visível para respirar, nariz com muita secreção. Choraminga de vez em quando e se acalma no colo. Não responde a perguntas.
[TOM] Não fala. Faz choro fraco e entrecortado quando é manipulada.
[CONTEXTO] Helena Souza Prado, 4 meses, sexo feminino, peso de 6,2 kg, trazida pela mãe à UPA por tosse e cansaço que pioraram hoje. Sinais vitais da triagem: temperatura axilar 38,1 °C; FC 168 bpm; FR 64 irpm; SpO2 89% em ar ambiente. A classificação de risco foi amarela, e a criança foi encaminhada ao consultório pediátrico.

[ATOR mae papel=acompanhante idade=24 voz=feminina-adulta] Juliana Souza Prado
[PERFIL] Mãe de Helena, ansiosa e cansada porque dormiu pouco na última noite. É colaborativa e acaricia a filha o tempo todo. Fica mais aflita se ouvir a palavra "internar" sem explicação.
[TOM] Fala de forma simples, com frases curtas. Estudou até o primeiro ano do ensino médio e usa termos como "chiado", "cansaço" e "puxando o ar".

# 3. ROTEIRO DO ATOR SIMULADO

[TÓPICO] Queixa principal e história da doença atual (respostas da mãe)
[FATO queixa-principal ator=mae] Doutor, ela está com uma tosse que não para e hoje começou a ficar cansadinha, puxando o ar.
[FATO inicio-coriza ator=mae pep=item-02.criterio-1] Começou há quatro dias, com nariz escorrendo e espirro, igual a um resfriado.
[FATO evolucao-tosse ator=mae pep=item-02.criterio-1] Há uns dois dias começou a tosse, e de ontem para hoje ela ficou cansada.
[FATO febre ator=mae pep=item-02.criterio-2] Teve febre baixa, de 37,8 a 38 graus, desde o começo. Eu dei paracetamol e baixou.
[FATO chiado ator=mae pep=item-02.criterio-3] Dá para ouvir um chiado no peito, e a barriguinha dela afunda quando respira.
[FATO alimentacao ator=mae pep=item-02.criterio-4] Ela mama só no peito. Hoje pega o peito, mama um pouquinho, cansa e solta. Está mamando menos da metade do normal.
[FATO vomito-tosse ator=mae] Às vezes engasga com a tosse e põe um pouco de leite para fora.
[FATO diurese ator=mae pep=item-02.criterio-5 EXPLÍCITO] Hoje troquei só três fraldas molhadas. Normalmente são umas seis ou sete.
[FATO apneia ator=mae pep=item-02.criterio-6 EXPLÍCITO] Não, ela não parou de respirar nenhuma vez.
[FATO cianose ator=mae pep=item-02.criterio-6 EXPLÍCITO] Não vi a boca roxa, não.
[FATO sono ator=mae] Ela acorda muito à noite tossindo e chorando.
[FATO medicacao-em-casa ator=mae] Só dei paracetamol e soro no nariz uma vez. Não dei xarope.

[TÓPICO] Antecedentes e fatores de risco (respostas da mãe)
[FATO gestacao-parto ator=mae pep=item-03.criterio-1] Ela nasceu de parto normal, com 39 semanas, e pesou 3 quilos e 200. Não precisou ficar internada.
[FATO comorbidades ator=mae pep=item-03.criterio-2] Ela não tem problema no coração nem no pulmão. Nunca tinha chiado antes.
[FATO internacoes ator=mae pep=item-03.criterio-2] Nunca ficou internada.
[FATO vacinacao ator=mae pep=item-03.criterio-3] As vacinas estão em dia. Tomou as de 2 e de 4 meses, a última na semana passada.
[FATO contato-irmao ator=mae pep=item-03.criterio-4] O irmão dela, de 3 anos, vai à creche e estava resfriado na semana passada.
[FATO tabagismo ator=mae pep=item-03.criterio-4 EXPLÍCITO] O pai dela fuma. Às vezes fuma dentro de casa, na cozinha.
[FATO alergias ator=mae] Que eu saiba, ela não tem alergia a remédio.
[FATO desenvolvimento ator=mae] Ela está crescendo bem e já sustenta a cabecinha.

[TÓPICO] Comportamento da paciente
[FATO choro-exame ator=paciente] Chora de forma fraca e entrecortada quando é colocada na maca e se acalma no colo da mãe.

[REGRA comportamento-no-exame] Se o candidato pedir para examinar a criança, a mãe a coloca na maca, ajuda a segurá-la e pergunta, preocupada, se "é grave". Os achados do exame físico só são informados pelo impresso correspondente.
[REGRA reacao-internacao] Se o candidato indicar internação sem explicar o motivo, a mãe pergunta: "Mas por que tem que internar, doutor?". Se a explicação for clara, ela aceita e fica mais tranquila.
[REGRA exames-nao-solicitados] Se o candidato não solicitar radiografia ou exames laboratoriais, o examinador não os oferece. Se o candidato solicitar, o examinador entrega o impresso correspondente.

[TÓPICO] Dúvidas obrigatórias da mãe (nos minutos finais)
[PERGUNTA-OBRIGATÓRIA duvida-mae-inalacao ator=mae] “Doutor, ela não vai precisar de uma inalação com remédio, de xarope ou de antibiótico para sarar mais rápido?”
[PERGUNTA-OBRIGATÓRIA duvida-mae-asma ator=mae] “Esse chiado quer dizer que ela vai ficar com asma pelo resto da vida?”

[CONDUTA-ESPERADA resposta-duvida-inalacao] O candidato explica que a bronquiolite é causada por vírus, na maioria das vezes pelo vírus sincicial respiratório. Antibiótico não trata vírus e não está indicado, porque não há sinais de infecção bacteriana. Corticoide, xaropes para tosse e inalação com broncodilatador ou com outros remédios não aceleram a melhora e não são recomendados de rotina pela Sociedade Brasileira de Pediatria. O tratamento é de suporte: oxigênio, lavagem e aspiração do nariz, hidratação e alimentação.
[CONDUTA-ESPERADA resposta-duvida-asma] O candidato explica que ter bronquiolite não significa ter asma. Algumas crianças podem apresentar novos episódios de chiado nos meses ou anos seguintes, sobretudo se expostas à fumaça de cigarro. O acompanhamento na unidade básica de saúde vai avaliar essa evolução. Evitar a exposição ao fumo ajuda a proteger o pulmão da criança.
[CONDUTA-ESPERADA conduta-geral] O examinador espera o diagnóstico clínico de bronquiolite viral aguda com sinais de gravidade e indicação de internação hospitalar. Os sinais de gravidade são SpO2 de 89% em ar ambiente, taquipneia (FR de 64 irpm), tiragem subcostal e intercostal, batimento de asa nasal e aceitação alimentar menor que 50% do habitual, com redução da diurese. O candidato deve prescrever oxigênio por cateter nasal para manter SpO2 ≥ 92%, lavagem nasal com soro fisiológico 0,9% e aspiração das vias aéreas superiores e manutenção da hidratação. A alimentação deve ser fracionada. Se a FR permanecer acima de 60 a 70 irpm ou a aceitação seguir insuficiente, indica-se sonda nasogástrica ou hidratação venosa. O antitérmico é prescrito por peso. Exames complementares não são necessários de rotina.

# 4. IMPRESSOS DISPONÍVEIS NA ESTAÇÃO

[IMPRESSO impresso-1-exame-geral categoria=exame-fisico] IMPRESSO 1 — EXAME FÍSICO GERAL E SINAIS VITAIS
[LIBERAÇÃO] exame físico; exame físico geral; examinar a criança; sinais vitais; ectoscopia; estado geral; hidratação; peso
[CONTEÚDO]
- **Peso:** 6,2 kg (adequado para a idade).
- **Sinais vitais:** temperatura axilar 38,1 °C; FC 168 bpm; FR 64 irpm.
- **Estado geral:** regular, acordada e reativa ao manuseio, com aspecto cansado; acalma-se no colo.
- **Hidratação:** mucosas levemente secas; fontanela anterior normotensa; tempo de enchimento capilar de 2 segundos; lágrimas presentes ao choro.
- **Pele:** corada, sem cianose central ou periférica.
- **Nariz e orofaringe:** coriza hialina abundante; orofaringe levemente hiperemiada, sem exsudato.
- **Otoscopia:** membranas timpânicas íntegras e sem abaulamento.
- **Cardiovascular:** ritmo cardíaco regular em dois tempos, bulhas normofonéticas, sem sopros; pulsos periféricos cheios.
- **Abdome:** flácido, sem visceromegalias; fígado palpável a 1 cm do rebordo costal direito.

[IMPRESSO impresso-2-exame-respiratorio categoria=exame-fisico] IMPRESSO 2 — EXAME DO APARELHO RESPIRATÓRIO
[LIBERAÇÃO] exame do aparelho respiratório; ausculta pulmonar; exame respiratório; exame do tórax; inspeção do tórax; padrão respiratório
[CONTEÚDO]
- **Inspeção:** taquipneia; batimento de asa nasal; tiragem subcostal e intercostal moderada; sem gemência e sem retração de fúrcula.
- **Expansibilidade:** simétrica.
- **Percussão:** som claro pulmonar, levemente hipersonoro bilateralmente.
- **Ausculta:** murmúrio vesicular presente bilateralmente, com tempo expiratório prolongado, sibilos expiratórios difusos e crepitações finas em ambas as bases.

[IMPRESSO impresso-3-oximetria categoria=exame-fisico] IMPRESSO 3 — OXIMETRIA DE PULSO
[LIBERAÇÃO] oximetria de pulso; oximetria; saturação de oxigênio; saturação; SpO2; oxímetro
[CONTEÚDO]
- **SpO2 em ar ambiente:** 89%, medida com a criança calma, com boa curva de pulso.
- **Valor de referência:** SpO2 ≥ 95% em ar ambiente.

[IMPRESSO impresso-4-radiografia categoria=imagem] IMPRESSO 4 — RADIOGRAFIA DE TÓRAX
[LIBERAÇÃO] radiografia de tórax; raio X de tórax; RX de tórax; raio X; radiografia
[CONTEÚDO]
- **Incidência:** anteroposterior, com a criança em decúbito; técnica adequada.
- **Laudo:** hiperinsuflação pulmonar bilateral com retificação das cúpulas diafragmáticas; espessamento peribrônquico difuso; pequena atelectasia laminar no lobo superior direito; sem consolidação e sem derrame pleural. Área cardíaca normal.
- **Impressão:** achados compatíveis com doença inflamatória de pequenas vias aéreas.

[IMPRESSO impresso-5-hemograma-pcr categoria=laboratorio] IMPRESSO 5 — HEMOGRAMA E PROTEÍNA C REATIVA
[LIBERAÇÃO] hemograma; hemograma completo; PCR; proteína C reativa; exames de sangue; exames laboratoriais
[CONTEÚDO]
- **Hemoglobina:** 11,2 g/dL (VR: 9,5 a 13,5 g/dL)
- **Hematócrito:** 33% (VR: 29% a 41%)
- **Leucócitos:** 10.800/mm³ (VR: 6.000 a 17.500/mm³)
- **Neutrófilos:** 30% — 3.240/mm³ (VR: 1.000 a 8.500/mm³)
- **Linfócitos:** 62% — 6.696/mm³ (VR: 4.000 a 13.500/mm³)
- **Monócitos:** 7% (VR: 2% a 10%)
- **Eosinófilos:** 1% (VR: 0% a 5%)
- **Plaquetas:** 385.000/mm³ (VR: 150.000 a 450.000/mm³)
- **Proteína C reativa:** 4 mg/L (VR: < 10 mg/L)

[IMPRESSO impresso-6-pesquisa-viral categoria=laboratorio] IMPRESSO 6 — PESQUISA DE VÍRUS RESPIRATÓRIOS EM SECREÇÃO NASOFARÍNGEA
[LIBERAÇÃO] pesquisa de vírus respiratórios; painel viral; pesquisa de vírus sincicial respiratório; pesquisa de VSR; swab nasal; aspirado nasofaríngeo; teste rápido para VSR
[CONTEÚDO]
- **Vírus sincicial respiratório (teste rápido de antígeno):** detectado (VR: não detectado)
- **Influenza A e B (teste rápido de antígeno):** não detectado (VR: não detectado)
- **SARS-CoV-2 (teste rápido de antígeno):** não detectado (VR: não detectado)

# 5. PADRÃO ESPERADO DE PROCEDIMENTO (PEP)

[ITEM item-01] Apresentação e identificação
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Apresenta-se à acompanhante com nome e função
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] Identifica a criança e a acompanhante pelo nome e confirma o vínculo
[NÍVEL adequado pontos=0,5 mínimo=2] Realiza as duas ações.
[NÍVEL parcialmente_adequado pontos=0,25 mínimo=1] Realiza uma ação.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma ação.

[ITEM item-02] Anamnese da doença atual
[CRITÉRIO criterio-1 tipo=PERGUNTA] Pergunta o início e a evolução dos sintomas (pródromo de coriza seguido de tosse e cansaço)
[CRITÉRIO criterio-2 tipo=PERGUNTA] Pergunta sobre febre
[CRITÉRIO criterio-3 tipo=PERGUNTA] Pergunta sobre chiado ou dificuldade para respirar
[CRITÉRIO criterio-4 tipo=PERGUNTA] Pergunta sobre a aceitação alimentar (mamadas)
[CRITÉRIO criterio-5 tipo=PERGUNTA] Pergunta sobre a diurese (número de fraldas molhadas)
[CRITÉRIO criterio-6 tipo=PERGUNTA] Pergunta sobre pausas respiratórias (apneia) ou cianose
[NÍVEL adequado pontos=1,5 mínimo=5] Investiga cinco ou seis itens.
[NÍVEL parcialmente_adequado pontos=0,75 mínimo=3] Investiga três ou quatro itens.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga dois itens ou menos.

[ITEM item-03] Antecedentes e fatores de risco
[CRITÉRIO criterio-1 tipo=PERGUNTA] Pergunta sobre idade gestacional ao nascer e intercorrências neonatais (prematuridade)
[CRITÉRIO criterio-2 tipo=PERGUNTA] Pergunta sobre doença cardíaca ou pulmonar prévia, episódios anteriores de chiado ou internações
[CRITÉRIO criterio-3 tipo=PERGUNTA] Pergunta sobre a situação vacinal
[CRITÉRIO criterio-4 tipo=PERGUNTA] Pergunta sobre contato com pessoas doentes ou frequência à creche e sobre exposição à fumaça de cigarro
[NÍVEL adequado pontos=1,0 mínimo=4] Investiga os quatro itens.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Investiga dois ou três itens.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga um item ou nenhum.

[ITEM item-04] Solicitação do exame físico
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-1-exame-geral] Solicita o exame físico geral com sinais vitais
[CRITÉRIO criterio-2 tipo=SOLICITAÇÃO impressos=impresso-2-exame-respiratorio] Solicita o exame do aparelho respiratório
[CRITÉRIO criterio-3 tipo=SOLICITAÇÃO impressos=impresso-3-oximetria] Solicita a oximetria de pulso
[NÍVEL adequado pontos=0,75 mínimo=3] Solicita os três exames.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Solicita dois exames.
[NÍVEL inadequado pontos=0 mínimo=0] Solicita um exame ou nenhum.

[ITEM item-05] Interpretação dos achados clínicos
[CRITÉRIO criterio-1 tipo=VERBALIZAÇÃO após=impresso-1-exame-geral,impresso-2-exame-respiratorio] Verbaliza desconforto respiratório: taquipneia, tiragem subcostal e intercostal e batimento de asa nasal, com sibilos e crepitações difusos
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-3-oximetria] Verbaliza hipoxemia (SpO2 de 89% em ar ambiente)
[NÍVEL adequado pontos=1,0 mínimo=2] Verbaliza os dois achados.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=1] Verbaliza um achado.
[NÍVEL inadequado pontos=0 mínimo=0] Não verbaliza nenhum achado.

[ITEM item-06] Hipótese diagnóstica e classificação de gravidade
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] Formula a hipótese de bronquiolite viral aguda
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] Classifica o quadro como moderado a grave, com critérios de internação: hipoxemia, desconforto respiratório e aceitação alimentar menor que 50%
[NÍVEL adequado pontos=1,5 mínimo=2] Formula a hipótese e classifica a gravidade com os critérios.
[NÍVEL parcialmente_adequado pontos=0,75 mínimo=1] Formula a hipótese de bronquiolite viral aguda sem classificar a gravidade.
[NÍVEL inadequado pontos=0 mínimo=0] Não formula a hipótese de bronquiolite viral aguda.

[ITEM item-07] Conduta terapêutica
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] Indica internação hospitalar e explica o motivo à mãe
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] Prescreve oxigênio suplementar por cateter nasal para manter SpO2 ≥ 92%
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] Prescreve lavagem nasal com soro fisiológico 0,9% e aspiração das vias aéreas superiores, sobretudo antes das mamadas
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] Orienta hidratação e alimentação: mamadas fracionadas e sonda nasogástrica ou hidratação venosa se FR > 60 a 70 irpm ou aceitação insuficiente
[CRITÉRIO criterio-5 tipo=COMUNICAÇÃO] Prescreve antitérmico por peso: paracetamol 200 mg/mL, 6 gotas (cerca de 10 mg/kg) por via oral a cada 6 horas se temperatura ≥ 37,8 °C, enquanto houver febre
[CRITÉRIO corticoide-antibiotico tipo=COMUNICAÇÃO PROIBIDO] Prescreve corticoide sistêmico ou antibiótico
[NÍVEL adequado pontos=2,0 mínimo=4] Indica a internação e realiza pelo menos mais três medidas.
[NÍVEL parcialmente_adequado pontos=1,0 mínimo=2] Indica a internação e realiza mais uma ou duas medidas.
[NÍVEL inadequado pontos=0 mínimo=0] Não indica internação, realiza menos de duas medidas ou prescreve corticoide sistêmico ou antibiótico.

[ITEM item-08] Resposta às dúvidas da mãe
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO perguntas=duvida-mae-inalacao] Explica que antibiótico, corticoide, xarope e inalação com broncodilatador não são indicados de rotina porque a doença é viral e o tratamento é de suporte
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO perguntas=duvida-mae-asma] Explica que bronquiolite não é sinônimo de asma, que pode haver novos episódios de chiado e que a criança será acompanhada
[NÍVEL adequado pontos=1,0 mínimo=2] Responde adequadamente às duas dúvidas.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=1] Responde adequadamente a uma dúvida.
[NÍVEL inadequado pontos=0 mínimo=0] Não responde adequadamente a nenhuma dúvida.

[ITEM item-09] Orientações e prevenção
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Explica a doença em linguagem acessível: causa viral, piora entre o terceiro e o quinto dia e tosse que pode durar de 2 a 3 semanas
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] Orienta a lavagem das mãos, o afastamento de pessoas resfriadas e a suspensão da exposição à fumaça de cigarro
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] Orienta a manutenção do aleitamento materno
[NÍVEL adequado pontos=0,75 mínimo=3] Realiza as três orientações.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Realiza duas orientações.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza uma orientação ou nenhuma.
