# ESTAÇÃO

[ESTAÇÃO pre-eclampsia-grave-terceiro-trimestre]
[ÁREA] Ginecologia e Obstetrícia
[TEMA] Pré-eclâmpsia com sinais de gravidade no terceiro trimestre
[PROVISÓRIO] sim

# 1. CENÁRIO DE ATUAÇÃO E INSTRUÇÕES AO PARTICIPANTE

[CENÁRIO] Você é o médico ou a médica plantonista do pronto atendimento obstétrico de uma maternidade de referência regional para gestação de alto risco, vinculada ao SUS. A unidade dispõe de materiais para o exame físico e obstétrico (esfigmomanômetro com manguito adequado, sonar Doppler, fita métrica, espéculo, martelo de reflexos), laboratório 24 horas com hemograma, bioquímica e urinálise, cardiotocografia e ultrassonografia obstétrica com Doppler. Há centro obstétrico, centro cirúrgico, anestesiologista, neonatologista de plantão e UTI neonatal. Juliana Ferreira dos Santos, 29 anos, sexo feminino, auxiliar de cozinha, ensino médio completo, segunda gestação, com 35 semanas e 1 dia, procura a maternidade por dor de cabeça há 6 horas. Sinais vitais da triagem: PA 168 × 112 mmHg (sentada, braço esquerdo); FC 94 bpm; FR 18 irpm; temperatura axilar 36,6 °C; SpO2 98% em ar ambiente; peso 90 kg.
[TAREFA tarefa-1] Realizar a anamnese dirigida da gestante.
[TAREFA tarefa-2] Solicitar e interpretar o exame físico geral e obstétrico.
[TAREFA tarefa-3] Solicitar e interpretar os exames complementares maternos e de vitalidade fetal.
[TAREFA tarefa-4] Formular a hipótese diagnóstica e prescrever a conduta inicial.
[TAREFA tarefa-5] Orientar a gestante e responder às suas dúvidas.

# 2. ATORES

[ATOR paciente papel=paciente idade=29 voz=feminina-adulta] Juliana Ferreira dos Santos
[PERFIL] Gestante de 29 anos, deitada em decúbito lateral esquerdo, com a mão na testa, incomodada pela luz e ansiosa. Dor de cabeça intensa (nota 8 de 10). Colaborativa, mas assustada ao ouvir falar em parto antecipado. Mora com o companheiro e a filha de 6 anos.
[TOM] Linguagem simples, ensino médio completo; fala baixo por causa da dor de cabeça e pede para apagar a luz forte.
[CONTEXTO] Juliana, 35 semanas e 1 dia, procurou a maternidade por dor de cabeça forte há 6 horas que não melhorou com dipirona. Sinais vitais da chegada: PA 168 × 112 mmHg; FC 94 bpm; FR 18 irpm; temperatura axilar 36,6 °C; SpO2 98%; peso 90 kg.

# 3. ROTEIRO DO ATOR SIMULADO

[TÓPICO] História da doença atual
[FATO cefaleia ator=paciente pep=item-02.criterio-1] A dor de cabeça começou hoje de manhã, umas seis horas atrás, na nuca e na testa, latejando, nota 8. Tomei dipirona 500 mg e não passou.
[FATO escotomas ator=paciente pep=item-02.criterio-2 EXPLÍCITO] Há umas duas horas estou vendo uns pontinhos brilhantes, umas luzinhas piscando, e a vista fica embaçada.
[FATO epigastralgia ator=paciente pep=item-02.criterio-3 EXPLÍCITO] Tenho uma dor na boca do estômago que vai para o lado direito, embaixo das costelas, desde o fim da manhã.
[FATO nauseas ator=paciente pep=item-02.criterio-4] Fiquei enjoada e vomitei uma vez agora à tarde.
[FATO edema ator=paciente] Os pés e as mãos incharam muito nesta última semana; a aliança não entra mais.
[FATO movimentos-fetais ator=paciente pep=item-03.criterio-1] O bebê está mexendo normal, mexeu bastante hoje.
[FATO perda-liquido ator=paciente pep=item-03.criterio-2] Não perdi água pela vagina.
[FATO sangramento ator=paciente pep=item-03.criterio-3] Não tive sangramento.
[FATO contracoes ator=paciente pep=item-03.criterio-4] A barriga endurece de vez em quando, sem dor e sem ritmo.

