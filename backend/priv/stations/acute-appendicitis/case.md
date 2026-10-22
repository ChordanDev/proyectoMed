# ESTAÇÃO

[ESTAÇÃO acute-appendicitis]
[ÁREA] Cirurgia Geral
[TEMA] Abdome agudo inflamatório — apendicite aguda
[PROVISÓRIO] sim

# 1. CENÁRIO DE ATUAÇÃO E INSTRUÇÕES AO PARTICIPANTE

[CENÁRIO] Você é o médico ou a médica de plantão em um pronto-socorro de hospital geral. Rafael Nogueira, 27 anos, auxiliar administrativo, chega sem acompanhante e procura atendimento por dor abdominal.

[TAREFA tarefa-1] Apresentar-se, confirmar a identificação do paciente e obter anamnese dirigida.
[TAREFA tarefa-2] Solicitar e interpretar o exame físico abdominal e as manobras pertinentes.
[TAREFA tarefa-3] Solicitar e interpretar exames laboratoriais e de imagem adequados ao caso.
[TAREFA tarefa-4] Formular a hipótese diagnóstica principal e indicar medidas de suporte e tratamento inicial.
[TAREFA tarefa-5] Explicar a necessidade de avaliação cirúrgica e tratamento definitivo, respondendo às dúvidas do paciente.

# 2. ATORES

[ATOR paciente papel=paciente idade=27 voz=masculina-adulta] Rafael Nogueira
[PERFIL] Rafael está sentado na maca, um pouco curvado e com expressão de desconforto. Responde às perguntas, mas evita movimentar o tronco por causa da dor. Não está agitado nem confuso. Demonstra preocupação com a possibilidade de cirurgia e com o tempo de recuperação.
[TOM] Fala em português claro, com escolaridade compatível com ensino médio completo.
[CONTEXTO] Você está atendendo Rafael Nogueira, 27 anos, auxiliar administrativo, sem acompanhante. Ele procura o pronto-socorro por dor abdominal iniciada há cerca de 18 horas. Está consciente, orientado e hemodinamicamente estável. Na chegada, apresenta pressão arterial de 126/78 mmHg, frequência cardíaca de 102 bpm, frequência respiratória de 18 irpm, temperatura axilar de 38,1 °C e saturação periférica de oxigênio de 98% em ar ambiente. Refere dor atual de intensidade 7/10.

# 3. ROTEIRO DO ATOR SIMULADO

[TÓPICO] HDA — respostas padronizadas
[FATO hda-01 ator=paciente pep=item-02.criterio-1] A dor começou ao redor do umbigo.
[FATO hda-01-migracao ator=paciente pep=item-02.criterio-2] Há cerca de 10 horas, a dor migrou para a parte inferior direita do abdome.
[FATO hda-01-tempo ator=paciente pep=item-02.criterio-4] A dor começou há 18 horas.
[FATO hda-02 ator=paciente pep=item-02.criterio-3] É uma dor contínua.
[FATO hda-02-progressao ator=paciente pep=item-02.criterio-3] A dor foi aumentando progressivamente.
[FATO hda-02-intensidade ator=paciente pep=item-02.criterio-5] Atualmente, a dor é 7/10.
[FATO hda-03 ator=paciente pep=item-02.criterio-6] Piora ao caminhar, tossir ou mudar de posição. Não encontrou posição ou medida que alivie significativamente.
[FATO hda-04 ator=paciente pep=item-03.criterio-2] Teve náusea e vomitou uma vez, sem sangue ou bile.
[FATO hda-05 ator=paciente pep=item-03.criterio-3] Refere falta de apetite desde o início do quadro.
[FATO hda-06 ator=paciente pep=item-03.criterio-1] Mediu a temperatura em casa e teve “febre baixa”.
[FATO hda-06-antitermico ator=paciente pep=item-03.criterio-1] Não tomou antitérmico.
[FATO hda-07 ator=paciente pep=item-03.criterio-4] Evacuou no dia anterior e eliminou gases hoje. Nega diarreia e constipação importante.
[FATO hda-08 ator=paciente pep=item-03.criterio-5] Nega ardor ao urinar, urgência, aumento da frequência urinária ou sangue na urina.
[FATO hda-09 ator=paciente pep=item-03.criterio-6] Nega dor testicular ou secreção uretral.

