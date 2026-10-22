# ESTAÇÃO

[ESTAÇÃO pre-eclampsia-grave-terceiro-trimestre]
[ÁREA] Ginecologia e Obstetrícia
[TEMA] Pré-eclâmpsia com sinais de gravidade no terceiro trimestre
[PROVISÓRIO] sim

# 1. CENÁRIO DE ATUAÇÃO E INSTRUÇÕES AO PARTICIPANTE

[CENÁRIO] Você é o médico ou a médica plantonista do pronto-atendimento obstétrico de uma maternidade de referência para gestação de alto risco do SUS. A unidade dispõe de centro obstétrico, laboratório, cardiotocografia, ultrassonografia com Doppler, farmácia e unidade de terapia intensiva. Uma gestante de 23 anos procura atendimento por dor de cabeça, trazendo a caderneta da gestante.
[TAREFA tarefa-1] Realizar a anamnese dirigida.
[TAREFA tarefa-2] Solicitar o exame físico e os exames complementares pertinentes e interpretar os resultados.
[TAREFA tarefa-3] Formular a hipótese diagnóstica.
[TAREFA tarefa-4] Instituir a conduta inicial e definir o plano terapêutico.
[TAREFA tarefa-5] Orientar a paciente e responder às suas dúvidas.

# 2. ATORES

[ATOR paciente papel=paciente idade=23 voz=feminina-adulta] Tainá Rodrigues Melo
[PERFIL] Gestante, primigesta, sentada na maca com a mão na testa, incomodada com a luz da sala. Está ansiosa e com medo de que algo aconteça com o bebê. Colabora com o atendimento, mas fica mais aflita se o médico demorar a explicar o que está acontecendo.
[TOM] Fala de forma simples, com ensino médio completo, trabalha como atendente de loja. Usa expressões como "boca do estômago" e "pontinhos brilhando na vista". Responde de forma curta e só detalha quando perguntada.
[CONTEXTO] Tainá Rodrigues Melo, 23 anos, primigesta, com 36 semanas e 1 dia de gestação, datada por ultrassonografia do primeiro trimestre. Fez sete consultas de pré-natal na UBS do bairro. Procura a maternidade porque está com dor de cabeça forte desde a manhã, que não melhorou com analgésico, e há duas horas começou a ver pontos brilhantes e a sentir dor no estômago. Sinais vitais na chegada: PA 168/112 mmHg, FC 92 bpm, FR 18 irpm, temperatura axilar 36,6 °C, SpO2 98% em ar ambiente.

# 3. ROTEIRO DO ATOR SIMULADO

[TÓPICO] Queixa principal e história da doença atual
[FATO cefaleia-inicio ator=paciente pep=item-02.criterio-1] A dor de cabeça começou hoje de manhã, quando acordei, faz umas oito horas. É na testa e na nuca, latejando, muito forte, a mais forte que já tive.
[FATO cefaleia-analgesico ator=paciente pep=item-02.criterio-1] Tomei um paracetamol de 750 mg às dez da manhã e não melhorou nada.
[FATO escotomas ator=paciente pep=item-02.criterio-2] Faz umas duas horas que estou vendo uns pontinhos brilhando na vista, e a claridade incomoda.
[FATO visao-turva ator=paciente pep=item-02.criterio-2 EXPLÍCITO] Às vezes a vista fica meio embaçada, mas não fiquei cega em nenhum momento.
[FATO epigastralgia ator=paciente pep=item-02.criterio-3] Também começou uma dor aqui na boca do estômago, que vai um pouco para o lado direito, embaixo das costelas. Começou junto com os pontinhos.
[FATO nausea ator=paciente pep=item-02.criterio-4] Estou enjoada, mas não vomitei.
[FATO edema ator=paciente pep=item-02.criterio-5] Faz uma semana que meus pés e minhas mãos estão muito inchados. A aliança não entra mais e o rosto amanheceu inchado.
[FATO ganho-peso ator=paciente pep=item-02.criterio-5 EXPLÍCITO] Engordei uns três quilos em uma semana, a balança da UBS mostrou.
[FATO sem-convulsao ator=paciente EXPLÍCITO] Não desmaiei, não tive convulsão e não estou com falta de ar.

[TÓPICO] Queixas obstétricas e bem-estar fetal
[FATO movimentos-fetais ator=paciente pep=item-03.criterio-1] O bebê está mexendo normal, mexeu bastante hoje.
[FATO sem-perdas ator=paciente pep=item-03.criterio-2] Não perdi água nem sangue.
[FATO sem-contracoes ator=paciente pep=item-03.criterio-3] A barriga não está endurecendo e não tenho cólica.

