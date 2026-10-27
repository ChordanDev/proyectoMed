# ESTAÇÃO

[ESTAÇÃO cetoacidose-diabetica-adulto-jovem]
[ÁREA] Clínica Médica
[TEMA] Cetoacidose diabética em adulto jovem
[PROVISÓRIO] sim

# 1. CENÁRIO DE ATUAÇÃO E INSTRUÇÕES AO PARTICIPANTE

[CENÁRIO] Você é o médico ou a médica plantonista do pronto-socorro de um hospital geral de médio porte do SUS. A sala de emergência dispõe de materiais para o exame físico (estetoscópio, esfigmomanômetro, oxímetro de pulso, termômetro, glicosímetro e lancetas), monitor multiparamétrico, bombas de infusão, acesso venoso periférico e soluções cristaloides. O laboratório realiza em regime de urgência gasometria arterial e venosa, eletrólitos, ureia, creatinina, glicose plasmática, beta-hidroxibutirato sérico, urina tipo 1, hemograma e proteína C-reativa. Há eletrocardiógrafo e radiografia de tórax. O hospital tem Unidade de Terapia Intensiva (UTI) com leito disponível. Gabriel Antunes Moreira, 22 anos, sexo masculino, estudante universitário de Educação Física, procura o serviço por vômitos, dor abdominal e falta de ar há dois dias. Sinais vitais da triagem: PA 96 x 58 mmHg; FC 124 bpm; FR 30 irpm; temperatura axilar 37,4 °C; SpO2 98% em ar ambiente; peso referido de 68 kg.
[TAREFA tarefa-1] Realizar a anamnese dirigida, incluindo a investigação do fator desencadeante.
[TAREFA tarefa-2] Solicitar e interpretar o exame físico.
[TAREFA tarefa-3] Solicitar e interpretar os exames complementares pertinentes.
[TAREFA tarefa-4] Formular a hipótese diagnóstica com a classificação de gravidade.
[TAREFA tarefa-5] Prescrever a conduta inicial, a monitorização e o destino do paciente.
[TAREFA tarefa-6] Orientar o paciente e responder às suas dúvidas.

# 2. ATORES

[ATOR paciente papel=paciente idade=22 voz=masculina-adulta] Gabriel Antunes Moreira
[PERFIL] Jovem de 22 anos, magro, abatido, sentado na maca inclinado para a frente, com respiração rápida e profunda. Lábios ressecados, pede água várias vezes. Dor abdominal moderada (nota 6 em 10), difusa. Mora em república estudantil, longe dos pais, solteiro, cursa o terceiro ano de Educação Física com bolsa. Envergonhado por ter parado a insulina; fica defensivo se o médico o julgar.
[TOM] Fala frases curtas, interrompidas pela respiração ofegante; linguagem informal de universitário, sem termos técnicos, embora conheça palavras como "insulina" e "glicemia".
[CONTEXTO] Gabriel tem diabetes tipo 1 desde os 14 anos. Há três dias teve diarreia e vômitos depois de comer em uma lanchonete; há dois dias deixou de aplicar toda a insulina porque não conseguia comer e teve medo de hipoglicemia. Desde então, sede intensa, urina muito, vômitos repetidos, dor na barriga e falta de ar. Sinais vitais da chegada: PA 96 x 58 mmHg; FC 124 bpm; FR 30 irpm; temperatura axilar 37,4 °C; SpO2 98%; peso 68 kg.

# 3. ROTEIRO DO ATOR SIMULADO