[TÓPICO] Antecedentes pessoais, obstétricos e vacinais
[FATO gestacoes ator=paciente pep=item-04.criterio-1] É minha segunda gravidez. A primeira filha nasceu há 6 anos, de parto normal, com 39 semanas, pressão normal. Este bebê é do meu atual companheiro.
[FATO pre-natal ator=paciente pep=item-04.criterio-2] Fiz 7 consultas na UBS. A pressão era sempre 110 × 70; na última, há 15 dias, deu 138 × 88 e pediram para repetir em uma semana, mas não consegui ir.
[FATO idade-gestacional ator=paciente] Estou com 35 semanas e 1 dia, pela ultrassonografia de 9 semanas.
[FATO doencas-previas ator=paciente pep=item-04.criterio-3] Não tenho pressão alta fora da gravidez, nem diabetes, doença nos rins, lúpus ou trombose.
[FATO profilaxia ator=paciente pep=item-04.criterio-4 EXPLÍCITO] Não tomei AAS nem cálcio na gravidez; ninguém me passou.
[FATO cirurgias ator=paciente] Nunca fiz cirurgia nem recebi transfusão.
[FATO vacinas ator=paciente] Tomei a dTpa com 28 semanas, a da gripe e completei a hepatite B.
[FATO tipo-sanguineo ator=paciente] Meu sangue é O positivo.

[TÓPICO] Medicações, alergias e hábitos de vida
[FATO medicacoes ator=paciente pep=item-05.criterio-1] Tomo sulfato ferroso 40 mg por dia e hoje tomei dipirona. Não tenho alergia a remédio.
[FATO habitos ator=paciente pep=item-05.criterio-2] Não fumo, não bebo e nunca usei drogas.
[FATO ocupacao-peso ator=paciente] Trabalho em pé o dia todo numa cozinha de restaurante. Antes da gravidez eu pesava 82 kg, com 1,62 m.

[TÓPICO] Histórico familiar
[FATO familia ator=paciente pep=item-05.criterio-3 EXPLÍCITO] Minha mãe teve convulsão no parto do meu irmão, por pressão alta, e hoje é hipertensa.

[REGRA comportamento-no-exame] Durante o exame físico, a atriz se queixa de dor quando o candidato palpa o epigástrio e o hipocôndrio direito e pede para diminuir a luz da sala.

[TÓPICO] Dúvidas obrigatórias da gestante
[PERGUNTA-OBRIGATÓRIA duvida-parto ator=paciente] “Doutor, vou ter que ter o bebê agora? Com 35 semanas ele não é muito pequeno?”
[PERGUNTA-OBRIGATÓRIA duvida-sulfato ator=paciente] “Esse remédio que vai no soro faz mal para mim ou para o bebê?”
[PERGUNTA-OBRIGATÓRIA duvida-futuro ator=paciente] “Isso pode acontecer de novo se eu engravidar? Vou ficar com pressão alta para sempre?”

[CONDUTA-ESPERADA resposta-as-duvidas] Parto: explica que, com sinais de gravidade e 35 semanas, o tratamento definitivo é o nascimento após a estabilização da pressão e o início do sulfato de magnésio, preferencialmente por indução do parto normal; manter a gestação traz risco de convulsão (eclâmpsia), AVC, descolamento prematuro de placenta e síndrome HELLP; o bebê, com peso estimado de 2.380 g, é prematuro tardio, tem bom prognóstico e será recebido pelo neonatologista. Sulfato: explica que o sulfato de magnésio previne convulsões, é seguro para o bebê, pode causar calor, rubor e náusea, e que a equipe vigiará reflexos, respiração e urina, mantendo-o por 24 horas após o parto. Futuro: explica que o risco de pré-eclâmpsia em nova gestação é maior, exigindo pré-natal de alto risco precoce com AAS 100 a 150 mg à noite de 12 a 36 semanas e carbonato de cálcio 1 a 2 g por dia; a pressão costuma normalizar até 12 semanas após o parto, mas há maior risco cardiovascular futuro, com reavaliação em 7 a 10 dias de puerpério e controle anual da pressão.

# 4. IMPRESSOS DISPONÍVEIS NA ESTAÇÃO