[TÓPICO] Pré-natal, antecedentes e hábitos
[FATO idade-gestacional ator=paciente pep=item-04.criterio-1] Estou com 36 semanas, foi o ultrassom do começo da gravidez que deu a data. Fiz sete consultas na UBS.
[FATO pa-prenatal ator=paciente pep=item-04.criterio-2] A pressão sempre foi 11 por 7. Na última consulta, há duas semanas, deu 13 por 8,5, e a enfermeira pediu para eu voltar em uma semana, mas eu não consegui ir.
[FATO sem-has-previa ator=paciente pep=item-04.criterio-2] Antes de engravidar eu nunca tive pressão alta.
[FATO comorbidades ator=paciente pep=item-04.criterio-3] Não tenho diabetes, problema de rim nem outra doença.
[FATO historia-familiar ator=paciente pep=item-04.criterio-3 EXPLÍCITO] Minha mãe teve pressão alta na gravidez de mim e precisou fazer cesárea antes do tempo.
[FATO medicacoes ator=paciente pep=item-04.criterio-4] Só tomo o sulfato ferroso que a UBS deu. Ninguém me passou AAS nem cálcio.
[FATO alergias ator=paciente pep=item-04.criterio-4] Não tenho alergia a nenhum remédio.
[FATO habitos ator=paciente EXPLÍCITO] Não fumo, não bebo e não uso drogas.
[FATO cirurgias ator=paciente EXPLÍCITO] Nunca fiz cirurgia.

[REGRA comportamento-exame-fisico] Se o candidato disser que vai examinar a paciente ou pedir o exame físico, o examinador entrega o impresso do exame físico. A atriz deita na maca, com a cabeça elevada, e refere dor leve quando o examinador palpa a região epigástrica.
[REGRA comportamento-sulfato] Se o candidato prescrever o sulfato de magnésio, a atriz comenta que está sentindo calor no corpo, sem outras queixas. Se o candidato não explicar o motivo da medicação, a atriz faz a dúvida sobre o remédio da veia.
[REGRA momento-duvidas] Nos três minutos finais, ou logo após o candidato comunicar o diagnóstico e a conduta, a atriz faz as dúvidas obrigatórias, uma de cada vez, aguardando a resposta.

[TÓPICO] Dúvidas obrigatórias da paciente
[PERGUNTA-OBRIGATÓRIA duvida-parto ator=paciente] “Doutor, meu bebê vai ter que nascer agora? Ainda não deu nove meses, não é perigoso para ele?”
[PERGUNTA-OBRIGATÓRIA duvida-medicacao ator=paciente] “Esse remédio que vão colocar na minha veia é para quê? Eu posso ter convulsão?”
[PERGUNTA-OBRIGATÓRIA duvida-futuro ator=paciente] “Depois que o bebê nascer, a pressão volta ao normal? Isso pode acontecer de novo?”