[TÓPICO] História da doença atual
[FATO sede-urina ator=paciente pep=item-02.criterio-1] Estou com uma sede que não passa e fazendo xixi toda hora, até de madrugada levantei umas cinco vezes.
[FATO perda-peso ator=paciente pep=item-02.criterio-2] Acho que emagreci; eu pesava 72 quilos semana passada e hoje na balança deu 68.
[FATO vomitos ator=paciente pep=item-02.criterio-3] Vomitei umas oito vezes desde ontem, tudo que eu bebo volta. Não tem sangue no vômito.
[FATO dor-abdominal ator=paciente pep=item-02.criterio-4] A dor é na barriga toda, tipo um aperto, começou ontem e não vai para lugar nenhum.
[FATO falta-ar ator=paciente pep=item-02.criterio-5] Estou puxando o ar fundo, parece que o ar não chega. Estou muito cansado e com sono.
[FATO gastroenterite ator=paciente pep=item-03.criterio-2] Há três dias comi um pastel numa lanchonete e tive diarreia líquida, umas seis vezes no dia, e uma febrinha de 37,8 °C. A diarreia melhorou ontem.
[FATO suspensao-insulina ator=paciente pep=item-03.criterio-1 EXPLÍCITO] Faz dois dias que eu não aplico nenhuma insulina, nem a NPH. Como eu não estava comendo, achei que ia ter hipoglicemia.
[FATO glicosimetro ator=paciente pep=item-03.criterio-1] Meu aparelho de medir a glicemia ficou sem fita, então não medi nesses dias.
[FATO sem-sintomas-urinarios ator=paciente pep=item-03.criterio-3] Não tenho ardência para urinar nem tosse ou catarro.
[FATO sem-dor-toracica ator=paciente pep=item-03.criterio-4] Não sinto dor no peito nem palpitação.

[TÓPICO] Antecedentes mórbidos
[FATO diagnostico-dm1 ator=paciente pep=item-04.criterio-1] Descobri o diabetes tipo 1 com 14 anos, quando fui parar na UTI.
[FATO esquema-insulina ator=paciente pep=item-04.criterio-1] Uso insulina NPH, 18 unidades de manhã e 10 à noite, e insulina regular antes das refeições, umas 4 a 6 unidades, conforme o que eu como. Pego tudo na UBS.
[FATO cad-previa ator=paciente pep=item-04.criterio-2] Fiquei internado uma vez só, no diagnóstico. Hipoglicemia forte eu tive duas vezes no último ano, depois do treino.
[FATO controle-recente ator=paciente pep=item-04.criterio-2] Minha última hemoglobina glicada, faz quatro meses, deu 8,9%.
[FATO cirurgias ator=paciente] Nunca fiz cirurgia.

[TÓPICO] Medicações em uso e alergias
[FATO outras-medicacoes ator=paciente pep=item-04.criterio-3] Além da insulina, tomei só um comprimido de dimenidrinato ontem, que não adiantou. Não uso outro remédio.
[FATO alergias ator=paciente pep=item-04.criterio-3] Tenho alergia a dipirona, me dá placas vermelhas no corpo.

[TÓPICO] Hábitos de vida
[FATO alcool ator=paciente pep=item-04.criterio-4] Bebo cerveja nas festas, umas quatro latas, uma vez a cada quinze dias. Na última semana não bebi.
[FATO tabaco-drogas ator=paciente pep=item-04.criterio-4 EXPLÍCITO] Não fumo cigarro. Já fumei maconha em festa, mas faz meses; cocaína nunca usei.
[FATO atividade-fisica ator=paciente] Treino musculação cinco vezes por semana e faço estágio em academia.
[FATO moradia ator=paciente] Moro numa república com mais três colegas; minha família mora em outra cidade.

[TÓPICO] Histórico familiar
[FATO familia ator=paciente pep=item-04.criterio-5] Minha mãe tem hipotireoidismo e meu avô paterno tinha diabetes, mas ele tomava comprimido.

[REGRA comportamento-no-exame] Durante o exame físico, o ator mantém a respiração rápida e profunda, refere dor leve à palpação de todo o abdome, sem defesa, e pede água ao final.

[TÓPICO] Dúvidas obrigatórias do paciente
[PERGUNTA-OBRIGATÓRIA duvida-internacao ator=paciente] “Doutor, eu vou ter que ficar internado? Não dá para tomar um soro e ir embora?”
[PERGUNTA-OBRIGATÓRIA duvida-insulina-doente ator=paciente] “Eu errei de parar a insulina? O que eu faço da próxima vez que ficar doente e não conseguir comer?”
[PERGUNTA-OBRIGATÓRIA duvida-insulina-veia ator=paciente] “Vou ter que tomar insulina na veia daqui para a frente?”

