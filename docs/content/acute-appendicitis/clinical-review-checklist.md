# Acute appendicitis: clinical review checklist

**The station stays `placeholder: true` until a qualified human completes this checklist. No clinical accuracy claim is made:** the package was transcribed from the Content Partner's source by a transcriber with no clinical authority, and nothing below has been clinically reviewed.

| | |
|---|---|
| Package | `backend/priv/stations/acute-appendicitis/package.json` |
| Source | `docs/content/acute-appendicitis/partner-source.pt-BR.md` |
| Mapping, derived fields, gaps | `docs/content/acute-appendicitis/package-mapping.md` |
| Review status | Not started. Every row is unchecked. |

## How to review

1. Compare each row with the source and with your clinical judgement.
2. Tick **Confirmed**, or tick **Change requested** and describe the change in the notes at the end.
3. Write your name and the date on every row you decide.
4. Decide every gap (section 7) and every derived field (section 8).
5. Sign section 9. Only then may a human set `placeholder` to `false`.

Rows are generated from the package. If the package changes, this checklist must be regenerated and reviewed again.

## 1. Station identity and patient profile

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `station_id` | acute-appendicitis | [ ] | [ ] | | |
| `version` | 2.0.0 | [ ] | [ ] | | |
| `language` | pt-BR | [ ] | [ ] | | |
| `display_title` | Abdome agudo inflamatório — apendicite aguda | [ ] | [ ] | | |
| `placeholder` | `true` | [ ] | [ ] | | |
| `patient_profile.persona` | Rafael está sentado na maca, um pouco curvado e com expressão de desconforto. Responde às perguntas, mas evita movimentar o tronco por causa da dor. Não está agitado nem confuso. Demonstra preocupação com a possibilidade de cirurgia e com o tempo de recuperação. | [ ] | [ ] | | |
| `patient_profile.age` | `27` | [ ] | [ ] | | |
| `patient_profile.presenting_context` | Você está atendendo Rafael Nogueira, 27 anos, auxiliar administrativo, sem acompanhante. Ele procura o pronto-socorro por dor abdominal iniciada há cerca de 18 horas. Está consciente, orientado e hemodinamicamente estável. Na chegada, apresenta pressão arterial de 126/78 mmHg, frequência cardíaca de 102 bpm, frequência respiratória de 18 irpm, temperatura axilar de 38,1 °C e saturação periférica de oxigênio de 98% em ar ambiente. Refere dor atual de intensidade 7/10. | [ ] | [ ] | | |
| `patient_profile.tone` | Fala em português claro, com escolaridade compatível com ensino médio completo. | [ ] | [ ] | | |

## 2. Revealable facts

| Fact id | Topic | Content | Disclosure condition | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|---|---|
| `hda-01` | HDA — respostas padronizadas | A dor começou ao redor do umbigo. | `on_request` | [ ] | [ ] | | |
| `hda-01-migracao` | HDA — respostas padronizadas | Há cerca de 10 horas, a dor migrou para a parte inferior direita do abdome. | `on_request` | [ ] | [ ] | | |
| `hda-01-tempo` | HDA — respostas padronizadas | A dor começou há 18 horas. | `on_request` | [ ] | [ ] | | |
| `hda-02` | HDA — respostas padronizadas | É uma dor contínua. | `on_request` | [ ] | [ ] | | |
| `hda-02-progressao` | HDA — respostas padronizadas | A dor foi aumentando progressivamente. | `on_request` | [ ] | [ ] | | |
| `hda-02-intensidade` | HDA — respostas padronizadas | Atualmente, a dor é 7/10. | `on_request` | [ ] | [ ] | | |
| `hda-03` | HDA — respostas padronizadas | Piora ao caminhar, tossir ou mudar de posição. Não encontrou posição ou medida que alivie significativamente. | `on_request` | [ ] | [ ] | | |
| `hda-04` | HDA — respostas padronizadas | Teve náusea e vomitou uma vez, sem sangue ou bile. | `on_request` | [ ] | [ ] | | |
| `hda-05` | HDA — respostas padronizadas | Refere falta de apetite desde o início do quadro. | `on_request` | [ ] | [ ] | | |
| `hda-06` | HDA — respostas padronizadas | Mediu a temperatura em casa e teve “febre baixa”. | `on_request` | [ ] | [ ] | | |
| `hda-06-antitermico` | HDA — respostas padronizadas | Não tomou antitérmico. | `on_request` | [ ] | [ ] | | |
| `hda-07` | HDA — respostas padronizadas | Evacuou no dia anterior e eliminou gases hoje. Nega diarreia e constipação importante. | `on_request` | [ ] | [ ] | | |
| `hda-08` | HDA — respostas padronizadas | Nega ardor ao urinar, urgência, aumento da frequência urinária ou sangue na urina. | `on_request` | [ ] | [ ] | | |
| `hda-09` | HDA — respostas padronizadas | Nega dor testicular ou secreção uretral. | `on_request` | [ ] | [ ] | | |
| `antecedentes-01` | Antecedentes, medicações e hábitos — respostas padronizadas | Nega doenças crônicas. | `on_request` | [ ] | [ ] | | |
| `antecedentes-01-internacoes-cirurgias` | Antecedentes, medicações e hábitos — respostas padronizadas | Nega internações anteriores e cirurgias. | `on_request` | [ ] | [ ] | | |
| `antecedentes-02` | Antecedentes, medicações e hábitos — respostas padronizadas | Não usa medicamentos regularmente. | `on_request` | [ ] | [ ] | | |
| `antecedentes-03` | Antecedentes, medicações e hábitos — respostas padronizadas | Nega alergias medicamentosas conhecidas. | `on_request` | [ ] | [ ] | | |
| `antecedentes-04` | Antecedentes, medicações e hábitos — respostas padronizadas | Nega tabagismo e uso de drogas; refere consumo ocasional de bebida alcoólica. | `on_request` | [ ] | [ ] | | |
| `antecedentes-05` | Antecedentes, medicações e hábitos — respostas padronizadas | Mora com a companheira; trabalha em escritório. Não há informação adicional relevante sobre histórico familiar, a menos que perguntado. | `on_request` | [ ] | [ ] | | |
| `pergunta-explicita-01` | Informações que o ator só revela se o candidato perguntar explicitamente | Nega episódio semelhante anterior. | `on_request` | [ ] | [ ] | | |
| `pergunta-explicita-02` | Informações que o ator só revela se o candidato perguntar explicitamente | Nega uso recente de antibióticos ou anticoagulantes. | `on_request` | [ ] | [ ] | | |
| `pergunta-explicita-02-anti-inflamatorios` | Informações que o ator só revela se o candidato perguntar explicitamente | Nega uso recente de anti-inflamatórios. | `on_request` | [ ] | [ ] | | |
| `pergunta-explicita-03` | Informações que o ator só revela se o candidato perguntar explicitamente | Nega dor lombar, icterícia, dor no peito, falta de ar ou síncope. | `on_request` | [ ] | [ ] | | |
| `pergunta-explicita-04` | Informações que o ator só revela se o candidato perguntar explicitamente | Nega perda de peso ou alteração intestinal persistente nas últimas semanas. | `on_request` | [ ] | [ ] | | |
| `pergunta-explicita-05` | Informações que o ator só revela se o candidato perguntar explicitamente | Se perguntado sobre hidratação e ingestão oral, relata que bebeu água pela última vez há duas horas, mas não conseguiu se alimentar desde a manhã. | `on_request` | [ ] | [ ] | | |
| `duvida-final-01` | Dúvidas obrigatórias do ator nos minutos finais | “Doutor, isso pode ser tratado só com remédio, sem cirurgia?” | `timed` | [ ] | [ ] | | |
| `duvida-final-02` | Dúvidas obrigatórias do ator nos minutos finais | “Se eu precisar operar, quanto tempo vou ficar internado e quando posso voltar ao trabalho?” | `timed` | [ ] | [ ] | | |

