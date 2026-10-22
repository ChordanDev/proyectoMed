# ESTAÇÃO

[ESTAÇÃO cetoacidose-diabetica-adulto-jovem]
[ÁREA] Clínica Médica
[TEMA] Cetoacidose diabética em adulto jovem
[PROVISÓRIO] sim

# 1. CENÁRIO DE ATUAÇÃO E INSTRUÇÕES AO PARTICIPANTE

[CENÁRIO] Você é o médico ou a médica plantonista de uma Unidade de Pronto Atendimento (UPA 24 horas) do SUS. A unidade tem sala de emergência com monitor cardíaco, oxímetro, glicosímetro, bomba de infusão, laboratório com gasometria e eletrólitos, eletrocardiógrafo e medicamentos de urgência. Há central de regulação para transferência hospitalar, se necessário. Lucas, 22 anos, chega à unidade caminhando com dificuldade, acompanhado de um colega de trabalho que aguarda na recepção, com mal-estar e vômitos.
[TAREFA tarefa-1] Realizar a anamnese dirigida ao quadro atual.
[TAREFA tarefa-2] Solicitar e interpretar o exame físico.
[TAREFA tarefa-3] Solicitar e interpretar os exames complementares pertinentes.
[TAREFA tarefa-4] Formular a hipótese diagnóstica e identificar o fator desencadeante.
[TAREFA tarefa-5] Prescrever o tratamento inicial e a monitorização.
[TAREFA tarefa-6] Orientar o paciente e responder às suas dúvidas.

# 2. ATORES

[ATOR paciente papel=paciente idade=22 voz=masculina-adulta] Lucas Ferreira Andrade
[PERFIL] Homem jovem, magro, abatido, sentado na maca, curvado para a frente, com a mão sobre a barriga. Respira rápido e fundo, parece cansado e um pouco sonolento, mas responde a todas as perguntas. Está assustado e um pouco envergonhado por ter deixado de aplicar a insulina.
[TOM] Fala devagar, com frases curtas, em linguagem simples, compatível com ensino médio completo. Pausa para respirar entre as frases. Não usa termos médicos, exceto "insulina" e "diabetes".
[CONTEXTO] Lucas Ferreira Andrade, 22 anos, auxiliar de almoxarifado, mora com a mãe. Tem diabetes tipo 1 desde os 15 anos e usa insulina NPH e insulina regular. Há três dias começou com diarreia e enjoo depois de uma festa; como não conseguia comer, parou de aplicar toda a insulina há dois dias. Desde ontem tem muita sede, urina muito, vomita tudo o que ingere e sente dor na barriga e falta de ar. Na chegada: PA 98 x 62 mmHg; FC 122 bpm; FR 30 irpm; temperatura axilar 37,4 °C; SatO2 98% em ar ambiente; glicemia capilar 482 mg/dL; peso 60 kg. Queixa principal: "Não paro de vomitar e tô com falta de ar".

# 3. ROTEIRO DO ATOR SIMULADO

[TÓPICO] Identificação e queixa principal
[FATO identificacao ator=paciente] Meu nome é Lucas Ferreira Andrade, tenho 22 anos, trabalho num almoxarifado e moro com a minha mãe.
[FATO queixa-principal ator=paciente] Eu não paro de vomitar, tô com dor na barriga e parece que falta ar.

[TÓPICO] História da doença atual
[FATO inicio-evolucao ator=paciente pep=item-02.criterio-1] Começou há três dias, com diarreia e enjoo depois de uma festa. Desde ontem piorou muito.
[FATO sede-urina ator=paciente pep=item-02.criterio-2] Tô com uma sede que não passa e fazendo xixi toda hora, até de noite.
[FATO vomitos ator=paciente pep=item-02.criterio-3] Vomitei umas seis vezes desde ontem. Tudo o que eu bebo volta. Não teve sangue.
[FATO dor-abdominal ator=paciente pep=item-02.criterio-4] A dor é na barriga toda, tipo um aperto, começou ontem junto com o vômito.
[FATO falta-de-ar ator=paciente] Tô respirando rápido, parece que o ar não enche.
[FATO perda-peso ator=paciente pep=item-02.criterio-5 EXPLÍCITO] Acho que emagreci uns quatro quilos nessa semana, a calça tá larga.
[FATO diarreia-atual ator=paciente] A diarreia já melhorou, ontem foi só uma vez.
[FATO sonolencia ator=paciente EXPLÍCITO] Tô me sentindo meio mole, com sono, desde hoje de manhã.