[CONDUTA-ESPERADA conduta-geral] O candidato confirma a hipertensão grave (PA ≥160/110 mmHg em duas aferições), reconhece a pré-eclâmpsia com sinais de gravidade (hipertensão grave, cefaleia refratária, escotomas e dor epigástrica, com proteinúria significativa) e afasta a síndrome HELLP e a lesão renal pelos exames. Interna a paciente no centro obstétrico com monitorização materno-fetal contínua, inicia sulfato de magnésio (esquema de Zuspan: ataque de 4 g IV em 15 a 20 minutos, manutenção de 1 g/h IV em bomba de infusão até 24 horas após o parto; o esquema de Pritchard também é aceito), com controle de reflexos patelares, frequência respiratória ≥16 irpm e diurese ≥25 mL/h por sonda vesical de demora, deixando gluconato de cálcio 10% disponível como antídoto. Trata a crise hipertensiva com hidralazina 5 mg IV a cada 20 minutos (máximo de 30 mg) ou nifedipino 10 mg VO a cada 20 a 30 minutos (máximo de 30 mg), com meta de PAS 140 a 155 mmHg e PAD 90 a 100 mmHg, sem queda abrupta. Com 36 semanas e sinais de gravidade, indica a resolução da gestação após a estabilização materna, com via de parto por indicação obstétrica (a indução do parto com preparo do colo é possível, e a cesariana fica reservada às indicações obstétricas ou à piora clínica). A corticoterapia para maturação pulmonar fetal não está indicada nessa idade gestacional, e sua omissão não deve ser penalizada.
[CONDUTA-ESPERADA resposta-duvida-parto] O candidato explica que o parto é o tratamento definitivo da pré-eclâmpsia, que com 36 semanas o bebê já tem boas condições de nascer e que manter a gravidez traz risco maior para ela e para o bebê (convulsão, AVC, descolamento da placenta, sofrimento fetal). Informa que o parto será feito depois de controlar a pressão e de iniciar o remédio contra convulsão e que pode ser normal, com indução, se não houver indicação de cesárea.
[CONDUTA-ESPERADA resposta-duvida-medicacao] O candidato explica que o sulfato de magnésio serve para prevenir a convulsão (eclâmpsia), que o risco existe por causa da gravidade do quadro e que ela ficará monitorizada pela equipe. Explica que a sensação de calor é comum e que a medicação será mantida até 24 horas depois do parto.
[CONDUTA-ESPERADA resposta-duvida-futuro] O candidato explica que a pressão costuma voltar ao normal em algumas semanas após o parto, mas que nos primeiros dias ainda há risco de complicações e por isso ela ficará monitorizada. Orienta o seguimento da pressão no pós-parto, o risco maior de pressão alta e de doença cardiovascular ao longo da vida e o risco de repetir o quadro numa próxima gravidez, quando deverá iniciar o pré-natal cedo e usar AAS e cálcio a partir do início da gestação, conforme orientação médica.

# 4. IMPRESSOS DISPONÍVEIS NA ESTAÇÃO

[IMPRESSO impresso-1-exame-fisico categoria=exame-fisico] IMPRESSO 1 — EXAME FÍSICO
[LIBERAÇÃO] exame físico; examinar a paciente; sinais vitais; aferir a pressão arterial; exame obstétrico; batimentos cardíacos fetais; reflexos
[CONTEÚDO]
- **Estado geral:** bom estado geral, consciente, orientada, Glasgow 15, corada, hidratada, acianótica, anictérica. Fotofobia.
- **Sinais vitais:** PA 168/112 mmHg (sentada, braço esquerdo, manguito adequado); PA após 15 minutos de repouso 166/110 mmHg; FC 92 bpm; FR 18 irpm; temperatura axilar 36,6 °C; SpO2 98% em ar ambiente.
- **Peso:** 78 kg (peso pré-gestacional de 66 kg; 75 kg há duas semanas na caderneta).
- **Edema:** 2+/4+ em membros inferiores, mãos e face.
- **Aparelho cardiovascular:** ritmo cardíaco regular, em dois tempos, bulhas normofonéticas, sem sopros.
- **Aparelho respiratório:** murmúrio vesicular presente bilateralmente, sem ruídos adventícios.
- **Abdome:** gravídico, dor leve à palpação profunda do epigástrio e do hipocôndrio direito, sem defesa.
- **Exame obstétrico:** altura uterina de 33 cm; feto único, longitudinal, cefálico; dinâmica uterina ausente em 10 minutos; tônus uterino normal; BCF 142 bpm, rítmicos.
- **Exame especular:** sem perdas de líquido ou de sangue pelo orifício externo do colo.
- **Toque vaginal:** colo posterior, grosso, impérvio; apresentação cefálica alta; índice de Bishop 3.
- **Exame neurológico:** sem déficits focais; reflexos patelares vivos e aumentados (3+), bilaterais; sem clônus.

[IMPRESSO impresso-2-hemograma categoria=laboratorio] IMPRESSO 2 — HEMOGRAMA COMPLETO
[LIBERAÇÃO] hemograma; hemograma completo; contagem de plaquetas; plaquetas; série vermelha; esfregaço de sangue periférico
[CONTEÚDO]
- **Hemoglobina:** 12,4 g/dL (referência na gestação: ≥11,0 g/dL)
- **Hematócrito:** 37% (referência na gestação: 33% a 44%)
- **Leucócitos:** 10.800/mm³ (referência na gestação: 6.000 a 16.000/mm³)
- **Plaquetas:** 145.000/mm³ (referência: 150.000 a 450.000/mm³)
- **Esfregaço de sangue periférico:** ausência de esquizócitos (referência: ausentes)