## 3. Response rules and expected actions

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `response_rules.comportamento-durante-o-exame` | Se o candidato explicar o que fará e pedir autorização, o paciente coopera, mas refere piora da dor à palpação no quadrante inferior direito. Se o candidato fizer palpação brusca sem explicar, o ator demonstra desconforto e contrai a musculatura. | [ ] | [ ] | | |
| `expected_actions.tarefa-1` | Apresentar-se, confirmar a identificação do paciente e obter anamnese dirigida. | [ ] | [ ] | | |
| `expected_actions.tarefa-2` | Solicitar e interpretar o exame físico abdominal e as manobras pertinentes. | [ ] | [ ] | | |
| `expected_actions.tarefa-3` | Solicitar e interpretar exames laboratoriais e de imagem adequados ao caso. | [ ] | [ ] | | |
| `expected_actions.tarefa-4` | Formular a hipótese diagnóstica principal e indicar medidas de suporte e tratamento inicial. | [ ] | [ ] | | |
| `expected_actions.tarefa-5` | Explicar a necessidade de avaliação cirúrgica e tratamento definitivo, respondendo às dúvidas do paciente. | [ ] | [ ] | | |
| `expected_actions.resposta-as-duvidas-do-paciente` | O candidato deve responder com empatia, explicar que o quadro e a imagem sugerem apendicite e que a equipe cirúrgica precisa avaliar prontamente a conduta definitiva. Deve esclarecer que a apendicectomia é o tratamento habitual, que antibióticos isolados não são a opção padrão para todos os casos e que duração da internação e retorno ao trabalho dependem da evolução, da técnica utilizada e de eventual complicação. | [ ] | [ ] | | |

## 4. Approved templates

The package authors no approved template, so there is no applicability predicate to review.

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `approved_templates` | `null` | [ ] | [ ] | | |

## 5. Impressos

### `impresso-1-exame-fisico`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 1 — EXAME FÍSICO SEGMENTAR | [ ] | [ ] | | |
| `category` | physical_exam | [ ] | [ ] | | |
| `keywords` | `exame físico`, `exame segmentar`, `exame do abdome`, `exame abdominal`, `examinar o abdome`, `examinar a barriga`, `examinar o paciente`, `palpação abdominal`, `palpação do abdome`, `palpar o abdome`, `palpar a barriga`, `sinais vitais` | [ ] | [ ] | | |
| `content, line 1` | - **Estado geral:** regular, consciente, orientado, fácies de dor; hidratado, sem cianose ou icterícia. | [ ] | [ ] | | |
| `content, line 2` | - **Sinais vitais no exame:** PA 126/78 mmHg; FC 102 bpm; FR 18 irpm; temperatura 38,1 °C; SpO₂ 98% em ar ambiente. | [ ] | [ ] | | |
| `content, line 3` | - **Aparelho cardiovascular:** bulhas normofonéticas, ritmo regular, sem sopros. | [ ] | [ ] | | |
| `content, line 4` | - **Aparelho respiratório:** murmúrio vesicular presente bilateralmente, sem ruídos adventícios. | [ ] | [ ] | | |
| `content, line 5` | - **Abdome — inspeção:** plano, sem cicatrizes, distensão, equimoses ou circulação colateral; movimentação reduzida durante a respiração profunda. | [ ] | [ ] | | |
| `content, line 6` | - **Ausculta:** ruídos hidroaéreos presentes, discretamente diminuídos; sem sopros. | [ ] | [ ] | | |
| `content, line 7` | - **Percussão:** timpanismo predominante; sem macicez anormal. | [ ] | [ ] | | |
| `content, line 8` | - **Palpação superficial:** dor localizada no quadrante inferior direito, com defesa voluntária discreta. | [ ] | [ ] | | |
| `content, line 9` | - **Palpação profunda:** dor acentuada na fossa ilíaca direita, especialmente no ponto de McBurney. Descompressão brusca dolorosa na fossa ilíaca direita: sinal de Blumberg positivo. | [ ] | [ ] | | |
| `content, line 10` | - **Manobras:** sinal de Rovsing positivo; sinal do psoas negativo; sinal do obturador negativo. Sem dor à punho-percussão lombar. | [ ] | [ ] | | |
| `content, line 11` | - **Neurológico:** alerta, orientado em tempo, espaço e pessoa; sem déficit motor grosseiro. | [ ] | [ ] | | |
| `content, line 12` | - **Geniturinário:** sem dor testicular à inspeção referida; não é necessário exame genital invasivo na ausência de indicação clínica. | [ ] | [ ] | | |