[IMPRESSO impresso-1-exame-fisico categoria=exame-fisico] IMPRESSO 1 — EXAME FÍSICO GERAL E OBSTÉTRICO
[LIBERAÇÃO] exame físico; examinar a paciente; exame obstétrico; sinais vitais; aferir a pressão
[CONTEÚDO]
- **Estado geral:** regular estado geral, consciente, orientada, Glasgow 15, corada, hidratada, acianótica, anictérica; fotofobia; sem petéquias ou equimoses.
- **Sinais vitais:** PA 166 × 112 mmHg (sentada, braço esquerdo, manguito adequado); após 15 minutos, 164 × 110 mmHg; FC 92 bpm; FR 18 irpm; temperatura axilar 36,5 °C; SpO2 98%; peso 90 kg.
- **Aparelho cardiovascular:** ritmo cardíaco regular em 2 tempos, sem sopros.
- **Aparelho respiratório:** murmúrio vesicular presente bilateralmente, sem estertores crepitantes ou sibilos.
- **Abdome:** gravídico; dor à palpação profunda do epigástrio e do hipocôndrio direito, sem defesa ou descompressão dolorosa; fígado não palpável.
- **Exame obstétrico:** altura uterina 32 cm; feto único, longitudinal, cefálico, dorso à esquerda; BCF 140 bpm, rítmicos; dinâmica uterina ausente em 10 minutos; tônus uterino normal.
- **Exame especular:** colo epitelizado, sem sangramento ou saída de líquido amniótico.
- **Toque vaginal:** colo posterior, consistência média, 30% apagado, dilatação de 1 cm, apresentação cefálica no plano −2 de De Lee, bolsa íntegra; índice de Bishop 3.
- **Extremidades:** edema 2+/4+ em membros inferiores e mãos; panturrilhas livres.
- **Neurológico:** reflexos patelares vivos (3+/4+), simétricos, sem clônus; força preservada; sem déficit focal; sem rigidez de nuca.

[IMPRESSO impresso-2-hemograma categoria=laboratorio] IMPRESSO 2 — HEMOGRAMA COMPLETO
[LIBERAÇÃO] hemograma; hemograma completo; plaquetas; contagem de plaquetas; esfregaço de sangue periférico
[CONTEÚDO]
- Hemoglobina: 12,1 g/dL. Referência (gestante): 11,0 a 14,0 g/dL.
- Hematócrito: 36%. Referência: 33% a 42%.
- Leucócitos: 10.800/mm³. Referência (gestante): 6.000 a 16.000/mm³.
- Plaquetas: 128.000/mm³. Referência: 150.000 a 450.000/mm³.
- Esfregaço de sangue periférico: ausência de esquizócitos.

[IMPRESSO impresso-3-hepatica categoria=laboratorio] IMPRESSO 3 — ENZIMAS HEPÁTICAS, DESIDROGENASE LÁTICA E BILIRRUBINAS
[LIBERAÇÃO] transaminases; TGO; TGP; AST; ALT; LDH; desidrogenase lática; bilirrubinas; função hepática
[CONTEÚDO]
- AST (TGO): 58 U/L. Referência: até 40 U/L.
- ALT (TGP): 52 U/L. Referência: até 41 U/L.
- Desidrogenase lática (LDH): 410 U/L. Referência: 135 a 225 U/L.
- Bilirrubina total: 0,8 mg/dL. Referência: até 1,2 mg/dL.

[IMPRESSO impresso-4-renal categoria=laboratorio] IMPRESSO 4 — FUNÇÃO RENAL E ÁCIDO ÚRICO
[LIBERAÇÃO] creatinina; ureia; função renal; ácido úrico
[CONTEÚDO]
- Creatinina: 0,9 mg/dL. Referência (gestante): 0,4 a 0,8 mg/dL; sinal de gravidade se acima de 1,1 mg/dL.
- Ureia: 28 mg/dL. Referência: 15 a 40 mg/dL.
- Ácido úrico: 6,4 mg/dL. Referência (gestante): 2,5 a 5,5 mg/dL.