[TÓPICO] Diabetes e uso de insulina
[FATO tempo-diabetes ator=paciente pep=item-03.criterio-1] Tenho diabetes tipo 1 desde os 15 anos. Uso insulina NPH, 18 unidades de manhã e 10 à noite, e a regular antes das refeições.
[FATO omissao-insulina ator=paciente pep=item-03.criterio-2 EXPLÍCITO] Faz dois dias que eu não aplico nenhuma insulina. Como eu não tava comendo, achei que ia dar hipoglicemia.
[FATO controle-glicemia ator=paciente EXPLÍCITO] Não medi o açúcar esses dias. Meu aparelho tá sem fita.
[FATO internacao-previa ator=paciente EXPLÍCITO] Já internei uma vez, quando descobri o diabetes, com uma coisa parecida.

[TÓPICO] Fatores precipitantes e antecedentes
[FATO sintomas-infecciosos ator=paciente pep=item-03.criterio-3] Não tive febre que eu saiba. Não arde para urinar, não tenho tosse nem catarro, nenhum machucado no corpo.
[FATO alcool-drogas ator=paciente pep=item-03.criterio-4 EXPLÍCITO] Na festa eu bebi umas três latas de cerveja. Não uso droga nenhuma.
[FATO medicamentos-alergias ator=paciente pep=item-03.criterio-5] Só uso as insulinas. Não tenho alergia a remédio.
[FATO outras-doencas ator=paciente EXPLÍCITO] Não tenho outra doença. Não fumo.
[FATO familia ator=paciente EXPLÍCITO] Minha mãe tem pressão alta. Ninguém mais na família tem diabetes.

[REGRA comportamento-exame-fisico] Se o candidato pedir para examinar, Lucas se deita com dificuldade, mantém a respiração rápida e profunda e refere dor leve na barriga toda à palpação, sem defesa. O examinador entrega o impresso de exame físico.
[REGRA comportamento-geral] Lucas responde apenas o que for perguntado. Se o candidato usar termos técnicos, pergunta: "Como assim, doutor?".

[TÓPICO] Dúvidas obrigatórias do paciente
[PERGUNTA-OBRIGATÓRIA duvida-insulina ator=paciente] “Doutor, se eu tô vomitando e sem comer, não é perigoso tomar insulina? Achei que tinha que parar.”
[PERGUNTA-OBRIGATÓRIA duvida-internacao ator=paciente] “Eu vou ter que ficar internado? Não dá para tomar um soro e ir para casa?”

[CONDUTA-ESPERADA resposta-duvida-insulina] O candidato explica, em linguagem simples, que a pessoa com diabetes tipo 1 nunca deve suspender a insulina, mesmo sem comer, porque o corpo continua precisando dela e a falta de insulina causou o quadro atual. Orienta que, em dias de doença, deve medir a glicemia com mais frequência (a cada 3 a 4 horas), manter a insulina basal, ajustar as doses de insulina rápida com a equipe, beber líquidos em pequenos goles, pesquisar cetonas quando possível e procurar atendimento imediato se tiver vômitos persistentes, dor abdominal, falta de ar ou sonolência. Também orienta a buscar fitas de glicemia na UBS.
[CONDUTA-ESPERADA resposta-duvida-internacao] O candidato explica que o quadro é grave (cetoacidose diabética), que precisa de soro e insulina na veia com controle de hora em hora e exames de sangue repetidos, e que por isso ficará na sala de emergência e será internado (com transferência pela regulação para leito hospitalar ou de terapia intensiva, conforme a evolução) até a correção da acidose e a volta para a insulina subcutânea.

# 4. IMPRESSOS DISPONÍVEIS NA ESTAÇÃO

[IMPRESSO impresso-1-exame-fisico categoria=exame-fisico] IMPRESSO 1 — EXAME FÍSICO
[LIBERAÇÃO] exame físico; examinar o paciente; sinais vitais; glicemia capilar; dextro; exame do abdome
[CONTEÚDO]
- **Estado geral:** regular, emagrecido, sonolento porém desperto e orientado; Glasgow 15.
- **Sinais vitais:** PA 98 x 62 mmHg; FC 122 bpm; FR 30 irpm; temperatura axilar 37,4 °C; SatO2 98% em ar ambiente; peso 60 kg.
- **Glicemia capilar:** 482 mg/dL.
- **Hidratação:** mucosas secas, olhos encovados, turgor cutâneo diminuído; tempo de enchimento capilar de 3 segundos.
- **Respiração:** incursões respiratórias rápidas e profundas; hálito com odor adocicado (cetônico).
- **Aparelho respiratório:** murmúrio vesicular presente bilateralmente, sem ruídos adventícios.
- **Aparelho cardiovascular:** ritmo cardíaco regular, taquicárdico, bulhas normofonéticas, sem sopros.
- **Abdome:** plano, ruídos hidroaéreos diminuídos, doloroso difusamente à palpação profunda, sem defesa, sem descompressão dolorosa, sem massas.
- **Pele e extremidades:** sem lesões, sem sinais de infecção em locais de aplicação de insulina; pulsos periféricos finos e simétricos.
- **Neurológico:** sem sinais focais; sem rigidez de nuca.