### `impresso-2-hemograma`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 2 — EXAMES LABORATORIAIS — Hemograma completo | [ ] | [ ] | | |
| `category` | laboratory | [ ] | [ ] | | |
| `keywords` | `hemograma`, `leucograma` | [ ] | [ ] | | |
| `content, line 1` | **Hemograma completo:** | [ ] | [ ] | | |
| `content, line 2` | - Hemoglobina: 14,6 g/dL. Referência adulto masculino: 13,0–17,0 g/dL. | [ ] | [ ] | | |
| `content, line 3` | - Hematócrito: 43%. Referência adulto masculino: 40–52%. | [ ] | [ ] | | |
| `content, line 4` | - Leucócitos: 15.800/mm³. Referência: 4.000–11.000/mm³. | [ ] | [ ] | | |
| `content, line 5` | - Neutrófilos: 86%; bastonetes: 8%. Referências usuais: neutrófilos segmentados 40–75%; bastonetes 0–5%. | [ ] | [ ] | | |
| `content, line 6` | - Plaquetas: 268.000/mm³. Referência: 150.000–450.000/mm³. | [ ] | [ ] | | |

### `impresso-2-pcr`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 2 — EXAMES LABORATORIAIS — PCR | [ ] | [ ] | | |
| `category` | laboratory | [ ] | [ ] | | |
| `keywords` | `PCR`, `proteína C-reativa`, `proteína C reativa` | [ ] | [ ] | | |
| `content, line 1` | **Inflamação e função renal/metabólica:** | [ ] | [ ] | | |
| `content, line 2` | - PCR: 86 mg/L. Referência: inferior a 5 mg/L. | [ ] | [ ] | | |

### `impresso-2-eletrolitos`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 2 — EXAMES LABORATORIAIS — Sódio, Potássio | [ ] | [ ] | | |
| `category` | laboratory | [ ] | [ ] | | |
| `keywords` | `eletrólitos`, `sódio`, `potássio`, `ionograma` | [ ] | [ ] | | |
| `content, line 1` | **Inflamação e função renal/metabólica:** | [ ] | [ ] | | |
| `content, line 2` | - Sódio: 138 mmol/L. Referência: 135–145 mmol/L. | [ ] | [ ] | | |
| `content, line 3` | - Potássio: 4,1 mmol/L. Referência: 3,5–5,1 mmol/L. | [ ] | [ ] | | |

### `impresso-2-ureia`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 2 — EXAMES LABORATORIAIS — Ureia | [ ] | [ ] | | |
| `category` | laboratory | [ ] | [ ] | | |
| `keywords` | `ureia`, `função renal` | [ ] | [ ] | | |
| `content, line 1` | **Inflamação e função renal/metabólica:** | [ ] | [ ] | | |
| `content, line 2` | - Ureia: 28 mg/dL. Referência: 15–45 mg/dL. | [ ] | [ ] | | |

### `impresso-2-creatinina`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 2 — EXAMES LABORATORIAIS — Creatinina | [ ] | [ ] | | |
| `category` | laboratory | [ ] | [ ] | | |
| `keywords` | `creatinina`, `função renal` | [ ] | [ ] | | |
| `content, line 1` | **Inflamação e função renal/metabólica:** | [ ] | [ ] | | |
| `content, line 2` | - Creatinina: 0,9 mg/dL. Referência adulto masculino: 0,7–1,3 mg/dL. | [ ] | [ ] | | |

### `impresso-2-glicemia`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 2 — EXAMES LABORATORIAIS — Glicemia | [ ] | [ ] | | |
| `category` | laboratory | [ ] | [ ] | | |
| `keywords` | `glicemia`, `glicose` | [ ] | [ ] | | |
| `content, line 1` | **Inflamação e função renal/metabólica:** | [ ] | [ ] | | |
| `content, line 2` | - Glicemia: 104 mg/dL. Referência em jejum: 70–99 mg/dL. | [ ] | [ ] | | |

### `impresso-2-urina-tipo-1`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 2 — EXAMES LABORATORIAIS — Urina tipo 1 (EAS) | [ ] | [ ] | | |
| `category` | laboratory | [ ] | [ ] | | |
| `keywords` | `urina tipo 1`, `urina tipo I`, `urina 1`, `EAS`, `exame de urina`, `sumário de urina`, `parcial de urina`, `urinálise` | [ ] | [ ] | | |
| `content, line 1` | **Urina tipo 1 (EAS):** | [ ] | [ ] | | |
| `content, line 2` | - Densidade: 1,020; pH: 6,0. | [ ] | [ ] | | |
| `content, line 3` | - Nitrito negativo; esterase leucocitária negativa. | [ ] | [ ] | | |
| `content, line 4` | - Leucócitos: 2/campo; hemácias: 1/campo. | [ ] | [ ] | | |
| `content, line 5` | - Sem bacteriúria significativa, proteinúria ou cetonúria relevante. | [ ] | [ ] | | |