[IMPRESSO impresso-5-proteinuria categoria=laboratorio] IMPRESSO 5 — RELAÇÃO PROTEÍNA/CREATININA URINÁRIA E URINA TIPO 1
[LIBERAÇÃO] relação proteína/creatinina; proteinúria; proteinúria de 24 horas; urina tipo 1; EAS; fita urinária
[CONTEÚDO]
- Relação proteína/creatinina em amostra isolada: 1,6 mg/mg. Referência: inferior a 0,3 mg/mg.
- Urina tipo 1: densidade 1.020; proteínas +++; leucócitos 3 por campo (referência: até 5); hemácias 2 por campo (referência: até 3); nitrito negativo.

[IMPRESSO impresso-6-ctg categoria=imagem] IMPRESSO 6 — CARDIOTOCOGRAFIA ANTEPARTO
[LIBERAÇÃO] cardiotocografia; CTG; monitorização fetal; vitalidade fetal
[CONTEÚDO]
- **Técnica:** traçado de 30 minutos, gestante em decúbito lateral esquerdo.
- **Achados:** linha de base de 140 bpm; variabilidade moderada (10 a 15 bpm); 4 acelerações transitórias de 15 bpm por 15 segundos; ausência de desacelerações; atividade uterina irregular, 1 contração em 10 minutos.
- **Impressão:** traçado categoria I, feto ativo e reativo.

[IMPRESSO impresso-7-usg-doppler categoria=imagem] IMPRESSO 7 — ULTRASSONOGRAFIA OBSTÉTRICA COM DOPPLER
[LIBERAÇÃO] ultrassonografia obstétrica; ultrassom; USG; Doppler obstétrico; dopplervelocimetria; perfil biofísico fetal
[CONTEÚDO]
- **Técnica:** via abdominal, com Doppler colorido e pulsado.
- **Achados:** feto único, cefálico, BCF 142 bpm; peso fetal estimado 2.380 g (percentil 15 para 35 semanas); índice de líquido amniótico 10 cm; placenta posterior, grau II, sem sinais de descolamento; artéria umbilical com índice de pulsatilidade no percentil 50 e diástole presente; artéria cerebral média com índice de pulsatilidade normal; relação cerebroplacentária acima de 1; perfil biofísico 8/8.
- **Impressão:** gestação tópica de 35 semanas, crescimento adequado e Doppler fetoplacentário normal.

# 5. PADRÃO ESPERADO DE PROCEDIMENTO (PEP)

[ITEM item-01] Apresentação e acolhimento
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] subitem (1): apresenta-se com nome e função
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): confirma o nome da gestante e posiciona-a em decúbito lateral esquerdo, reduzindo a luz da sala
[NÍVEL adequado pontos=0,3 mínimo=2] Realiza os 2 critérios.
[NÍVEL parcialmente_adequado pontos=0,15 mínimo=1] Realiza 1 critério.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhum critério.