[CONDUTA-ESPERADA resposta-as-duvidas] O candidato explica que se trata de cetoacidose diabética grave, com risco de vida, que exige internação em UTI para soro, insulina na veia por bomba de infusão e controle frequente do potássio e da glicemia. Explica, sem julgamento, que a insulina basal (NPH) nunca deve ser suspensa, mesmo sem comer; nos dias de doença, mede a glicemia a cada 3 a 4 horas, pesquisa cetonas, mantém hidratação oral com líquidos e carboidratos fracionados, ajusta a insulina regular pela glicemia e procura o serviço se houver vômitos persistentes, glicemia acima de 250 mg/dL persistente ou cetonas positivas. Garante a reposição das fitas pela UBS. Explica que a insulina venosa é temporária e que, após a resolução, volta ao esquema subcutâneo, com sobreposição de 1 a 2 horas, e encaminhamento ao ambulatório de endocrinologia e educação em diabetes.

# 4. IMPRESSOS DISPONÍVEIS NA ESTAÇÃO

[IMPRESSO impresso-1-exame-fisico categoria=exame-fisico] IMPRESSO 1 — EXAME FÍSICO SEGMENTAR
[LIBERAÇÃO] exame físico; examinar o paciente; exame físico completo; sinais vitais
[CONTEÚDO]
- **Estado geral:** regular estado geral, sonolento porém despertável, orientado no tempo e no espaço; desidratado (+++/4+), mucosas secas, acianótico, anictérico, afebril.
- **Sinais vitais:** PA 94 x 56 mmHg (deitado), 82 x 50 mmHg (sentado); FC 126 bpm; FR 30 irpm com respiração profunda e regular; temperatura axilar 37,4 °C; SpO2 98% em ar ambiente; tempo de enchimento capilar 3 s; peso 68 kg.
- **Cabeça e pescoço:** hálito cetônico (odor de maçã passada); língua seca; turgor cutâneo diminuído; jugulares planas a 45°.
- **Aparelho respiratório:** respiração de Kussmaul; murmúrio vesicular presente bilateralmente, sem ruídos adventícios; sem tiragens.
- **Aparelho cardiovascular:** ritmo cardíaco regular em 2 tempos, taquicárdico, bulhas normofonéticas, sem sopros; pulsos periféricos finos e simétricos.
- **Abdome:** plano, ruídos hidroaéreos diminuídos; dor difusa leve à palpação profunda, sem defesa; sinal de Blumberg negativo; sinal de Murphy negativo; sinal de Giordano negativo bilateralmente; sem visceromegalias.
- **Neurológico:** Glasgow 14 (ocular 3, verbal 5, motor 6); pupilas isocóricas e fotorreagentes; sem déficits focais; sem rigidez de nuca; Kernig e Brudzinski negativos.
- **Pele e extremidades:** locais de aplicação de insulina em abdome e coxas sem lipodistrofia ou sinais de infecção; sem edema.

[IMPRESSO impresso-2-glicemia-capilar categoria=laboratorio] IMPRESSO 2 — GLICEMIA CAPILAR
[LIBERAÇÃO] glicemia capilar; dextro; HGT; glicemia de ponta de dedo; hemoglicoteste
[CONTEÚDO]
- Glicemia capilar: 478 mg/dL. Referência em jejum: 70 a 99 mg/dL.

[IMPRESSO impresso-3-gasometria categoria=laboratorio] IMPRESSO 3 — GASOMETRIA ARTERIAL (AR AMBIENTE)
[LIBERAÇÃO] gasometria; gasometria arterial; gasometria venosa; gaso
[CONTEÚDO]
- pH: 6,98. Referência: 7,35 a 7,45.
- pCO2: 17 mmHg. Referência: 35 a 45 mmHg.
- pO2: 108 mmHg. Referência: 80 a 100 mmHg.
- Bicarbonato (HCO3): 6 mEq/L. Referência: 22 a 26 mEq/L.
- Excesso de bases (BE): -26 mEq/L. Referência: -2 a +2 mEq/L.
- Saturação de O2: 98%. Referência: acima de 95%.
- Lactato: 1,6 mmol/L. Referência: até 2,0 mmol/L.

[IMPRESSO impresso-4-bioquimica categoria=laboratorio] IMPRESSO 4 — ELETRÓLITOS, FUNÇÃO RENAL E GLICOSE PLASMÁTICA
[LIBERAÇÃO] eletrólitos; sódio; potássio; cloro; ionograma; ureia; creatinina; função renal; glicose plasmática; glicemia sérica; fósforo; magnésio
[CONTEÚDO]
- Glicose plasmática: 486 mg/dL. Referência em jejum: 70 a 99 mg/dL.
- Sódio: 131 mEq/L. Referência: 135 a 145 mEq/L.
- Potássio: 5,6 mEq/L. Referência: 3,5 a 5,0 mEq/L.
- Cloro: 98 mEq/L. Referência: 98 a 107 mEq/L.
- Ureia: 64 mg/dL. Referência: 15 a 40 mg/dL.
- Creatinina: 1,6 mg/dL. Referência: 0,7 a 1,3 mg/dL.
- Fósforo: 5,2 mg/dL. Referência: 2,5 a 4,5 mg/dL.
- Magnésio: 1,9 mg/dL. Referência: 1,7 a 2,4 mg/dL.