### `impresso-3-exame-de-imagem`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 3 — EXAME DE IMAGEM | [ ] | [ ] | | |
| `category` | imaging | [ ] | [ ] | | |
| `keywords` | `ultrassonografia de abdome e pelve`, `tomografia computadorizada de abdome e pelve`, `ultrassonografia`, `ultrassom`, `USG`, `ecografia`, `TC de abdome`, `TC do abdome`, `TC abdominal`, `tomografia de abdome`, `tomografia do abdome`, `tomografia abdominal`, `tomografia computadorizada de abdome`, `tomografia computadorizada do abdome`, `exame de imagem` | [ ] | [ ] | | |
| `content, line 1` | **Tomografia computadorizada de abdome e pelve com contraste intravenoso:** | [ ] | [ ] | | |
| `content, line 2` | - Apêndice cecal em posição habitual, com diâmetro externo máximo de 10 mm, espessamento parietal e realce mucoso. | [ ] | [ ] | | |
| `content, line 3` | - Presença de densificação da gordura periapendicular e pequena quantidade de líquido adjacente. | [ ] | [ ] | | |
| `content, line 4` | - Apendicolito de 5 mm no interior do apêndice. | [ ] | [ ] | | |
| `content, line 5` | - Sem pneumoperitônio, abscesso organizado, coleção ou sinais de perfuração. | [ ] | [ ] | | |
| `content, line 6` | - Sem dilatação de alças ou sinais de obstrução intestinal. | [ ] | [ ] | | |
| `content, line 7` | - Rins sem hidronefrose; bexiga sem alteração relevante. | [ ] | [ ] | | |
| `content, line 8` | **Conclusão:** achados compatíveis com apendicite aguda, sem evidência tomográfica de perfuração ou abscesso. | [ ] | [ ] | | |

### `impresso-4-receituario`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `title` | IMPRESSO 4 — RECEITUÁRIO/REGISTRO DE CONDUTA INICIAL | [ ] | [ ] | | |
| `category` | report | [ ] | [ ] | | |
| `keywords` | none (`[]`) | [ ] | [ ] | | |
| `content, line 1` | Para adulto sem alergia conhecida e função renal preservada, são opções adequadas: | [ ] | [ ] | | |
| `content, line 2` | - Jejum oral. | [ ] | [ ] | | |
| `content, line 3` | - Acesso venoso periférico e cristaloide intravenoso conforme estado de hidratação e resposta clínica; por exemplo, Ringer lactato ou cloreto de sódio 0,9%, com reavaliação. | [ ] | [ ] | | |
| `content, line 4` | - Dipirona 1 g intravenosa a cada 6 horas, se necessário, respeitando contraindicações e dose máxima diária. | [ ] | [ ] | | |
| `content, line 5` | - Ondansetrona 4 mg intravenosa a cada 8 horas, se necessário. | [ ] | [ ] | | |
| `content, line 6` | - Antibiótico intravenoso perioperatório conforme protocolo institucional e avaliação da equipe cirúrgica; opção: ceftriaxona 2 g IV associada a metronidazol 500 mg IV, com ajuste em caso de alergia, função renal alterada ou outra particularidade clínica. | [ ] | [ ] | | |
| `content, line 7` | - Avaliação imediata pela cirurgia geral. Não atrasar encaminhamento para avaliação cirúrgica enquanto se aguarda resposta a tratamento sintomático. | [ ] | [ ] | | |

## 6. Rubric

Points are in station points. `min_actions` is the number of performed actions a level needs.

### `item-01`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 1: Apresentação e identificação (Total: 0,2 ponto)<br>Critérios avaliados: (1) Identifica-se; (2) Cumprimenta o paciente e confirma seu nome. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Não realiza nenhuma ação. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.1` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `1` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Realiza uma ação. | [ ] | [ ] | | |
| `level adequado: points` | `0.2` | [ ] | [ ] | | |
| `level adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level adequado: description` | Realiza as duas ações. | [ ] | [ ] | | |
| `action criterio-1: description` | Identifica-se | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | Cumprimenta o paciente e confirma seu nome | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Apresentação e identificação | [ ] | [ ] | | |