[TÓPICO] Antecedentes, medicações e hábitos — respostas padronizadas
[FATO antecedentes-01 ator=paciente pep=item-04.criterio-1] Nega doenças crônicas.
[FATO antecedentes-01-internacoes-cirurgias ator=paciente pep=item-04.criterio-2] Nega internações anteriores e cirurgias.
[FATO antecedentes-02 ator=paciente pep=item-04.criterio-3] Não usa medicamentos regularmente.
[FATO antecedentes-03 ator=paciente pep=item-04.criterio-4] Nega alergias medicamentosas conhecidas.
[FATO antecedentes-04 ator=paciente] Nega tabagismo e uso de drogas; refere consumo ocasional de bebida alcoólica.
[FATO antecedentes-05 ator=paciente] Mora com a companheira; trabalha em escritório. Não há informação adicional relevante sobre histórico familiar, a menos que perguntado.

[TÓPICO] Informações que o ator só revela se o candidato perguntar explicitamente
[FATO pergunta-explicita-01 ator=paciente EXPLÍCITO] Nega episódio semelhante anterior.
[FATO pergunta-explicita-02 ator=paciente pep=item-04.criterio-5 EXPLÍCITO] Nega uso recente de antibióticos ou anticoagulantes.
[FATO pergunta-explicita-02-anti-inflamatorios ator=paciente pep=item-04.criterio-3 EXPLÍCITO] Nega uso recente de anti-inflamatórios.
[FATO pergunta-explicita-03 ator=paciente pep=item-03.criterio-6 EXPLÍCITO] Nega dor lombar, icterícia, dor no peito, falta de ar ou síncope.
[FATO pergunta-explicita-04 ator=paciente EXPLÍCITO] Nega perda de peso ou alteração intestinal persistente nas últimas semanas.
[FATO pergunta-explicita-05 ator=paciente EXPLÍCITO] Se perguntado sobre hidratação e ingestão oral, relata que bebeu água pela última vez há duas horas, mas não conseguiu se alimentar desde a manhã.

[REGRA comportamento-durante-o-exame] Se o candidato explicar o que fará e pedir autorização, o paciente coopera, mas refere piora da dor à palpação no quadrante inferior direito. Se o candidato fizer palpação brusca sem explicar, o ator demonstra desconforto e contrai a musculatura.

[TÓPICO] Dúvidas obrigatórias do ator nos minutos finais
[PERGUNTA-OBRIGATÓRIA duvida-final-01 ator=paciente] “Doutor, isso pode ser tratado só com remédio, sem cirurgia?”
[PERGUNTA-OBRIGATÓRIA duvida-final-02 ator=paciente] “Se eu precisar operar, quanto tempo vou ficar internado e quando posso voltar ao trabalho?”

[CONDUTA-ESPERADA resposta-as-duvidas-do-paciente] O candidato deve responder com empatia, explicar que o quadro e a imagem sugerem apendicite e que a equipe cirúrgica precisa avaliar prontamente a conduta definitiva. Deve esclarecer que a apendicectomia é o tratamento habitual, que antibióticos isolados não são a opção padrão para todos os casos e que duração da internação e retorno ao trabalho dependem da evolução, da técnica utilizada e de eventual complicação.

# 4. IMPRESSOS DISPONÍVEIS NA ESTAÇÃO