[IMPRESSO impresso-3-bioquimica categoria=laboratorio] IMPRESSO 3 — BIOQUÍMICA E FUNÇÃO HEPÁTICA E RENAL
[LIBERAÇÃO] bioquímica; função hepática; transaminases; TGO; TGP; AST; ALT; desidrogenase láctica; DHL; LDH; bilirrubinas; função renal; creatinina; ureia; ácido úrico; exames para HELLP
[CONTEÚDO]
- **AST (TGO):** 34 U/L (referência: até 40 U/L)
- **ALT (TGP):** 29 U/L (referência: até 41 U/L)
- **Desidrogenase láctica (LDH):** 390 U/L (referência: 135 a 225 U/L; valor ≥600 U/L sugere hemólise)
- **Bilirrubina total:** 0,7 mg/dL (referência: 0,2 a 1,2 mg/dL)
- **Bilirrubina indireta:** 0,4 mg/dL (referência: até 0,8 mg/dL)
- **Creatinina:** 0,8 mg/dL (referência na gestação: 0,4 a 0,8 mg/dL; >1,1 mg/dL indica gravidade)
- **Ureia:** 22 mg/dL (referência: 15 a 40 mg/dL)
- **Ácido úrico:** 6,1 mg/dL (referência na gestação: 2,5 a 5,5 mg/dL)

[IMPRESSO impresso-4-proteinuria categoria=laboratorio] IMPRESSO 4 — AVALIAÇÃO DE PROTEINÚRIA
[LIBERAÇÃO] proteinúria; relação proteína/creatinina urinária; relação proteína creatinina; proteinúria de fita; urina tipo 1; EAS; exame de urina; proteinúria de 24 horas
[CONTEÚDO]
- **Relação proteína/creatinina em amostra isolada de urina:** 1,2 mg/mg (referência: <0,3 mg/mg)
- **Proteína na fita urinária:** 2+ (referência: negativa)
- **Urina tipo 1:** densidade 1,020 (referência: 1,005 a 1,030); leucócitos 4/campo (referência: até 10/campo); hemácias 2/campo (referência: até 5/campo); nitrito negativo (referência: negativo)
- **Observação:** a proteinúria de 24 horas não está disponível de imediato; resultado previsto em 24 horas.

[IMPRESSO impresso-5-cardiotocografia categoria=imagem] IMPRESSO 5 — CARDIOTOCOGRAFIA
[LIBERAÇÃO] cardiotocografia; CTG; cardiotoco; monitorização fetal; avaliação da vitalidade fetal
[CONTEÚDO]
- **Duração do registro:** 30 minutos
- **Linha de base da frequência cardíaca fetal:** 140 bpm (referência: 110 a 160 bpm)
- **Variabilidade:** moderada, 6 a 25 bpm (referência: moderada)
- **Acelerações transitórias:** presentes, quatro em 30 minutos
- **Desacelerações:** ausentes
- **Contrações uterinas:** ausentes
- **Conclusão:** traçado categoria I, sugestivo de bem-estar fetal

[IMPRESSO impresso-6-ultrassonografia categoria=imagem] IMPRESSO 6 — ULTRASSONOGRAFIA OBSTÉTRICA COM DOPPLER
[LIBERAÇÃO] ultrassonografia obstétrica; ultrassom obstétrico; ultrassonografia com Doppler; Doppler obstétrico; dopplervelocimetria; perfil biofísico fetal; avaliação do crescimento fetal
[CONTEÚDO]
- **Feto:** único, vivo, cefálico, dorso à esquerda; batimentos cardíacos de 144 bpm
- **Biometria:** peso fetal estimado de 2.750 g (percentil 35 para 36 semanas; referência: entre os percentis 10 e 90)
- **Índice de líquido amniótico:** 11 cm (referência: 5 a 25 cm)
- **Placenta:** posterior, grau II, sem sinais de descolamento
- **Doppler da artéria umbilical:** índice de pulsatilidade 0,82 (referência: abaixo do percentil 95; diástole presente)
- **Doppler da artéria cerebral média:** índice de pulsatilidade 1,70 (referência: acima do percentil 5)
- **Perfil biofísico fetal:** 8/8 (referência: 8 ou 10)
- **Conclusão:** crescimento fetal adequado e vitalidade fetal preservada

# 5. PADRÃO ESPERADO DE PROCEDIMENTO (PEP)

[ITEM item-01] Apresentação e identificação
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Apresenta-se pelo nome e pela função
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] identifica a paciente pelo nome
[NÍVEL adequado pontos=0,25 mínimo=2] Realiza as duas ações.
[NÍVEL parcialmente_adequado pontos=0,125 mínimo=1] Realiza uma ação.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma ação.