### `item-02`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 2: Anamnese — caracterização da dor (Total: 0,8 ponto)<br>Critérios avaliados: (1) Localização inicial; (2) migração para fossa ilíaca direita; (3) caráter e progressão; (4) tempo de evolução; (5) intensidade; (6) fatores de piora ou melhora. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Investiga duas ou menos características. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.4` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `3` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Investiga três ou quatro características. | [ ] | [ ] | | |
| `level adequado: points` | `0.8` | [ ] | [ ] | | |
| `level adequado: min_actions` | `5` | [ ] | [ ] | | |
| `level adequado: description` | Investiga cinco ou seis características. | [ ] | [ ] | | |
| `action criterio-1: description` | Localização inicial | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | migração para fossa ilíaca direita | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | caráter e progressão | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | tempo de evolução | [ ] | [ ] | | |
| `action criterio-4: role` | counted | [ ] | [ ] | | |
| `action criterio-5: description` | intensidade | [ ] | [ ] | | |
| `action criterio-5: role` | counted | [ ] | [ ] | | |
| `action criterio-6: description` | fatores de piora ou melhora | [ ] | [ ] | | |
| `action criterio-6: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Anamnese — caracterização da dor | [ ] | [ ] | | |

### `item-03`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 3: Anamnese — sintomas associados e diagnósticos diferenciais (Total: 0,8 ponto)<br>Critérios avaliados: (1) Febre; (2) náuseas ou vômitos; (3) apetite; (4) hábito intestinal e eliminação de gases; (5) sintomas urinários; (6) sintomas genitais ou outros sinais de alarme. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Investiga um grupo ou nenhum. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.4` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Investiga dois ou três grupos. | [ ] | [ ] | | |
| `level adequado: points` | `0.8` | [ ] | [ ] | | |
| `level adequado: min_actions` | `4` | [ ] | [ ] | | |
| `level adequado: description` | Investiga pelo menos quatro dos seis grupos de sintomas. | [ ] | [ ] | | |
| `action criterio-1: description` | Febre | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | náuseas ou vômitos | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | apetite | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | hábito intestinal e eliminação de gases | [ ] | [ ] | | |
| `action criterio-4: role` | counted | [ ] | [ ] | | |
| `action criterio-5: description` | sintomas urinários | [ ] | [ ] | | |
| `action criterio-5: role` | counted | [ ] | [ ] | | |
| `action criterio-6: description` | sintomas genitais ou outros sinais de alarme | [ ] | [ ] | | |
| `action criterio-6: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Anamnese — sintomas associados e diagnósticos diferenciais | [ ] | [ ] | | |

### `item-04`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 4: Antecedentes, medicamentos e alergias (Total: 0,6 ponto)<br>Critérios avaliados: (1) Comorbidades; (2) cirurgias ou internações prévias; (3) medicamentos de uso habitual ou recente; (4) alergias medicamentosas; (5) uso de anticoagulantes ou antibióticos recentes. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Investiga um item ou nenhum. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.3` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Investiga dois ou três itens. | [ ] | [ ] | | |
| `level adequado: points` | `0.6` | [ ] | [ ] | | |
| `level adequado: min_actions` | `4` | [ ] | [ ] | | |
| `level adequado: description` | Investiga quatro ou cinco itens. | [ ] | [ ] | | |
| `action criterio-1: description` | Comorbidades | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | cirurgias ou internações prévias | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | medicamentos de uso habitual ou recente | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | alergias medicamentosas | [ ] | [ ] | | |
| `action criterio-4: role` | counted | [ ] | [ ] | | |
| `action criterio-5: description` | uso de anticoagulantes ou antibióticos recentes | [ ] | [ ] | | |
| `action criterio-5: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Antecedentes, medicamentos e alergias | [ ] | [ ] | | |

### `item-05`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 5: Exame físico abdominal e manobras (Total: 1,2 ponto)<br>Critérios avaliados: (1) Explica o exame e solicita autorização, com paciente em decúbito dorsal; (2) verbaliza dor à palpação profunda no ponto de McBurney/fossa ilíaca direita; (3) pesquisa e interpreta o sinal de Blumberg; (4) pesquisa ao menos uma manobra entre Rovsing, psoas e obturador. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Realiza ou solicita uma ação ou nenhuma. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.6` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Realiza ou solicita corretamente duas ações. | [ ] | [ ] | | |
| `level adequado: points` | `1.2` | [ ] | [ ] | | |
| `level adequado: min_actions` | `3` | [ ] | [ ] | | |
| `level adequado: description` | Realiza ou solicita corretamente três ou quatro ações. | [ ] | [ ] | | |
| `action criterio-1: description` | Explica o exame e solicita autorização, com paciente em decúbito dorsal | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | verbaliza dor à palpação profunda no ponto de McBurney/fossa ilíaca direita | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | pesquisa e interpreta o sinal de Blumberg | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | pesquisa ao menos uma manobra entre Rovsing, psoas e obturador | [ ] | [ ] | | |
| `action criterio-4: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Exame físico abdominal e manobras | [ ] | [ ] | | |

### `item-06`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 6: Solicitação de exames laboratoriais (Total: 0,8 ponto)<br>Critérios avaliados: (1) Hemograma completo; (2) PCR; (3) urina tipo 1; (4) função renal e eletrólitos, especialmente se houver necessidade de contraste ou hidratação. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Solicita um grupo ou nenhum. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.4` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Solicita dois grupos. | [ ] | [ ] | | |
| `level adequado: points` | `0.8` | [ ] | [ ] | | |
| `level adequado: min_actions` | `3` | [ ] | [ ] | | |
| `level adequado: description` | Solicita três ou quatro grupos pertinentes. | [ ] | [ ] | | |
| `action criterio-1: description` | Hemograma completo | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | PCR | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | urina tipo 1 | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | função renal e eletrólitos, especialmente se houver necessidade de contraste ou hidratação | [ ] | [ ] | | |
| `action criterio-4: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Solicitação de exames laboratoriais | [ ] | [ ] | | |

### `item-07`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 7: Interpretação laboratorial (Total: 0,8 ponto)<br>Critérios avaliados: (1) Identifica leucocitose com neutrofilia e desvio à esquerda; (2) reconhece PCR elevada; (3) interpreta EAS sem evidências de infecção urinária; (4) considera função renal e eletrólitos preservados. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Interpreta um achado ou nenhum, ou atribui incorretamente o quadro a infecção urinária. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.4` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Interpreta corretamente dois achados. | [ ] | [ ] | | |
| `level adequado: points` | `0.8` | [ ] | [ ] | | |
| `level adequado: min_actions` | `3` | [ ] | [ ] | | |
| `level adequado: description` | Interpreta corretamente três ou quatro achados. | [ ] | [ ] | | |
| `action criterio-1: description` | Identifica leucocitose com neutrofilia e desvio à esquerda | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | reconhece PCR elevada | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | interpreta EAS sem evidências de infecção urinária | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | considera função renal e eletrólitos preservados | [ ] | [ ] | | |
| `action criterio-4: role` | counted | [ ] | [ ] | | |
| `action atribuicao-a-infeccao-urinaria: description` | atribui incorretamente o quadro a infecção urinária | [ ] | [ ] | | |
| `action atribuicao-a-infeccao-urinaria: role` | forbidden | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `true` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Interpretação laboratorial | [ ] | [ ] | | |