[ITEM item-02] Anamnese — sintoma principal e sintomas de iminência de eclâmpsia
[CRITÉRIO criterio-1 tipo=PERGUNTA] subitem (1): início, localização, intensidade da cefaleia e resposta à analgesia
[CRITÉRIO criterio-2 tipo=PERGUNTA] subitem (2): alterações visuais (escotomas, turvação visual)
[CRITÉRIO criterio-3 tipo=PERGUNTA] subitem (3): dor epigástrica ou em hipocôndrio direito
[CRITÉRIO criterio-4 tipo=PERGUNTA] subitem (4): náuseas e vômitos
[NÍVEL adequado pontos=0,6 mínimo=3] Investiga 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,3 mínimo=2] Investiga 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-03] Anamnese — queixas obstétricas e vitalidade fetal
[CRITÉRIO criterio-1 tipo=PERGUNTA] subitem (1): movimentação fetal
[CRITÉRIO criterio-2 tipo=PERGUNTA] subitem (2): perda de líquido amniótico
[CRITÉRIO criterio-3 tipo=PERGUNTA] subitem (3): sangramento vaginal
[CRITÉRIO criterio-4 tipo=PERGUNTA] subitem (4): contrações uterinas
[NÍVEL adequado pontos=0,5 mínimo=3] Investiga 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,25 mínimo=2] Investiga 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-04] Anamnese — antecedentes obstétricos, pré-natal e comorbidades
[CRITÉRIO criterio-1 tipo=PERGUNTA] subitem (1): gestações e partos anteriores, com pressão arterial nas gestações prévias e troca de parceiro
[CRITÉRIO criterio-2 tipo=PERGUNTA] subitem (2): número de consultas e valores de pressão arterial no pré-natal
[CRITÉRIO criterio-3 tipo=PERGUNTA] subitem (3): hipertensão crônica, diabetes, doença renal ou lúpus
[CRITÉRIO criterio-4 tipo=PERGUNTA] subitem (4): uso de AAS e cálcio profiláticos na gestação
[NÍVEL adequado pontos=0,6 mínimo=3] Investiga 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,3 mínimo=2] Investiga 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-05] Anamnese — medicações, hábitos e história familiar
[CRITÉRIO criterio-1 tipo=PERGUNTA] subitem (1): medicações em uso e alergias
[CRITÉRIO criterio-2 tipo=PERGUNTA] subitem (2): tabagismo, etilismo e uso de drogas
[CRITÉRIO criterio-3 tipo=PERGUNTA] subitem (3): pré-eclâmpsia, eclâmpsia ou hipertensão na família
[NÍVEL adequado pontos=0,4 mínimo=3] Investiga os 3 critérios.
[NÍVEL parcialmente_adequado pontos=0,2 mínimo=2] Investiga 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-06] Exame físico e verbalização dos achados
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-1-exame-fisico] subitem (1): solicita exame físico geral e obstétrico com nova aferição da pressão arterial
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] subitem (2): verbaliza PA maior ou igual a 160 × 110 mmHg confirmada em duas aferições com intervalo de 15 minutos
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] subitem (3): verbaliza hiper-reflexia patelar (3+/4+) sem clônus e Glasgow 15
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] subitem (4): verbaliza altura uterina de 32 cm, BCF de 140 bpm, ausência de dinâmica uterina e índice de Bishop 3
[CRITÉRIO criterio-5 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] subitem (5): verbaliza dor à palpação do epigástrio e hipocôndrio direito e ausculta pulmonar sem estertores
[NÍVEL adequado pontos=0,9 mínimo=4] Realiza 4 ou 5 critérios.
[NÍVEL parcialmente_adequado pontos=0,45 mínimo=2] Realiza 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza 1 critério ou nenhum.

[ITEM item-07] Solicitação de exames maternos e de vitalidade fetal
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-2-hemograma] subitem (1): solicita hemograma completo com contagem de plaquetas
[CRITÉRIO criterio-2 tipo=SOLICITAÇÃO impressos=impresso-3-hepatica] subitem (2): solicita AST, ALT, LDH e bilirrubinas
[CRITÉRIO criterio-3 tipo=SOLICITAÇÃO impressos=impresso-4-renal] subitem (3): solicita creatinina, ureia e ácido úrico
[CRITÉRIO criterio-4 tipo=SOLICITAÇÃO impressos=impresso-5-proteinuria] subitem (4): solicita relação proteína/creatinina urinária ou proteinúria de 24 horas
[CRITÉRIO criterio-5 tipo=SOLICITAÇÃO impressos=impresso-6-ctg] subitem (5): solicita cardiotocografia
[CRITÉRIO criterio-6 tipo=SOLICITAÇÃO impressos=impresso-7-usg-doppler] subitem (6): solicita ultrassonografia obstétrica com Doppler
[NÍVEL adequado pontos=0,8 mínimo=5] Solicita 5 ou 6 critérios.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=3] Solicita 3 ou 4 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Solicita 2 critérios ou menos.

[ITEM item-08] Interpretação dos exames
[CRITÉRIO criterio-1 tipo=VERBALIZAÇÃO após=impresso-5-proteinuria] subitem (1): verbaliza proteinúria significativa (relação proteína/creatinina de 1,6 mg/mg)
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-2-hemograma,impresso-3-hepatica] subitem (2): verbaliza plaquetas de 128.000/mm³, AST de 58 U/L e LDH de 410 U/L, sem critérios de hemólise ou plaquetopenia abaixo de 100.000/mm³
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-4-renal] subitem (3): verbaliza creatinina de 0,9 mg/dL, sem insuficiência renal
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-6-ctg,impresso-7-usg-doppler] subitem (4): verbaliza vitalidade fetal preservada (cardiotocografia categoria I e Doppler normal)
[NÍVEL adequado pontos=0,8 mínimo=3] Verbaliza 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=2] Verbaliza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Verbaliza 1 critério ou nenhum.