[IMPRESSO impresso-1-exame-fisico categoria=exame-fisico] IMPRESSO 1 — EXAME FÍSICO SEGMENTAR
[LIBERAÇÃO] exame físico; exame segmentar; exame do abdome; exame abdominal; examinar o abdome; examinar a barriga; examinar o paciente; palpação abdominal; palpação do abdome; palpar o abdome; palpar a barriga; sinais vitais
[CONTEÚDO]
- **Estado geral:** regular, consciente, orientado, fácies de dor; hidratado, sem cianose ou icterícia.
- **Sinais vitais no exame:** PA 126/78 mmHg; FC 102 bpm; FR 18 irpm; temperatura 38,1 °C; SpO₂ 98% em ar ambiente.
- **Aparelho cardiovascular:** bulhas normofonéticas, ritmo regular, sem sopros.
- **Aparelho respiratório:** murmúrio vesicular presente bilateralmente, sem ruídos adventícios.
- **Abdome — inspeção:** plano, sem cicatrizes, distensão, equimoses ou circulação colateral; movimentação reduzida durante a respiração profunda.
- **Ausculta:** ruídos hidroaéreos presentes, discretamente diminuídos; sem sopros.
- **Percussão:** timpanismo predominante; sem macicez anormal.
- **Palpação superficial:** dor localizada no quadrante inferior direito, com defesa voluntária discreta.
- **Palpação profunda:** dor acentuada na fossa ilíaca direita, especialmente no ponto de McBurney. Descompressão brusca dolorosa na fossa ilíaca direita: sinal de Blumberg positivo.
- **Manobras:** sinal de Rovsing positivo; sinal do psoas negativo; sinal do obturador negativo. Sem dor à punho-percussão lombar.
- **Neurológico:** alerta, orientado em tempo, espaço e pessoa; sem déficit motor grosseiro.
- **Geniturinário:** sem dor testicular à inspeção referida; não é necessário exame genital invasivo na ausência de indicação clínica.

[IMPRESSO impresso-2-hemograma categoria=laboratorio] IMPRESSO 2 — EXAMES LABORATORIAIS — Hemograma completo
[LIBERAÇÃO] hemograma; leucograma
[CONTEÚDO]
**Hemograma completo:**

- Hemoglobina: 14,6 g/dL. Referência adulto masculino: 13,0–17,0 g/dL.
- Hematócrito: 43%. Referência adulto masculino: 40–52%.
- Leucócitos: 15.800/mm³. Referência: 4.000–11.000/mm³.
- Neutrófilos: 86%; bastonetes: 8%. Referências usuais: neutrófilos segmentados 40–75%; bastonetes 0–5%.
- Plaquetas: 268.000/mm³. Referência: 150.000–450.000/mm³.

[IMPRESSO impresso-2-pcr categoria=laboratorio] IMPRESSO 2 — EXAMES LABORATORIAIS — PCR
[LIBERAÇÃO] PCR; proteína C-reativa; proteína C reativa
[CONTEÚDO]
**Inflamação e função renal/metabólica:**

- PCR: 86 mg/L. Referência: inferior a 5 mg/L.

[IMPRESSO impresso-2-eletrolitos categoria=laboratorio] IMPRESSO 2 — EXAMES LABORATORIAIS — Sódio, Potássio
[LIBERAÇÃO] eletrólitos; sódio; potássio; ionograma
[CONTEÚDO]
**Inflamação e função renal/metabólica:**

- Sódio: 138 mmol/L. Referência: 135–145 mmol/L.
- Potássio: 4,1 mmol/L. Referência: 3,5–5,1 mmol/L.

[IMPRESSO impresso-2-ureia categoria=laboratorio] IMPRESSO 2 — EXAMES LABORATORIAIS — Ureia
[LIBERAÇÃO] ureia; função renal
[CONTEÚDO]
**Inflamação e função renal/metabólica:**

- Ureia: 28 mg/dL. Referência: 15–45 mg/dL.

[IMPRESSO impresso-2-creatinina categoria=laboratorio] IMPRESSO 2 — EXAMES LABORATORIAIS — Creatinina
[LIBERAÇÃO] creatinina; função renal
[CONTEÚDO]
**Inflamação e função renal/metabólica:**

- Creatinina: 0,9 mg/dL. Referência adulto masculino: 0,7–1,3 mg/dL.