[IMPRESSO impresso-5-cetonas-urina categoria=laboratorio] IMPRESSO 5 — BETA-HIDROXIBUTIRATO SÉRICO E URINA TIPO 1
[LIBERAÇÃO] cetonemia; beta-hidroxibutirato; corpos cetônicos; cetonúria; urina tipo 1; EAS; exame de urina
[CONTEÚDO]
- Beta-hidroxibutirato sérico: 6,1 mmol/L. Referência: inferior a 0,6 mmol/L.
- Urina tipo 1 — densidade: 1,030. Referência: 1,005 a 1,030.
- Glicose: 4+. Referência: negativa.
- Corpos cetônicos: 3+. Referência: negativos.
- Nitrito: negativo. Referência: negativo.
- Leucócitos: 3 por campo. Referência: até 5 por campo.

[IMPRESSO impresso-6-hemograma-pcr categoria=laboratorio] IMPRESSO 6 — HEMOGRAMA E PROTEÍNA C-REATIVA
[LIBERAÇÃO] hemograma; hemograma completo; PCR; proteína C-reativa
[CONTEÚDO]
- Hemoglobina: 16,2 g/dL. Referência: 13,5 a 17,5 g/dL.
- Hematócrito: 49%. Referência: 41 a 53%.
- Leucócitos: 16.800/mm³ (bastões 3%, segmentados 78%, linfócitos 15%). Referência: 4.000 a 11.000/mm³.
- Plaquetas: 310.000/mm³. Referência: 150.000 a 450.000/mm³.
- PCR: 18 mg/L. Referência: inferior a 5 mg/L.

[IMPRESSO impresso-7-ecg categoria=imagem] IMPRESSO 7 — ELETROCARDIOGRAMA DE 12 DERIVAÇÕES
[LIBERAÇÃO] eletrocardiograma; ECG; eletro
[CONTEÚDO]
- **Técnica:** ECG de repouso, 12 derivações, velocidade 25 mm/s, calibração 10 mm/mV.
- **Achados:** ritmo sinusal, FC 122 bpm; eixo elétrico em +60°; intervalo PR 140 ms; QRS 88 ms; QTc 420 ms; ondas T discretamente apiculadas, de base estreita, em V2 a V4; sem alterações do segmento ST; sem ondas Q patológicas.
- **Impressão diagnóstica:** taquicardia sinusal com ondas T discretamente apiculadas, compatíveis com hiperpotassemia leve.

# 5. PADRÃO ESPERADO DE PROCEDIMENTO (PEP)

[ITEM item-01] Apresentação e acolhimento
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] apresenta-se com nome e função
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] confirma o nome do paciente e pergunta o motivo da procura
[NÍVEL adequado pontos=0,3 mínimo=2] Realiza os 2 critérios.
[NÍVEL parcialmente_adequado pontos=0,1 mínimo=1] Realiza 1 critério.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhum critério.

[ITEM item-02] Anamnese — sintomas principais
[CRITÉRIO criterio-1 tipo=PERGUNTA] poliúria e polidipsia
[CRITÉRIO criterio-2 tipo=PERGUNTA] perda de peso
[CRITÉRIO criterio-3 tipo=PERGUNTA] náuseas e vômitos (número de episódios e aspecto)
[CRITÉRIO criterio-4 tipo=PERGUNTA] dor abdominal (localização, início e características)
[CRITÉRIO criterio-5 tipo=PERGUNTA] dispneia, cansaço e sonolência
[NÍVEL adequado pontos=0,6 mínimo=4] Investiga 4 ou 5 critérios.
[NÍVEL parcialmente_adequado pontos=0,3 mínimo=2] Investiga 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-03] Anamnese — fator precipitante
[CRITÉRIO criterio-1 tipo=PERGUNTA OBRIGATÓRIO] uso da insulina nos últimos dias (omissão ou redução de doses) e automonitorização da glicemia
[CRITÉRIO criterio-2 tipo=PERGUNTA] febre, diarreia e quadro infeccioso recente
[CRITÉRIO criterio-3 tipo=PERGUNTA] disúria, tosse e expectoração
[CRITÉRIO criterio-4 tipo=PERGUNTA] dor torácica ou palpitações
[NÍVEL adequado pontos=0,6 mínimo=3] Investiga 3 ou 4 critérios, incluindo o uso da insulina.
[NÍVEL parcialmente_adequado pontos=0,3 mínimo=2] Investiga 2 critérios, incluindo o uso da insulina.
[NÍVEL inadequado pontos=0 mínimo=0] Não investiga o uso da insulina.