[IMPRESSO impresso-2-gasometria categoria=laboratorio] IMPRESSO 2 — GASOMETRIA VENOSA
[LIBERAÇÃO] gasometria; gasometria venosa; gasometria arterial; pH; bicarbonato; lactato
[CONTEÚDO]
**Gasometria venosa**
- **pH:** 7,12 (referência venosa: 7,32 a 7,42)
- **pCO2:** 22 mmHg (referência venosa: 41 a 51 mmHg)
- **Bicarbonato (HCO3):** 8 mEq/L (referência: 22 a 26 mEq/L)
- **Excesso de bases (BE):** −20 mEq/L (referência: −2 a +2 mEq/L)
- **Lactato:** 1,8 mmol/L (referência: menor que 2,0 mmol/L)

[IMPRESSO impresso-3-bioquimica categoria=laboratorio] IMPRESSO 3 — GLICEMIA, ELETRÓLITOS E FUNÇÃO RENAL
[LIBERAÇÃO] glicemia; glicose sérica; eletrólitos; sódio; potássio; cloro; ureia; creatinina; função renal; magnésio; fósforo
[CONTEÚDO]
- **Glicose:** 486 mg/dL (referência: 70 a 99 mg/dL)
- **Sódio:** 131 mEq/L (referência: 135 a 145 mEq/L)
- **Potássio:** 4,8 mEq/L (referência: 3,5 a 5,0 mEq/L)
- **Cloro:** 99 mEq/L (referência: 98 a 107 mEq/L)
- **Ureia:** 62 mg/dL (referência: 15 a 40 mg/dL)
- **Creatinina:** 1,5 mg/dL (referência: 0,7 a 1,3 mg/dL)
- **Magnésio:** 2,0 mg/dL (referência: 1,6 a 2,6 mg/dL)
- **Fósforo:** 3,2 mg/dL (referência: 2,5 a 4,5 mg/dL)

[IMPRESSO impresso-4-cetonas-urina categoria=laboratorio] IMPRESSO 4 — CETONEMIA E URINA TIPO 1
[LIBERAÇÃO] cetonemia; beta-hidroxibutirato; corpos cetônicos; cetonúria; urina tipo 1; EAS; exame de urina; sumário de urina
[CONTEÚDO]
**Cetonemia**
- **Beta-hidroxibutirato sérico:** 5,6 mmol/L (referência: menor que 0,6 mmol/L)

**Urina tipo 1 (EAS)**
- **Densidade:** 1.030 (referência: 1.005 a 1.030)
- **pH:** 5,0 (referência: 5,0 a 7,0)
- **Glicose:** ++++ (referência: ausente)
- **Corpos cetônicos:** +++ (referência: ausentes)
- **Proteínas:** traços (referência: ausentes)
- **Nitrito:** negativo (referência: negativo)
- **Leucócitos:** 3 por campo (referência: até 5 por campo)
- **Hemácias:** 1 por campo (referência: até 3 por campo)

[IMPRESSO impresso-5-hemograma categoria=laboratorio] IMPRESSO 5 — HEMOGRAMA E PROTEÍNA C REATIVA
[LIBERAÇÃO] hemograma; hemograma completo; leucograma; PCR; proteína C reativa
[CONTEÚDO]
- **Hemoglobina:** 15,8 g/dL (referência: 13,5 a 17,5 g/dL)
- **Hematócrito:** 47% (referência: 40% a 52%)
- **Leucócitos:** 16.200/mm³ (referência: 4.000 a 11.000/mm³)
- **Segmentados:** 80% (referência: 40% a 75%)
- **Bastonetes:** 2% (referência: 0% a 5%)
- **Linfócitos:** 14% (referência: 20% a 45%)
- **Plaquetas:** 290.000/mm³ (referência: 150.000 a 450.000/mm³)
- **Proteína C reativa:** 12 mg/L (referência: menor que 5 mg/L)