[IMPRESSO impresso-2-glicemia categoria=laboratorio] IMPRESSO 2 — EXAMES LABORATORIAIS — Glicemia
[LIBERAÇÃO] glicemia; glicose
[CONTEÚDO]
**Inflamação e função renal/metabólica:**

- Glicemia: 104 mg/dL. Referência em jejum: 70–99 mg/dL.

[IMPRESSO impresso-2-urina-tipo-1 categoria=laboratorio] IMPRESSO 2 — EXAMES LABORATORIAIS — Urina tipo 1 (EAS)
[LIBERAÇÃO] urina tipo 1; urina tipo I; urina 1; EAS; exame de urina; sumário de urina; parcial de urina; urinálise
[CONTEÚDO]
**Urina tipo 1 (EAS):**

- Densidade: 1,020; pH: 6,0.
- Nitrito negativo; esterase leucocitária negativa.
- Leucócitos: 2/campo; hemácias: 1/campo.
- Sem bacteriúria significativa, proteinúria ou cetonúria relevante.

[IMPRESSO impresso-3-exame-de-imagem categoria=imagem] IMPRESSO 3 — EXAME DE IMAGEM
[LIBERAÇÃO] ultrassonografia de abdome e pelve; tomografia computadorizada de abdome e pelve; ultrassonografia; ultrassom; USG; ecografia; TC de abdome; TC do abdome; TC abdominal; tomografia de abdome; tomografia do abdome; tomografia abdominal; tomografia computadorizada de abdome; tomografia computadorizada do abdome; exame de imagem
[CONTEÚDO]
**Tomografia computadorizada de abdome e pelve com contraste intravenoso:**

- Apêndice cecal em posição habitual, com diâmetro externo máximo de 10 mm, espessamento parietal e realce mucoso.
- Presença de densificação da gordura periapendicular e pequena quantidade de líquido adjacente.
- Apendicolito de 5 mm no interior do apêndice.
- Sem pneumoperitônio, abscesso organizado, coleção ou sinais de perfuração.
- Sem dilatação de alças ou sinais de obstrução intestinal.
- Rins sem hidronefrose; bexiga sem alteração relevante.

**Conclusão:** achados compatíveis com apendicite aguda, sem evidência tomográfica de perfuração ou abscesso.

[IMPRESSO impresso-4-receituario categoria=registro] IMPRESSO 4 — RECEITUÁRIO/REGISTRO DE CONDUTA INICIAL
[LIBERAÇÃO]
[CONTEÚDO]
Para adulto sem alergia conhecida e função renal preservada, são opções adequadas:

- Jejum oral.
- Acesso venoso periférico e cristaloide intravenoso conforme estado de hidratação e resposta clínica; por exemplo, Ringer lactato ou cloreto de sódio 0,9%, com reavaliação.
- Dipirona 1 g intravenosa a cada 6 horas, se necessário, respeitando contraindicações e dose máxima diária.
- Ondansetrona 4 mg intravenosa a cada 8 horas, se necessário.
- Antibiótico intravenoso perioperatório conforme protocolo institucional e avaliação da equipe cirúrgica; opção: ceftriaxona 2 g IV associada a metronidazol 500 mg IV, com ajuste em caso de alergia, função renal alterada ou outra particularidade clínica.
- Avaliação imediata pela cirurgia geral. Não atrasar encaminhamento para avaliação cirúrgica enquanto se aguarda resposta a tratamento sintomático.

# 5. PADRÃO ESPERADO DE PROCEDIMENTO (PEP)

[ITEM item-01] Apresentação e identificação
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Identifica-se
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] Cumprimenta o paciente e confirma seu nome
[NÍVEL adequado pontos=0,2 mínimo=2] Realiza as duas ações.
[NÍVEL parcialmente_adequado pontos=0,1 mínimo=1] Realiza uma ação.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma ação.