[ITEM item-04] Anamnese — antecedentes, medicações, hábitos e família
[CRITÉRIO criterio-1 tipo=PERGUNTA] tempo de diagnóstico do diabetes tipo 1 e esquema de insulina (NPH e regular, com doses)
[CRITÉRIO criterio-2 tipo=PERGUNTA] episódios prévios de cetoacidose, hipoglicemias graves e controle glicêmico (hemoglobina glicada)
[CRITÉRIO criterio-3 tipo=PERGUNTA] outras medicações em uso e alergias medicamentosas
[CRITÉRIO criterio-4 tipo=PERGUNTA] consumo de álcool, tabaco e drogas ilícitas (cocaína)
[CRITÉRIO criterio-5 tipo=PERGUNTA] histórico familiar de doenças endócrinas
[NÍVEL adequado pontos=0,5 mínimo=4] Investiga 4 ou 5 critérios.
[NÍVEL parcialmente_adequado pontos=0,25 mínimo=2] Investiga 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-05] Exame físico e verbalização dos achados
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-1-exame-fisico] solicita o exame físico segmentar com sinais vitais
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] verbaliza respiração de Kussmaul e hálito cetônico
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] verbaliza desidratação grave com hipotensão postural, taquicardia, mucosas secas e enchimento capilar de 3 s
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] verbaliza abdome sem sinais de peritonite (Blumberg negativo) e Glasgow 14 sem déficit focal
[NÍVEL adequado pontos=0,8 mínimo=3] Realiza 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=2] Realiza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza 1 critério ou nenhum.

[ITEM item-06] Solicitação de exames complementares
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-2-glicemia-capilar,impresso-5-cetonas-urina] glicemia capilar e beta-hidroxibutirato sérico ou cetonúria
[CRITÉRIO criterio-2 tipo=SOLICITAÇÃO impressos=impresso-3-gasometria] gasometria arterial ou venosa
[CRITÉRIO criterio-3 tipo=SOLICITAÇÃO impressos=impresso-4-bioquimica] sódio, potássio, cloro, ureia, creatinina, fósforo, magnésio e glicose plasmática
[CRITÉRIO criterio-4 tipo=SOLICITAÇÃO impressos=impresso-7-ecg] eletrocardiograma de 12 derivações
[CRITÉRIO criterio-5 tipo=SOLICITAÇÃO impressos=impresso-6-hemograma-pcr] hemograma completo e proteína C-reativa
[NÍVEL adequado pontos=1,0 mínimo=4] Solicita 4 ou 5 critérios.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Solicita 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Solicita 1 critério ou nenhum.

[ITEM item-07] Interpretação dos exames
[CRITÉRIO criterio-1 tipo=VERBALIZAÇÃO após=impresso-3-gasometria] acidose metabólica grave (pH 6,98; HCO3 6 mEq/L) com compensação respiratória adequada (pCO2 17 mmHg)
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-3-gasometria,impresso-4-bioquimica] calcula o ânion gap aumentado: 131 − (98 + 6) = 27 mEq/L
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-4-bioquimica] calcula o sódio corrigido pela glicemia: cerca de 137 mEq/L
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-4-bioquimica,impresso-7-ecg] interpreta potássio de 5,6 mEq/L com T apiculada como hiperpotassemia por deslocamento extracelular, com depleção do potássio corporal total
[CRITÉRIO criterio-5 tipo=VERBALIZAÇÃO após=impresso-5-cetonas-urina] beta-hidroxibutirato de 6,1 mmol/L e cetonúria 3+
[NÍVEL adequado pontos=1,0 mínimo=4] Verbaliza 4 ou 5 critérios.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Verbaliza 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Verbaliza 1 critério ou nenhum.