### `item-08`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 8: Solicitação e interpretação de imagem e hipótese diagnóstica (Total: 1,4 ponto)<br>Critérios avaliados: (1) Solicita imagem adequada, considerando TC ou ultrassonografia conforme disponibilidade e contexto; (2) identifica apêndice dilatado, espessamento parietal e inflamação periapendicular; (3) reconhece ausência de abscesso ou perfuração; (4) formula a hipótese de apendicite aguda. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Não formula apendicite aguda como hipótese principal. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.7` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `1` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Formula a hipótese diagnóstica principal, mas falha em interpretar um ou mais achados da imagem. | [ ] | [ ] | | |
| `level adequado: points` | `1.4` | [ ] | [ ] | | |
| `level adequado: min_actions` | `4` | [ ] | [ ] | | |
| `level adequado: description` | Cumpre os quatro critérios. | [ ] | [ ] | | |
| `action criterio-1: description` | Solicita imagem adequada, considerando TC ou ultrassonografia conforme disponibilidade e contexto | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | identifica apêndice dilatado, espessamento parietal e inflamação periapendicular | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | reconhece ausência de abscesso ou perfuração | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | formula a hipótese de apendicite aguda | [ ] | [ ] | | |
| `action criterio-4: role` | mandatory | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Solicitação e interpretação de imagem e hipótese diagnóstica | [ ] | [ ] | | |

### `item-09`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 9: Medidas de suporte e preparo inicial (Total: 1,2 ponto)<br>Critérios avaliados: (1) Mantém jejum oral; (2) estabelece acesso venoso e indica cristaloide conforme avaliação clínica, com reavaliação; (3) prescreve analgesia apropriada; (4) prescreve antiemético se necessário; (5) monitora sinais vitais e evolução clínica. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Indica uma medida ou nenhuma. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.6` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Indica duas ou três medidas. | [ ] | [ ] | | |
| `level adequado: points` | `1.2` | [ ] | [ ] | | |
| `level adequado: min_actions` | `4` | [ ] | [ ] | | |
| `level adequado: description` | Indica quatro ou cinco medidas. | [ ] | [ ] | | |
| `action criterio-1: description` | Mantém jejum oral | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | estabelece acesso venoso e indica cristaloide conforme avaliação clínica, com reavaliação | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | prescreve analgesia apropriada | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | prescreve antiemético se necessário | [ ] | [ ] | | |
| `action criterio-4: role` | counted | [ ] | [ ] | | |
| `action criterio-5: description` | monitora sinais vitais e evolução clínica | [ ] | [ ] | | |
| `action criterio-5: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Medidas de suporte e preparo inicial | [ ] | [ ] | | |

### `item-10`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 10: Antibiótico e articulação com equipe cirúrgica (Total: 1,2 ponto)<br>Critérios avaliados: (1) Solicita avaliação imediata da cirurgia geral; (2) indica antibiótico intravenoso perioperatório conforme protocolo e sem retardar a avaliação cirúrgica; (3) propõe cobertura para bacilos gram-negativos e anaeróbios, como ceftriaxona associada a metronidazol. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Não solicita avaliação cirúrgica nem indica conduta antimicrobiana pertinente. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.6` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Cumpre dois critérios ou prescreve antibiótico sem contemplar cobertura adequada para anaeróbios. | [ ] | [ ] | | |
| `level adequado: points` | `1.2` | [ ] | [ ] | | |
| `level adequado: min_actions` | `3` | [ ] | [ ] | | |
| `level adequado: description` | Cumpre os três critérios. | [ ] | [ ] | | |
| `action criterio-1: description` | Solicita avaliação imediata da cirurgia geral | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | indica antibiótico intravenoso perioperatório conforme protocolo e sem retardar a avaliação cirúrgica | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | propõe cobertura para bacilos gram-negativos e anaeróbios, como ceftriaxona associada a metronidazol | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Antibiótico e articulação com equipe cirúrgica | [ ] | [ ] | | |

### `item-11`

| Field | Value | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|
| `description` | ITEM 11: Conduta definitiva, consentimento e comunicação (Total: 1,0 ponto)<br>Critérios avaliados: (1) Indica avaliação para apendicectomia em caráter de urgência e encaminhamento à equipe/centro cirúrgico; (2) explica o diagnóstico provável, a finalidade da cirurgia e que a conduta definitiva depende de avaliação cirúrgica; (3) responde às duas dúvidas do paciente com clareza, empatia e informação compatível com a evolução clínica; (4) menciona obtenção de consentimento livre e esclarecido pela equipe responsável antes do procedimento, quando aplicável. | [ ] | [ ] | | |
| `level inadequado: points` | `0` | [ ] | [ ] | | |
| `level inadequado: min_actions` | `0` | [ ] | [ ] | | |
| `level inadequado: description` | Cumpre um critério ou nenhum. | [ ] | [ ] | | |
| `level parcialmente_adequado: points` | `0.5` | [ ] | [ ] | | |
| `level parcialmente_adequado: min_actions` | `2` | [ ] | [ ] | | |
| `level parcialmente_adequado: description` | Cumpre dois critérios. | [ ] | [ ] | | |
| `level adequado: points` | `1` | [ ] | [ ] | | |
| `level adequado: min_actions` | `3` | [ ] | [ ] | | |
| `level adequado: description` | Cumpre três ou quatro critérios. | [ ] | [ ] | | |
| `action criterio-1: description` | Indica avaliação para apendicectomia em caráter de urgência e encaminhamento à equipe/centro cirúrgico | [ ] | [ ] | | |
| `action criterio-1: role` | counted | [ ] | [ ] | | |
| `action criterio-2: description` | explica o diagnóstico provável, a finalidade da cirurgia e que a conduta definitiva depende de avaliação cirúrgica | [ ] | [ ] | | |
| `action criterio-2: role` | counted | [ ] | [ ] | | |
| `action criterio-3: description` | responde às duas dúvidas do paciente com clareza, empatia e informação compatível com a evolução clínica | [ ] | [ ] | | |
| `action criterio-3: role` | counted | [ ] | [ ] | | |
| `action criterio-4: description` | menciona obtenção de consentimento livre e esclarecido pela equipe responsável antes do procedimento, quando aplicável | [ ] | [ ] | | |
| `action criterio-4: role` | counted | [ ] | [ ] | | |
| `order` | `null` | [ ] | [ ] | | |
| `count_cap` | `null` | [ ] | [ ] | | |
| `first_n` | `null` | [ ] | [ ] | | |
| `veto` | `false` | [ ] | [ ] | | |
| `exclusion` | `false` | [ ] | [ ] | | |
| `modality_requirement` | `null` | [ ] | [ ] | | |
| `rule` | `null` | [ ] | [ ] | | |
| `evidence_questions` | none (`[]`) | [ ] | [ ] | | |
| `practice_recommendation` | Conduta definitiva, consentimento e comunicação | [ ] | [ ] | | |