[ITEM item-02] Anamnese dos sintomas atuais
[CRITÉRIO criterio-1 tipo=PERGUNTA] Investiga início, localização, intensidade da cefaleia e resposta ao analgésico
[CRITÉRIO criterio-2 tipo=PERGUNTA] investiga alterações visuais (escotomas, visão turva, fotofobia)
[CRITÉRIO criterio-3 tipo=PERGUNTA] investiga dor epigástrica ou em hipocôndrio direito
[CRITÉRIO criterio-4 tipo=PERGUNTA] investiga náuseas ou vômitos
[CRITÉRIO criterio-5 tipo=PERGUNTA] investiga edema ou ganho de peso súbito
[NÍVEL adequado pontos=1,0 mínimo=4] Investiga quatro ou cinco itens.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Investiga dois ou três itens.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga um item ou nenhum.

[ITEM item-03] Anamnese obstétrica atual
[CRITÉRIO criterio-1 tipo=PERGUNTA] Pergunta sobre os movimentos fetais
[CRITÉRIO criterio-2 tipo=PERGUNTA] pergunta sobre perda de líquido ou sangramento vaginal
[CRITÉRIO criterio-3 tipo=PERGUNTA] pergunta sobre contrações uterinas
[NÍVEL adequado pontos=0,5 mínimo=3] Investiga os três itens.
[NÍVEL parcialmente_adequado pontos=0,25 mínimo=2] Investiga dois itens.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga um item ou nenhum.

[ITEM item-04] Antecedentes e fatores de risco
[CRITÉRIO criterio-1 tipo=PERGUNTA] Confirma a idade gestacional e o acompanhamento pré-natal
[CRITÉRIO criterio-2 tipo=PERGUNTA] pergunta sobre a pressão arterial no pré-natal e a hipertensão prévia à gestação
[CRITÉRIO criterio-3 tipo=PERGUNTA] pergunta sobre comorbidades (diabetes, doença renal, doença autoimune) ou antecedente familiar de pré-eclâmpsia
[CRITÉRIO criterio-4 tipo=PERGUNTA] pergunta sobre medicações em uso e alergias
[NÍVEL adequado pontos=0,75 mínimo=4] Investiga os quatro itens.
[NÍVEL parcialmente_adequado pontos=0,375 mínimo=2] Investiga dois ou três itens.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga um item ou nenhum.

[ITEM item-05] Exame físico
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-1-exame-fisico] Solicita o exame físico com aferição da pressão arterial, exame obstétrico com ausculta dos batimentos cardíacos fetais e pesquisa de reflexos
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] identifica a hipertensão grave confirmada em duas aferições (PA ≥160/110 mmHg) e a hiperreflexia
[NÍVEL adequado pontos=0,5 mínimo=2] Realiza as duas ações.
[NÍVEL parcialmente_adequado pontos=0,25 mínimo=1] Realiza uma ação.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma ação.

[ITEM item-06] Exames laboratoriais
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-2-hemograma] Solicita hemograma com contagem de plaquetas
[CRITÉRIO criterio-2 tipo=SOLICITAÇÃO impressos=impresso-3-bioquimica] solicita transaminases, LDH, bilirrubinas e função renal
[CRITÉRIO criterio-3 tipo=SOLICITAÇÃO impressos=impresso-4-proteinuria] solicita avaliação de proteinúria (relação proteína/creatinina urinária ou fita)
[NÍVEL adequado pontos=0,75 mínimo=3] Solicita os três grupos de exames.
[NÍVEL parcialmente_adequado pontos=0,375 mínimo=2] Solicita dois grupos de exames.
[NÍVEL inadequado pontos=0 mínimo=0] Solicita um grupo ou nenhum.

[ITEM item-07] Avaliação da vitalidade fetal
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-5-cardiotocografia] Solicita cardiotocografia
[CRITÉRIO criterio-2 tipo=SOLICITAÇÃO impressos=impresso-6-ultrassonografia] solicita ultrassonografia obstétrica com Doppler ou perfil biofísico fetal
[NÍVEL adequado pontos=0,5 mínimo=2] Solicita os dois exames.
[NÍVEL parcialmente_adequado pontos=0,25 mínimo=1] Solicita um exame.
[NÍVEL inadequado pontos=0 mínimo=0] Não solicita nenhum exame de vitalidade fetal.