[ITEM item-02] Anamnese — caracterização da dor
[CRITÉRIO criterio-1 tipo=PERGUNTA] Localização inicial
[CRITÉRIO criterio-2 tipo=PERGUNTA] migração para fossa ilíaca direita
[CRITÉRIO criterio-3 tipo=PERGUNTA] caráter e progressão
[CRITÉRIO criterio-4 tipo=PERGUNTA] tempo de evolução
[CRITÉRIO criterio-5 tipo=PERGUNTA] intensidade
[CRITÉRIO criterio-6 tipo=PERGUNTA] fatores de piora ou melhora
[NÍVEL adequado pontos=0,8 mínimo=5] Investiga cinco ou seis características.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=3] Investiga três ou quatro características.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga duas ou menos características.

[ITEM item-03] Anamnese — sintomas associados e diagnósticos diferenciais
[CRITÉRIO criterio-1 tipo=PERGUNTA] Febre
[CRITÉRIO criterio-2 tipo=PERGUNTA] náuseas ou vômitos
[CRITÉRIO criterio-3 tipo=PERGUNTA] apetite
[CRITÉRIO criterio-4 tipo=PERGUNTA] hábito intestinal e eliminação de gases
[CRITÉRIO criterio-5 tipo=PERGUNTA] sintomas urinários
[CRITÉRIO criterio-6 tipo=PERGUNTA] sintomas genitais ou outros sinais de alarme
[NÍVEL adequado pontos=0,8 mínimo=4] Investiga pelo menos quatro dos seis grupos de sintomas.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=2] Investiga dois ou três grupos.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga um grupo ou nenhum.

[ITEM item-04] Antecedentes, medicamentos e alergias
[CRITÉRIO criterio-1 tipo=PERGUNTA] Comorbidades
[CRITÉRIO criterio-2 tipo=PERGUNTA] cirurgias ou internações prévias
[CRITÉRIO criterio-3 tipo=PERGUNTA] medicamentos de uso habitual ou recente
[CRITÉRIO criterio-4 tipo=PERGUNTA] alergias medicamentosas
[CRITÉRIO criterio-5 tipo=PERGUNTA] uso de anticoagulantes ou antibióticos recentes
[NÍVEL adequado pontos=0,6 mínimo=4] Investiga quatro ou cinco itens.
[NÍVEL parcialmente_adequado pontos=0,3 mínimo=2] Investiga dois ou três itens.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga um item ou nenhum.

[ITEM item-05] Exame físico abdominal e manobras
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Explica o exame e solicita autorização, com paciente em decúbito dorsal
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] verbaliza dor à palpação profunda no ponto de McBurney/fossa ilíaca direita
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] pesquisa e interpreta o sinal de Blumberg
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] pesquisa ao menos uma manobra entre Rovsing, psoas e obturador
[NÍVEL adequado pontos=1,2 mínimo=3] Realiza ou solicita corretamente três ou quatro ações.
[NÍVEL parcialmente_adequado pontos=0,6 mínimo=2] Realiza ou solicita corretamente duas ações.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza ou solicita uma ação ou nenhuma.

[ITEM item-06] Solicitação de exames laboratoriais
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-2-hemograma] Hemograma completo
[CRITÉRIO criterio-2 tipo=SOLICITAÇÃO impressos=impresso-2-pcr] PCR
[CRITÉRIO criterio-3 tipo=SOLICITAÇÃO impressos=impresso-2-urina-tipo-1] urina tipo 1
[CRITÉRIO criterio-4 tipo=SOLICITAÇÃO impressos=impresso-2-ureia,impresso-2-creatinina,impresso-2-eletrolitos] função renal e eletrólitos, especialmente se houver necessidade de contraste ou hidratação
[NÍVEL adequado pontos=0,8 mínimo=3] Solicita três ou quatro grupos pertinentes.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=2] Solicita dois grupos.
[NÍVEL inadequado pontos=0 mínimo=0] Solicita um grupo ou nenhum.