[IMPRESSO impresso-6-ecg categoria=imagem] IMPRESSO 6 — ELETROCARDIOGRAMA
[LIBERAÇÃO] eletrocardiograma; ECG; eletro
[CONTEÚDO]
- **Ritmo:** sinusal.
- **Frequência cardíaca:** 120 bpm.
- **Intervalo PR:** 0,14 s; **QRS:** 0,08 s; **QTc:** 420 ms.
- **Onda T:** morfologia normal, sem apiculamento; sem ondas U.
- **Segmento ST:** sem alterações.
- **Conclusão:** taquicardia sinusal, sem sinais eletrocardiográficos de distúrbio do potássio.

# 5. PADRÃO ESPERADO DE PROCEDIMENTO (PEP)

[ITEM item-01] Apresentação e identificação
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Apresenta-se ao paciente
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] confirma o nome e a idade do paciente
[NÍVEL adequado pontos=0,25 mínimo=2] Realiza as duas ações.
[NÍVEL parcialmente_adequado pontos=0,125 mínimo=1] Realiza uma ação.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma ação.

[ITEM item-02] Anamnese do quadro atual
[CRITÉRIO criterio-1 tipo=PERGUNTA] Pergunta o início e a evolução dos sintomas
[CRITÉRIO criterio-2 tipo=PERGUNTA] pergunta sobre sede excessiva e aumento do volume urinário
[CRITÉRIO criterio-3 tipo=PERGUNTA] pergunta sobre náuseas e vômitos (frequência e aceitação de líquidos)
[CRITÉRIO criterio-4 tipo=PERGUNTA] pergunta sobre dor abdominal (localização e início)
[CRITÉRIO criterio-5 tipo=PERGUNTA] pergunta sobre perda de peso
[NÍVEL adequado pontos=1,0 mínimo=4] Investiga quatro ou cinco itens.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Investiga dois ou três itens.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga um item ou nenhum.

[ITEM item-03] Investigação do diabetes e dos fatores precipitantes
[CRITÉRIO criterio-1 tipo=PERGUNTA] Pergunta o tempo de diagnóstico do diabetes e o esquema de insulina em uso
[CRITÉRIO criterio-2 tipo=PERGUNTA] pergunta sobre omissão ou uso irregular da insulina nos últimos dias
[CRITÉRIO criterio-3 tipo=PERGUNTA] pergunta sobre sinais de infecção (febre, sintomas urinários, respiratórios ou de pele)
[CRITÉRIO criterio-4 tipo=PERGUNTA] pergunta sobre uso de álcool ou drogas
[CRITÉRIO criterio-5 tipo=PERGUNTA] pergunta sobre outros medicamentos e alergias
[NÍVEL adequado pontos=1,0 mínimo=4] Investiga quatro ou cinco itens.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Investiga dois ou três itens.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga um item ou nenhum.

[ITEM item-04] Exame físico
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-1-exame-fisico] Solicita o exame físico com sinais vitais e glicemia capilar
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] identifica desidratação e respiração de Kussmaul (ou hálito cetônico)
[NÍVEL adequado pontos=0,75 mínimo=2] Realiza as duas ações.
[NÍVEL parcialmente_adequado pontos=0,375 mínimo=1] Realiza uma ação.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma ação.

[ITEM item-05] Solicitação de exames complementares
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-2-gasometria] Solicita gasometria (venosa ou arterial)
[CRITÉRIO criterio-2 tipo=SOLICITAÇÃO impressos=impresso-3-bioquimica] solicita glicemia sérica, eletrólitos (sódio, potássio, cloro) e função renal
[CRITÉRIO criterio-3 tipo=SOLICITAÇÃO impressos=impresso-4-cetonas-urina] solicita cetonemia ou pesquisa de cetonas na urina
[CRITÉRIO criterio-4 tipo=SOLICITAÇÃO impressos=impresso-6-ecg] solicita eletrocardiograma
[NÍVEL adequado pontos=1,0 mínimo=4] Solicita os quatro exames.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Solicita dois ou três exames.
[NÍVEL inadequado pontos=0 mínimo=0] Solicita um exame ou nenhum.