[ITEM item-08] Diagnóstico
[CRITÉRIO criterio-1 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico OBRIGATÓRIO] Formula o diagnóstico de pré-eclâmpsia com sinais de gravidade (ou pré-eclâmpsia grave)
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] justifica a gravidade pela hipertensão grave e pelos sintomas de iminência de eclâmpsia (cefaleia, escotomas, dor epigástrica)
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-2-hemograma,impresso-3-bioquimica] afasta a síndrome HELLP e a lesão renal aguda pelos exames laboratoriais
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-5-cardiotocografia,impresso-6-ultrassonografia] interpreta a vitalidade fetal como preservada
[NÍVEL adequado pontos=1,5 mínimo=4] Realiza as quatro ações, incluindo o diagnóstico.
[NÍVEL parcialmente_adequado pontos=0,75 mínimo=2] Realiza duas ou três ações, incluindo o diagnóstico.
[NÍVEL inadequado pontos=0 mínimo=0] Não formula o diagnóstico de pré-eclâmpsia com sinais de gravidade.

[ITEM item-09] Prevenção da eclâmpsia com sulfato de magnésio
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] Prescreve sulfato de magnésio com dose de ataque de 4 g IV em 15 a 20 minutos (Zuspan) ou esquema de Pritchard
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] prescreve manutenção de 1 g/h IV em bomba de infusão, mantida até 24 horas após o parto
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] orienta monitorização de reflexos patelares, frequência respiratória (≥16 irpm) e diurese (≥25 mL/h) com sonda vesical de demora
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] indica gluconato de cálcio 10%, 10 mL IV lento, como antídoto em caso de intoxicação
[CRITÉRIO diazepam-substituicao tipo=COMUNICAÇÃO PROIBIDO] utiliza diazepam ou fenitoína em substituição ao sulfato de magnésio
[NÍVEL adequado pontos=1,5 mínimo=4] Realiza as quatro ações.
[NÍVEL parcialmente_adequado pontos=0,75 mínimo=2] Realiza duas ou três ações, incluindo a prescrição do sulfato de magnésio.
[NÍVEL inadequado pontos=0 mínimo=0] Não prescreve sulfato de magnésio ou o substitui por diazepam ou fenitoína.

[ITEM item-10] Tratamento da crise hipertensiva
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Prescreve anti-hipertensivo de ação rápida em dose correta: hidralazina 5 mg IV a cada 20 minutos (máximo de 30 mg) ou nifedipino 10 mg VO a cada 20 a 30 minutos (máximo de 30 mg)
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] define a meta de PAS entre 140 e 155 mmHg e PAD entre 90 e 100 mmHg, evitando queda abrupta
[CRITÉRIO ieca-proibido tipo=COMUNICAÇÃO PROIBIDO] prescreve inibidor da ECA ou bloqueador do receptor da angiotensina
[NÍVEL adequado pontos=1,0 mínimo=2] Realiza as duas ações.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=1] Realiza uma ação.
[NÍVEL inadequado pontos=0 mínimo=0] Não trata a crise hipertensiva ou prescreve inibidor da ECA ou bloqueador do receptor da angiotensina.

[ITEM item-11] Plano obstétrico e resolução da gestação
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] Indica a resolução da gestação após a estabilização materna
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] interna a paciente no centro obstétrico com monitorização materno-fetal contínua
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] define a via de parto por indicação obstétrica, considerando a indução do parto com preparo do colo
[CRITÉRIO alta-proibida tipo=COMUNICAÇÃO PROIBIDO] dá alta ou indica conduta expectante com seguimento ambulatorial
[NÍVEL adequado pontos=1,0 mínimo=3] Realiza as três ações.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Realiza duas ações, incluindo a indicação de resolução da gestação.
[NÍVEL inadequado pontos=0 mínimo=0] Não indica a resolução da gestação ou dá alta à paciente.

[ITEM item-12] Comunicação e resposta às dúvidas
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO perguntas=duvida-parto] Explica que o parto é o tratamento definitivo e que com 36 semanas o bebê tem boas condições de nascer
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO perguntas=duvida-medicacao] explica que o sulfato de magnésio previne a convulsão e que ela será monitorizada
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO perguntas=duvida-futuro] orienta a monitorização no pós-parto, o risco cardiovascular futuro e o risco de recorrência em nova gestação
[NÍVEL adequado pontos=0,75 mínimo=3] Responde às três dúvidas adequadamente.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Responde a duas dúvidas adequadamente.
[NÍVEL inadequado pontos=0 mínimo=0] Responde a uma dúvida ou a nenhuma.