[ITEM item-07] Interpretação laboratorial
[CRITÉRIO criterio-1 tipo=VERBALIZAÇÃO após=impresso-2-hemograma] Identifica leucocitose com neutrofilia e desvio à esquerda
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-2-pcr] reconhece PCR elevada
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-2-urina-tipo-1] interpreta EAS sem evidências de infecção urinária
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-2-ureia,impresso-2-creatinina,impresso-2-eletrolitos] considera função renal e eletrólitos preservados
[CRITÉRIO atribuicao-a-infeccao-urinaria tipo=COMUNICAÇÃO PROIBIDO] atribui incorretamente o quadro a infecção urinária
[NÍVEL adequado pontos=0,8 mínimo=3] Interpreta corretamente três ou quatro achados.
[NÍVEL parcialmente_adequado pontos=0,4 mínimo=2] Interpreta corretamente dois achados.
[NÍVEL inadequado pontos=0 mínimo=0] Interpreta um achado ou nenhum, ou atribui incorretamente o quadro a infecção urinária.

[ITEM item-08] Solicitação e interpretação de imagem e hipótese diagnóstica
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-3-exame-de-imagem] Solicita imagem adequada, considerando TC ou ultrassonografia conforme disponibilidade e contexto
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-3-exame-de-imagem] identifica apêndice dilatado, espessamento parietal e inflamação periapendicular
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-3-exame-de-imagem] reconhece ausência de abscesso ou perfuração
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-3-exame-de-imagem OBRIGATÓRIO] formula a hipótese de apendicite aguda
[NÍVEL adequado pontos=1,4 mínimo=4] Cumpre os quatro critérios.
[NÍVEL parcialmente_adequado pontos=0,7 mínimo=1] Formula a hipótese diagnóstica principal, mas falha em interpretar um ou mais achados da imagem.
[NÍVEL inadequado pontos=0 mínimo=0] Não formula apendicite aguda como hipótese principal.

[ITEM item-09] Medidas de suporte e preparo inicial
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Mantém jejum oral
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] estabelece acesso venoso e indica cristaloide conforme avaliação clínica, com reavaliação
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] prescreve analgesia apropriada
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] prescreve antiemético se necessário
[CRITÉRIO criterio-5 tipo=COMUNICAÇÃO] monitora sinais vitais e evolução clínica
[NÍVEL adequado pontos=1,2 mínimo=4] Indica quatro ou cinco medidas.
[NÍVEL parcialmente_adequado pontos=0,6 mínimo=2] Indica duas ou três medidas.
[NÍVEL inadequado pontos=0 mínimo=0] Indica uma medida ou nenhuma.

[ITEM item-10] Antibiótico e articulação com equipe cirúrgica
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Solicita avaliação imediata da cirurgia geral
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] indica antibiótico intravenoso perioperatório conforme protocolo e sem retardar a avaliação cirúrgica
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] propõe cobertura para bacilos gram-negativos e anaeróbios, como ceftriaxona associada a metronidazol
[NÍVEL adequado pontos=1,2 mínimo=3] Cumpre os três critérios.
[NÍVEL parcialmente_adequado pontos=0,6 mínimo=2] Cumpre dois critérios ou prescreve antibiótico sem contemplar cobertura adequada para anaeróbios.
[NÍVEL inadequado pontos=0 mínimo=0] Não solicita avaliação cirúrgica nem indica conduta antimicrobiana pertinente.

[ITEM item-11] Conduta definitiva, consentimento e comunicação
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] Indica avaliação para apendicectomia em caráter de urgência e encaminhamento à equipe/centro cirúrgico
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] explica o diagnóstico provável, a finalidade da cirurgia e que a conduta definitiva depende de avaliação cirúrgica
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO perguntas=duvida-final-01,duvida-final-02] responde às duas dúvidas do paciente com clareza, empatia e informação compatível com a evolução clínica
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] menciona obtenção de consentimento livre e esclarecido pela equipe responsável antes do procedimento, quando aplicável
[NÍVEL adequado pontos=1,0 mínimo=3] Cumpre três ou quatro critérios.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Cumpre dois critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Cumpre um critério ou nenhum.