## 7. Gaps the reviewer must decide

Copied from the mapping record, which has the full description of each gap.

| Gap | Encoding in the package | Scoring direction versus the source | Decision needed | Decided | Reviewer | Date |
|---|---|---|---|---|---|---|
| G1 | Thresholds 0 / 2 / 3 over the three criteria. | **Lower.** A learner who only prescribes an antibiotic without anaerobic coverage scores 0, not 0.6. A learner who meets exactly one criterion scores 0; the source defines no level for "surgical evaluation only". | The level for each single-criterion case, and whether the second half of the partial rule should be its own criterion. | [ ] | | |
| G2a | `criterio-4` `mandatory`; thresholds 0 / 1 / 4. | **Equal** in the cases the source defines. The source defines no level for "hypothesis, both findings interpreted, imaging not requested"; the package scores it 0.7. | The level for that case. | [ ] | | |
| G2b | The criterion 4 text, verbatim. The level sentences reach the classifier in the criterion description. | **Possibly higher.** If appendicitis is named but not as the main hypothesis and the classifier marks criterion 4 performed, the package scores 0.7 or more where the source says 0. | Whether criterion 4 should say "principal". | [ ] | | |
| G3 | Fifth action, `forbidden`, `veto: true`. | **Equal.** | Confirm the action text (D14). | [ ] | | |
| G4 | One action per numbered criterion, verbatim. The classifier judges the inner condition from the text. | **Equal** at the threshold level; the inner condition is not verified in code. | Whether any compound criterion should be split. | [ ] | | |
| G5 | Seven impressos, one per named test (sodium and potassium together), each with its common phrasings (#241): "função renal" releases urea and creatinine, "sódio"/"potássio" the electrolytes, "EAS" and "urina 1" the urinalysis. A generic request ("exames laboratoriais") matches nothing and returns "unavailable". | **Lower** only for wordings not authored and for the generic request, which gets no "which tests?" question. | The split, the grouping of sodium and potassium under "eletrólitos", and the keywords. | [ ] | | |
| G6 | One impresso. Full phrases plus common abdominal phrasings (#241): "TC de abdome", "tomografia de abdome", "USG", "ultrassom", "exame de imagem". An ultrasound request releases the CT report, as in the source. | **Lower** only for wordings not authored. A CT request that does not name the abdomen releases nothing. | The keywords, whether "de abdome e pelve" applies to the ultrasound, and whether an ultrasound request should get a CT report. | [ ] | | |
| G7 | No keywords (`[]`): the impresso is in the package and is intentionally never released. Its content is the expected initial conduct scored in Items 9 and 10 (jejum, cristaloide, dipirona, ondansetrona, ceftriaxona + metronidazol, avaliação cirúrgica), so releasing it would hand the learner the answer key. The learner verbalizes the conduct instead; a prescription-style request ("prescrição", "receita", "receituário", "conduta inicial", "medidas de suporte") releases nothing. | **Lower or equal.** Items 9 and 10 are scored from what the learner says. | Whether and how this impresso is shown. | [ ] | | |
| G8 | `exame físico` plus common phrasings (#241): "exame do abdome", "examinar o abdome", "palpação abdominal", "sinais vitais". "Exame" alone releases nothing. | **Lower** only for wordings not authored. Any mention of a phrase releases it, including a negated one. | The keywords. | [ ] | | |
| G9 | All 25 answers `on_request`; the source heading is kept in `topic`. | No scoring rule depends on it. The patient prompt lists every fact without its condition (`backend/lib/backend/stations/station_ai.ex:176`); the condition is only forwarded to the decision model. | Whether the distinction must be enforced. | [ ] | | |
| G10 | Two `timed` facts holding the quoted questions. No approved template, because a turn count would be invented. | **Lower.** If the patient never asks, Item 11 criterion 3 cannot be met; "Adequado" stays reachable through criteria 1, 2 and 4. | How and when the questions are asked. | [ ] | | |
| G11 | One response rule, verbatim. | None on scoring. | Whether this behaviour is needed in a voice or text station. | [ ] | | |
| G12 | Scenario paragraph in `presenting_context`, which feeds the patient model's prompt. Área, Nível de atenção, Infraestrutura and the duration are not carried. | None on scoring. The learner sees the vital signs only through Impresso 1. | Where the scenario and tasks are shown. | [ ] | | |
| G13 | "Tema" as title; `acute-appendicitis` as id. | None on scoring. Both name the diagnosis. | The learner-visible title. | [ ] | | |
| G14 | `null` on every item: any learner evidence is valid. | Not determined by the source. | Whether any item must be verbal only. | [ ] | | |
| G15 | Verbatim in `expected_actions`; the rubric assessment does not read it. | None in code; the classifier does not receive it for Item 11. | Whether it belongs in Item 11. | [ ] | | |
| G16 | Verbatim. `antecedentes-05` says family history is available if asked but the source gives none. | None on scoring. | The family history content, if any. | [ ] | | |
| G17 | Not used: the source scores no order. | **Equal.** | — | [ ] | | |

## 8. Derived fields the reviewer must confirm

These were derived by the transcriber and are not partner-authored.

| Derived | Field | What was derived | Confirmed | Change requested | Reviewer | Date |
|---|---|---|---|---|---|---|
| D1 | `display_title` | The choice of "Tema" as the title. | [ ] | [ ] | | |
| D2 | `patient_profile.age` | `27`, read from the scenario paragraph. | [ ] | [ ] | | |
| D3 | `patient_profile.persona`, `.tone` | The split of the "Perfil do paciente" paragraph across the two required fields. | [ ] | [ ] | | |
| D4 | `patient_profile.presenting_context` | The choice of the scenario paragraph for this field (it is written to the participant, in the second person). | [ ] | [ ] | | |
| D5 | `revealable_facts[].id`, `.topic` | Positional ids; `topic` is the source section heading. One fact per bullet, except the splits of D22. | [ ] | [ ] | | |
| D6 | `revealable_facts[].disclosure_condition` | `on_request` for the 25 answers, `timed` for the two final doubts. | [ ] | [ ] | | |
| D7 | `response_rules` | The id and the choice of this field for "Comportamento durante o exame". | [ ] | [ ] | | |
| D8 | `expected_actions` | The ids and the choice of this field for the five tasks and the answer guidance. | [ ] | [ ] | | |
| D9 | `rubric[].id`, `rubric[].actions[].id` | Positional ids. | [ ] | [ ] | | |
| D10 | `rubric[].description` | Composition: title line, newline, criteria line. | [ ] | [ ] | | |
| D11 | `rubric[].evidence_questions` | Empty list on every item. The source authors none. | [ ] | [ ] | | |
| D12 | `rubric[].practice_recommendation` | The item title, used as a placeholder. The source authors no recommendation, and this text is shown to learners. | [ ] | [ ] | | |
| D13 | `rubric[].levels[].min_actions` | The integer thresholds, read from each level sentence (table above). | [ ] | [ ] | | |
| D14 | `item-07` action `atribuicao-a-infeccao-urinaria`, `veto: true` | A fifth, `forbidden` action whose text is a fragment of the "Inadequado" sentence. | [ ] | [ ] | | |
| D15 | `item-08` `criterio-4` role `mandatory`; partial threshold `1` | Read from the "Parcialmente adequado" and "Inadequado" sentences. | [ ] | [ ] | | |
| D16 | `rubric[].order`, `count_cap`, `first_n`, `exclusion`, `modality_requirement`, `rule` | Left unset (`null` / `false`): the source authors none of them. | [ ] | [ ] | | |
| D17 | `impressos[].id`, `.category` | Ids; `report` for Impresso 4 (the contract has no prescription category). | [ ] | [ ] | | |
| D18 | `impressos[].title` for the seven Impresso 2 parts | Source title, " — ", and the line label or subheading. | [ ] | [ ] | | |
| D19 | `impressos[].keywords` | Every keyword (table below). | [ ] | [ ] | | |
| D20 | `approved_templates` | `null`. The source authors no template. | [ ] | [ ] | | |
| D21 | `rubric[].actions[].impresso_ids` on `item-06` `criterio-1`–`4` and `item-08` `criterio-1` (issue #228) | Each lab group names the Impresso 2 parts that answer it (`criterio-4`: `-ureia`, `-creatinina`, `-eletrolitos`); the imaging request names `impresso-3-exame-de-imagem`. A verified request that releases one of them grades the action performed without a provider. `item-05` names none. | [ ] | [ ] | | |
| D22 | `revealable_facts` split per rubric characteristic (issue #264) | Source bullets that answer several rubric characteristics are split into one fact per characteristic, so a reply to one question cannot volunteer another criterion. Each part keeps the source wording of its clause, reordered into a sentence; no fact is added. The first part keeps the positional id and the others get a suffixed id: `hda-01` (initial location), `hda-01-migracao` (migration), `hda-01-tempo` (time since onset); `hda-02` (character), `hda-02-progressao` (progression), `hda-02-intensidade` (intensity). Items 3 and 4: `antecedentes-01` (comorbidities), `antecedentes-01-internacoes-cirurgias` (prior hospitalizations and surgeries); `pergunta-explicita-02` (recent antibiotics or anticoagulants, item-04 criterion 5), `pergunta-explicita-02-anti-inflamatorios` (recent anti-inflammatories, criterion 3). Kept whole because each answers one criterion: `hda-03`, `hda-04`, `hda-07`, `pergunta-explicita-03`, `-04`. | [ ] | [ ] | | |
| D23 | `rubric[].actions[].interprets_impresso_ids` on `item-05` `criterio-2`–`4`, `item-07` `criterio-1`–`4` and `item-08` `criterio-2`–`4` (issue #265) | A learner cannot interpret an exam before receiving it: these actions accept only learner turns sent after the named impresso was released. Item 5 findings name `impresso-1-exame-fisico`; each item 7 action names the Impresso 2 parts it reads (`criterio-4`: `-ureia`, `-creatinina`, `-eletrolitos`); item 8 interpretation and hypothesis (`criterio-4`, mandatory) name `impresso-3-exame-de-imagem`, so a hypothesis stated only before the imaging release does not count. `item-05` `criterio-1` (authorization) and the `item-07` forbidden attribution name none. | [ ] | [ ] | | |
| D24 | `revealable_facts` `hda-06` split (issue #273) | The source fever bullet also said "não tomou antitérmico", a recent-medication clause (item-04 criterion 3). Answering "Teve febre?" with it left Jev unable to tell whether the reply also stated the unasked medication facts (`antecedentes-02`, `pergunta-explicita-02-anti-inflamatorios`), and the reply was refused. Split as in D22: `hda-06` (fever, item-03 criterion 1) and `hda-06-antitermico` (no antipyretic taken). Same wording, no fact added. Reviewed for the same overlap and kept: `hda-07` (bowel habit now) and `pergunta-explicita-04` (persistent change over weeks) differ in time frame; `hda-05` (appetite) and `pergunta-explicita-05` (hydration and oral intake) answer different questions. | [ ] | [ ] | | |

## 9. Sign-off

| Field | Value |
|---|---|
| Reviewer name | PENDING |
| Qualification and registration | PENDING |
| Date completed | PENDING |
| Outcome (approved / approved with changes / rejected) | PENDING |
| Signature | PENDING |

## Notes and requested changes

| Row or id | Requested change | Reviewer | Date |
|---|---|---|---|
| | | | |