[ITEM item-06] Diagnóstico e fator desencadeante
[CRITÉRIO criterio-1 tipo=VERBALIZAÇÃO após=impresso-2-gasometria,impresso-3-bioquimica OBRIGATÓRIO] Formula o diagnóstico de cetoacidose diabética (hiperglicemia, acidose metabólica e cetose)
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-2-gasometria,impresso-3-bioquimica] calcula o ânion gap e o identifica como elevado (cerca de 24 mEq/L)
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-3-bioquimica] calcula ou interpreta o sódio corrigido pela glicemia (cerca de 137 mEq/L) e reconhece o potássio sérico normal (4,8 mEq/L)
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] identifica como fator desencadeante a suspensão da insulina durante quadro de gastroenterite
[NÍVEL adequado pontos=1,5 mínimo=4] Realiza as quatro ações, incluindo obrigatoriamente o diagnóstico de cetoacidose diabética.
[NÍVEL parcialmente_adequado pontos=0,75 mínimo=2] Realiza duas ou três ações, incluindo obrigatoriamente o diagnóstico de cetoacidose diabética.
[NÍVEL inadequado pontos=0 mínimo=0] Não formula o diagnóstico de cetoacidose diabética ou realiza apenas uma ação.

[ITEM item-07] Reposição volêmica
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Prescreve soro fisiológico (NaCl 0,9%) 15 a 20 mL/kg (1.000 a 1.500 mL) por via intravenosa na primeira hora
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] indica a hidratação de manutenção guiada pelo sódio corrigido (sódio corrigido normal: NaCl 0,45% 250 a 500 mL/h, conforme estado volêmico e diurese)
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] indica acesso venoso calibroso, monitorização cardíaca contínua e controle de diurese
[NÍVEL adequado pontos=1,25 mínimo=3] Realiza as três ações.
[NÍVEL parcialmente_adequado pontos=0,625 mínimo=1] Realiza uma ou duas ações, sendo uma delas a expansão inicial com soro fisiológico.
[NÍVEL inadequado pontos=0 mínimo=0] Não prescreve reposição volêmica.

[ITEM item-08] Potássio, insulinoterapia e bicarbonato
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Verbaliza que confirma potássio sérico de pelo menos 3,3 mEq/L antes de iniciar a insulina
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] prescreve reposição de cloreto de potássio 20 a 30 mEq em cada litro de soro, com alvo de potássio entre 4 e 5 mEq/L
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO OBRIGATÓRIO] prescreve insulina regular intravenosa em bomba de infusão: 0,1 U/kg em bolus (6 U) seguida de 0,1 U/kg/h (6 U/h), ou 0,14 U/kg/h (8 a 9 U/h) sem bolus
[CRITÉRIO bicarbonato-sem-indicacao tipo=COMUNICAÇÃO PROIBIDO] prescreve bicarbonato de sódio (pH 7,12, acima de 6,9, sem indicação)
[NÍVEL adequado pontos=1,75 mínimo=3] Realiza as três ações, incluindo obrigatoriamente a insulinoterapia intravenosa correta, sem prescrever bicarbonato.
[NÍVEL parcialmente_adequado pontos=0,875 mínimo=2] Realiza duas ações, incluindo obrigatoriamente a insulinoterapia intravenosa correta, sem prescrever bicarbonato.
[NÍVEL inadequado pontos=0 mínimo=0] Não prescreve insulina intravenosa corretamente ou prescreve bicarbonato de sódio.

[ITEM item-09] Monitorização e critérios de resolução
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Indica glicemia capilar de hora em hora
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] indica eletrólitos e gasometria venosa a cada 2 a 4 horas
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] indica acrescentar soro glicosado 5% quando a glicemia chegar a 200 a 250 mg/dL, reduzindo a insulina para 0,02 a 0,05 U/kg/h
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] cita os critérios de resolução (glicemia abaixo de 200 mg/dL com pelo menos dois de: bicarbonato de 15 mEq/L ou mais, pH venoso acima de 7,3, ânion gap de 12 mEq/L ou menos) e a transição para insulina subcutânea, com insulina basal aplicada cerca de 2 horas antes de suspender a infusão
[NÍVEL adequado pontos=0,75 mínimo=4] Realiza as quatro ações.
[NÍVEL parcialmente_adequado pontos=0,375 mínimo=2] Realiza duas ou três ações.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza uma ação ou nenhuma.

[ITEM item-10] Orientação ao paciente e resposta às dúvidas
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO perguntas=duvida-insulina] Explica que a insulina não deve ser suspensa mesmo sem alimentação e orienta os cuidados nos dias de doença (glicemia frequente, manter a insulina basal, hidratação)
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO perguntas=duvida-internacao] explica a gravidade do quadro e a necessidade de permanecer na emergência e de internação
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] orienta sinais de alarme para procurar atendimento (vômitos persistentes, dor abdominal, falta de ar, sonolência) e o acompanhamento na UBS com acesso às fitas de glicemia
[NÍVEL adequado pontos=0,75 mínimo=3] Realiza as três orientações.
[NÍVEL parcialmente_adequado pontos=0,375 mínimo=1] Realiza uma ou duas orientações.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma orientação.