[ITEM item-09] Hipótese diagnóstica
[CRITÉRIO criterio-1 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico OBRIGATÓRIO] subitem (1): formula pré-eclâmpsia com sinais de gravidade
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): reconhece iminência de eclâmpsia (cefaleia, escotomas e epigastralgia)
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-2-hemograma,impresso-3-hepatica] subitem (3): afasta síndrome HELLP
[NÍVEL adequado pontos=1,0 mínimo=3] Realiza os 3 critérios.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=1] Formula a hipótese principal com 1 ou nenhum critério adicional.
[NÍVEL inadequado pontos=0 mínimo=0] Não formula pré-eclâmpsia com sinais de gravidade.

[ITEM item-10] Prevenção da eclâmpsia com sulfato de magnésio
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] subitem (1): prescreve sulfato de magnésio, dose de ataque de 4 g IV em 20 minutos (esquema de Zuspan)
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): prescreve manutenção de 1 g/h IV em bomba de infusão até 24 horas após o parto
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] subitem (3): monitora reflexo patelar presente, FR maior ou igual a 16 irpm e diurese maior ou igual a 25 mL/h
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] subitem (4): deixa gluconato de cálcio 10%, 10 mL IV em 3 minutos, disponível como antídoto
[CRITÉRIO criterio-5 tipo=COMUNICAÇÃO PROIBIDO] prescreve diazepam ou fenitoína no lugar do sulfato de magnésio
[NÍVEL adequado pontos=1,2 mínimo=3] Realiza 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,6 mínimo=2] Realiza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Não prescreve sulfato de magnésio ou prescreve diazepam ou fenitoína em seu lugar.

[ITEM item-11] Tratamento da crise hipertensiva
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] subitem (1): prescreve hidralazina 5 mg IV a cada 20 minutos (máximo 30 mg) ou nifedipina 10 mg VO a cada 20 a 30 minutos (máximo 30 mg)
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): define alvo de PA sistólica entre 140 e 150 mmHg e diastólica entre 90 e 100 mmHg, evitando queda brusca
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] subitem (3): reafere a PA e ausculta o BCF a cada 20 minutos durante o tratamento
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO PROIBIDO] prescreve nifedipina sublingual ou inibidor da ECA (captopril, enalapril)
[NÍVEL adequado pontos=1,0 mínimo=3] Realiza os 3 critérios.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=1] Prescreve o anti-hipertensivo com 1 ou nenhum critério adicional.
[NÍVEL inadequado pontos=0 mínimo=0] Não prescreve anti-hipertensivo ou realiza a conduta proibida.

[ITEM item-12] Resolução da gestação e medidas de suporte
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] subitem (1): indica a interrupção da gestação após estabilização materna
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): indica via vaginal com indução por misoprostol 25 mcg via vaginal a cada 6 horas (Bishop 3), cesárea só por indicação obstétrica
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] subitem (3): solicita sonda vesical de demora com diurese horária, acesso venoso calibroso e comunica anestesiologia e neonatologia
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] subitem (4): interna no centro obstétrico com cardiotocografia contínua
[CRITÉRIO criterio-5 tipo=COMUNICAÇÃO PROIBIDO] indica conduta expectante até 37 semanas ou alta hospitalar
[NÍVEL adequado pontos=0,7 mínimo=3] Realiza 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,35 mínimo=2] Realiza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Não indica a resolução ou realiza a conduta proibida.

[ITEM item-13] Comunicação e Resolução de Dúvidas
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO perguntas=duvida-parto] subitem (1): explica a necessidade do parto após estabilização, os riscos maternos de manter a gestação e o bom prognóstico do prematuro tardio
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO perguntas=duvida-sulfato] subitem (2): explica que o sulfato de magnésio previne convulsões, é seguro para o bebê e será vigiado pela equipe
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO perguntas=duvida-futuro] subitem (3): explica risco de recorrência, AAS 100 a 150 mg e cálcio na próxima gestação e acompanhamento da pressão no puerpério
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] subitem (4): mantém postura empática e linguagem acessível, sem jargões
[NÍVEL adequado pontos=1,2 mínimo=4] Cumpre os 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,6 mínimo=2] Cumpre 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Cumpre 1 critério ou nenhum.