[ITEM item-08] Hipótese diagnóstica
[CRITÉRIO criterio-1 tipo=VERBALIZAÇÃO após=impresso-3-gasometria,impresso-5-cetonas-urina OBRIGATÓRIO] formula o diagnóstico de cetoacidose diabética
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] classifica como grave (pH inferior a 7,0 e HCO3 inferior a 10 mEq/L, com rebaixamento leve do sensório)
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] identifica como fator precipitante a omissão da insulina durante gastroenterite aguda
[NÍVEL adequado pontos=1,0 mínimo=3] Realiza os 3 critérios.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=1] Formula o diagnóstico sem classificar a gravidade ou sem identificar o fator precipitante.
[NÍVEL inadequado pontos=0 mínimo=0] Não formula o diagnóstico de cetoacidose diabética.

[ITEM item-09] Conduta — hidratação venosa
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] prescreve soro fisiológico 0,9%, 15 a 20 mL/kg (1.000 a 1.500 mL) IV na primeira hora
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] mantém hidratação de 250 a 500 mL/h guiada pelo sódio corrigido (NaCl 0,45% se sódio corrigido normal ou elevado; NaCl 0,9% se baixo)
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] acrescenta soro glicosado 5% quando a glicemia atingir 250 mg/dL ou menos
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] monitora diurese e balanço hídrico
[NÍVEL adequado pontos=1,2 mínimo=3] Realiza 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,6 mínimo=2] Realiza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Não prescreve a expansão volêmica inicial com soro fisiológico 0,9%.

[ITEM item-10] Conduta — insulinoterapia e potássio
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] confirma potássio igual ou superior a 3,3 mEq/L antes de iniciar a insulina
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO OBRIGATÓRIO] prescreve insulina regular IV em bomba de infusão contínua, 0,1 U/kg/h (cerca de 7 U/h), com ou sem bolus de 0,1 U/kg
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] não repõe potássio enquanto superior a 5,2 mEq/L e programa 20 a 30 mEq de KCl por litro de soro quando entre 3,3 e 5,2 mEq/L
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] reduz a insulina para 0,02 a 0,05 U/kg/h quando a glicemia chegar a 250 mg/dL, mantendo-a entre 150 e 200 mg/dL
[CRITÉRIO bicarbonato-indevido tipo=COMUNICAÇÃO PROIBIDO] prescreve bicarbonato de sódio com pH de 6,98
[NÍVEL adequado pontos=1,4 mínimo=3] Realiza 3 ou 4 critérios, incluindo a insulina regular IV.
[NÍVEL parcialmente_adequado pontos=0,7 mínimo=2] Realiza 2 critérios, incluindo a insulina regular IV.
[NÍVEL inadequado pontos=0 mínimo=0] Não prescreve insulina regular IV ou prescreve bicarbonato de sódio.

[ITEM item-11] Monitorização, destino e critérios de resolução
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] solicita glicemia capilar de 1/1 h
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] solicita eletrólitos (potássio) e gasometria venosa a cada 2 a 4 h
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] indica internação em UTI com monitorização cardíaca contínua
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] cita critérios de resolução (glicemia inferior a 200 mg/dL e dois entre HCO3 igual ou superior a 15 mEq/L, pH venoso superior a 7,30 e ânion gap até 12) e transição para insulina subcutânea com sobreposição de 1 a 2 h
[NÍVEL adequado pontos=0,8 mínimo=3] Realiza 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=2] Realiza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza 1 critério ou nenhum.

[ITEM item-12] Comunicação e Resolução de Dúvidas
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO perguntas=duvida-internacao] explica a gravidade da cetoacidose e a necessidade de internação em UTI
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO perguntas=duvida-insulina-doente] orienta, sem julgamento, a nunca suspender a NPH e as regras para dias de doença (glicemia a cada 3 a 4 h, cetonas, hidratação e procura do serviço)
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO perguntas=duvida-insulina-veia] explica que a insulina venosa é temporária, com retorno ao esquema subcutâneo e seguimento com endocrinologia
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] mantém postura empática e linguagem acessível, sem jargões
[NÍVEL adequado pontos=0,8 mínimo=4] Cumpre os 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=2] Cumpre 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Cumpre 1 critério ou nenhum.
