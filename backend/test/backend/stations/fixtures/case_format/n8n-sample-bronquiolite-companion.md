# ESTAÇÃO

[ESTAÇÃO bronquiolite-lactente]
[ÁREA] Pediatria
[TEMA] Bronquiolite viral aguda em lactente, atendida com a mãe como acompanhante
[PROVISÓRIO] sim

# 1. CENÁRIO DE ATUAÇÃO E INSTRUÇÕES AO PARTICIPANTE

[CENÁRIO] Você é o médico ou a médica plantonista do consultório pediátrico de uma Unidade de Pronto Atendimento (UPA 24 horas), em um mês de outono. A unidade dispõe de materiais para o exame físico pediátrico: estetoscópio, otoscópio, oxímetro de pulso com sensor neonatal e pediátrico, balança, termômetro e relógio para contagem da frequência respiratória. Há rede de oxigênio com cateter nasal e máscara, aspirador de secreções, soro fisiológico 0,9%, sonda nasogástrica e material para acesso venoso. O laboratório realiza hemograma, proteína C-reativa, gasometria e pesquisa de vírus respiratórios em amostra de nasofaringe, e há radiografia de tórax. O hospital municipal de referência tem enfermaria pediátrica e UTI pediátrica e recebe transferências pela central de regulação. Sofia Andrade Lima, 4 meses, sexo feminino, 6,4 kg, é trazida pela mãe por tosse e nariz entupido há quatro dias, com piora há um dia. Sinais vitais da triagem: temperatura axilar 37,9 °C; FC 168 bpm; FR 64 irpm; SpO2 89% em ar ambiente; peso 6,4 kg.
[TAREFA tarefa-1] Realizar a anamnese dirigida com a mãe.
[TAREFA tarefa-2] Solicitar e interpretar o exame físico.
[TAREFA tarefa-3] Solicitar e interpretar os exames complementares pertinentes.
[TAREFA tarefa-4] Formular a hipótese diagnóstica, classificar a gravidade e definir a conduta.
[TAREFA tarefa-5] Orientar a mãe sobre prevenção e responder às suas dúvidas.

# 2. ATORES

[ATOR paciente papel=paciente idade=0 voz=infantil] Sofia Andrade Lima
[PERFIL] Lactente de 4 meses no colo da mãe, com respiração rápida e esforçada, nariz com secreção clara e tosse frequente. Irritada, mas consolável. Não responde a perguntas.
[TOM] Não fala; choraminga, tosse e chora ao ser manipulada.
[CONTEXTO] Sofia Andrade Lima, 4 meses e 10 dias, 6,4 kg, trazida pela mãe por tosse e obstrução nasal há quatro dias, com cansaço e piora da alimentação há um dia. Triagem: temperatura axilar 37,9 °C; FC 168 bpm; FR 64 irpm; SpO2 89% em ar ambiente.

[ATOR mae papel=acompanhante idade=24 voz=feminina-adulta] Juliana Andrade Lima
[PERFIL] Mãe de Sofia, 24 anos, auxiliar de cozinha em licença-maternidade, ensino médio completo. Está cansada, preocupada e assustada com a respiração da filha. Colabora, mas resiste à ideia de internação porque tem outro filho de 3 anos em casa.
[TOM] Fala de forma simples, sem termos técnicos; usa expressões como "cansaço" e "chiadeira no peito".

# 3. ROTEIRO DO ATOR SIMULADO

[TÓPICO] HDA — respostas da mãe
[FATO coriza-inicio ator=mae pep=item-02.criterio-1] Começou há quatro dias com o nariz escorrendo água e entupido; ela ronca para respirar.
[FATO tosse-caracter ator=mae pep=item-02.criterio-2] A tosse começou no dia seguinte; é seca, em crise, e piorou muito de ontem para hoje.
[FATO febre-caracter ator=mae pep=item-02.criterio-3] Teve febre baixa, no máximo 38,2 °C no termômetro, desde anteontem; melhora com o remédio.
[FATO cansaco-chiado ator=mae pep=item-02.criterio-4] Desde ontem à tarde está respirando rápido, com a barriga afundando, e faz um chiado no peito.
[FATO primeira-vez ator=mae] É a primeira vez que ela fica assim; ontem à noite quase não dormiu.

[TÓPICO] Sinais de gravidade — respostas da mãe
[FATO aceitacao-mamadas ator=mae pep=item-03.criterio-1] Ela pega o peito, mama um pouquinho e solta para respirar; hoje mamou menos da metade do que costuma.
[FATO diurese ator=mae pep=item-03.criterio-2] Hoje só molhou três fraldas; antes eram umas seis ou sete por dia.
[FATO sem-apneia ator=mae pep=item-03.criterio-3] Não ficou roxinha e não percebi ela parar de respirar.
[FATO vomitos-tosse ator=mae pep=item-03.criterio-4] Vomitou duas vezes depois da crise de tosse, só leite; não tem diarreia.

[TÓPICO] Antecedentes, medicações e vacinação — respostas da mãe
[FATO perinatal ator=mae pep=item-04.criterio-1] Fiz pré-natal certinho; nasceu de parto normal com 38 semanas, pesando 3.250 g, e foi para casa comigo em dois dias.
[FATO sem-doencas-previas ator=mae pep=item-04.criterio-2] Nunca teve chiado, nunca foi internada e o pediatra nunca falou de problema no coração.
[FATO medicacoes ator=mae pep=item-04.criterio-3] Só pinguei soro no nariz e dei paracetamol em gotas, 6 gotas; ela não tem alergia a remédio.
[FATO vacinas ator=mae pep=item-04.criterio-4] As vacinas estão em dia; as de 4 meses ela tomou na semana passada. Trouxe a caderneta.

[TÓPICO] Contexto epidemiológico, hábitos e família — respostas da mãe
[FATO irmao-creche ator=mae pep=item-05.criterio-1] O irmão de 3 anos vai à creche e está gripado, com nariz escorrendo, há uma semana.
[FATO tabagismo ator=mae pep=item-05.criterio-2 EXPLÍCITO] O pai dela fuma um maço por dia, às vezes dentro de casa, na cozinha.
[FATO aleitamento ator=mae pep=item-05.criterio-3] Ela mama só no peito, não toma água nem chá.
[FATO familia-atopia ator=mae pep=item-05.criterio-4] O pai tem rinite; ninguém na família tem asma ou bronquite.
[FATO moradia ator=mae] Moramos em casa de três cômodos, com um pouco de mofo no quarto.
[FATO choro-lactente ator=paciente] Chora fraco ao ser despida e tosse em crise; acalma no colo da mãe.

[REGRA comportamento-no-exame] Se o candidato pedir para examinar, a mãe coloca Sofia na maca, despe a criança e a mantém tranquila. O examinador entrega o Impresso 1 assim que o exame físico é verbalizado.

[TÓPICO] Dúvidas obrigatórias da mãe
[PERGUNTA-OBRIGATÓRIA duvida-mae-01 ator=mae] “Doutor, precisa mesmo internar? Não dá para eu levar para casa e fazer nebulização lá?”
[PERGUNTA-OBRIGATÓRIA duvida-mae-02 ator=mae] “Ela não vai tomar antibiótico, xarope ou bombinha para o chiado?”
[PERGUNTA-OBRIGATÓRIA duvida-mae-03 ator=mae] “Isso vai virar asma? Quanto tempo essa tosse vai durar?”

[CONDUTA-ESPERADA resposta-as-duvidas-da-mae] Sobre a internação, o candidato explica que Sofia está com oxigênio baixo (89%), respira muito rápido, com esforço, e mama menos da metade. Por isso precisa de oxigênio e de vigilância no hospital, e a nebulização caseira não substitui esse cuidado. Sobre os remédios, explica que a doença é causada por vírus, o vírus sincicial respiratório. Antibiótico, xarope para tosse, corticoide e salbutamol ou adrenalina inalatórios não ajudam e podem causar efeitos adversos; o tratamento é de suporte, com oxigênio, lavagem e aspiração nasal, alimentação e hidratação. Sobre o prognóstico, informa que o pico da doença ocorre entre o 3º e o 5º dia e que a maioria das crianças se recupera completamente. A tosse pode persistir por 2 a 4 semanas. Uma parte das crianças pode ter novos episódios de chiado nos primeiros anos, sem que isso signifique asma, e o risco diminui sem exposição à fumaça de cigarro.

# 4. IMPRESSOS DISPONÍVEIS NA ESTAÇÃO

[IMPRESSO impresso-1-exame-fisico categoria=exame-fisico] IMPRESSO 1 — EXAME FÍSICO SEGMENTAR
[LIBERAÇÃO] exame físico; examinar a criança; exame físico segmentar; ausculta pulmonar; sinais vitais
[CONTEÚDO]
- **Estado geral:** regular estado geral, irritada, consolável, corada, acianótica em repouso, anictérica, afebril no momento; peso 6,4 kg.
- **Sinais vitais:** temperatura axilar 37,9 °C; FC 168 bpm; FR 64 irpm (contada em 1 minuto); SpO2 89% em ar ambiente; tempo de enchimento capilar 2 s.
- **Hidratação:** mucosas discretamente secas, lágrimas presentes, fontanela anterior normotensa, turgor cutâneo preservado.
- **Cabeça e pescoço:** coriza hialina abundante bilateral; otoscopia com membranas timpânicas íntegras e translúcidas; orofaringe sem exsudato; sem linfonodomegalias.
- **Aparelho respiratório:** batimento de asa nasal, tiragem subcostal e intercostal moderadas; tórax com aumento do diâmetro anteroposterior; percussão com som claro pulmonar; murmúrio vesicular presente bilateralmente, com tempo expiratório prolongado, sibilos expiratórios difusos e estertores crepitantes finos bibasais; sem gemência.
- **Aparelho cardiovascular:** ritmo cardíaco regular em 2 tempos, bulhas normofonéticas, sem sopros; pulsos femorais palpáveis e simétricos.
- **Abdome:** flácido, indolor; fígado palpável a 2 cm do rebordo costal direito, de consistência normal (rebaixamento por hiperinsuflação pulmonar); baço não palpável.
- **Pele:** sem exantema, sem petéquias.
- **Neurológico:** ativa ao manuseio, tônus preservado, sucção presente porém interrompida pela dispneia; sem rigidez de nuca.

[IMPRESSO impresso-2-painel-viral categoria=laboratorio] IMPRESSO 2 — PESQUISA DE VÍRUS RESPIRATÓRIOS EM ASPIRADO DE NASOFARINGE
[LIBERAÇÃO] pesquisa de vírus respiratórios; painel viral; painel respiratório; pesquisa de VSR; vírus sincicial respiratório; aspirado de nasofaringe; swab de nasofaringe; RT-PCR para vírus respiratórios; imunofluorescência para vírus respiratórios
[CONTEÚDO]
- **Material:** aspirado de nasofaringe. **Método:** RT-PCR em tempo real (painel multiplex).
- Vírus sincicial respiratório (VSR): **DETECTADO**. Referência: não detectado.
- Influenza A e B: não detectado. Referência: não detectado.
- SARS-CoV-2: não detectado. Referência: não detectado.
- Rinovírus/enterovírus: não detectado. Referência: não detectado.
- Metapneumovírus humano: não detectado. Referência: não detectado.
- Adenovírus: não detectado. Referência: não detectado.
- Parainfluenza 1 a 4: não detectado. Referência: não detectado.

[IMPRESSO impresso-3-caderneta categoria=registro] IMPRESSO 3 — CADERNETA DA CRIANÇA (VACINAÇÃO E CRESCIMENTO)
[LIBERAÇÃO] caderneta da criança; caderneta de vacinação; cartão de vacina; carteira de vacinação; curva de crescimento; caderneta de saúde da criança
[CONTEÚDO]
- **Ao nascer:** BCG dose única; hepatite B dose ao nascer.
- **2 meses:** pentavalente (DTP + Hib + hepatite B) 1ª dose; VIP 1ª dose; pneumocócica 10-valente 1ª dose; rotavírus 1ª dose.
- **3 meses:** meningocócica C 1ª dose.
- **4 meses (aplicadas há 7 dias):** pentavalente 2ª dose; VIP 2ª dose; pneumocócica 10-valente 2ª dose; rotavírus 2ª dose.
- **Crescimento:** peso ao nascer 3.250 g; comprimento 49 cm. Peso atual 6,4 kg, entre escore z 0 e +1 na curva de peso para idade da OMS (meninas), com ganho ponderal adequado.
- **Observação:** idade gestacional de 38 semanas; sem registro de cardiopatia, doença pulmonar crônica ou internações.

# 5. PADRÃO ESPERADO DE PROCEDIMENTO (PEP)

[ITEM item-01] Apresentação e acolhimento
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] subitem (1): apresenta-se com nome e função
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): cumprimenta a mãe e confirma o nome e a idade da criança
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] subitem (3): higieniza as mãos antes de examinar a lactente
[NÍVEL adequado pontos=0,3 mínimo=3] Realiza os 3 critérios.
[NÍVEL parcialmente_adequado pontos=0,15 mínimo=1] Realiza 1 ou 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhum critério.

[ITEM item-02] Anamnese — sintomas respiratórios
[CRITÉRIO criterio-1 tipo=PERGUNTA] subitem (1): início e evolução da coriza e da obstrução nasal (pródromo)
[CRITÉRIO criterio-2 tipo=PERGUNTA] subitem (2): início e características da tosse
[CRITÉRIO criterio-3 tipo=PERGUNTA] subitem (3): febre e temperatura máxima aferida
[CRITÉRIO criterio-4 tipo=PERGUNTA] subitem (4): cansaço, respiração rápida e chiado no peito
[NÍVEL adequado pontos=0,7 mínimo=3] Investiga 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,35 mínimo=2] Investiga 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-03] Anamnese — sinais de gravidade
[CRITÉRIO criterio-1 tipo=PERGUNTA] subitem (1): aceitação das mamadas em relação ao habitual
[CRITÉRIO criterio-2 tipo=PERGUNTA] subitem (2): diurese (número de fraldas molhadas por dia)
[CRITÉRIO criterio-3 tipo=PERGUNTA] subitem (3): episódios de apneia ou cianose
[CRITÉRIO criterio-4 tipo=PERGUNTA] subitem (4): vômitos e diarreia
[NÍVEL adequado pontos=0,7 mínimo=3] Investiga 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,35 mínimo=2] Investiga 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-04] Anamnese — antecedentes, medicações e vacinação
[CRITÉRIO criterio-1 tipo=PERGUNTA] subitem (1): idade gestacional, peso ao nascer e intercorrências neonatais (prematuridade, UTI neonatal)
[CRITÉRIO criterio-2 tipo=PERGUNTA] subitem (2): sibilância prévia, internações e cardiopatia congênita
[CRITÉRIO criterio-3 tipo=PERGUNTA] subitem (3): medicações em uso e alergias
[CRITÉRIO criterio-4 tipo=PERGUNTA] subitem (4): situação vacinal
[CRITÉRIO criterio-5 tipo=SOLICITAÇÃO impressos=impresso-3-caderneta] subitem (5): solicita a Caderneta da Criança para conferir vacinas e curva de crescimento
[NÍVEL adequado pontos=0,6 mínimo=4] Realiza 4 ou 5 critérios.
[NÍVEL parcialmente_adequado pontos=0,3 mínimo=2] Realiza 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza 1 critério ou nenhum.

[ITEM item-05] Anamnese — contexto epidemiológico, hábitos e família
[CRITÉRIO criterio-1 tipo=PERGUNTA] subitem (1): contato com pessoas resfriadas e frequência a creche dos contactantes
[CRITÉRIO criterio-2 tipo=PERGUNTA] subitem (2): exposição à fumaça de cigarro no domicílio (tabagismo passivo)
[CRITÉRIO criterio-3 tipo=PERGUNTA] subitem (3): tipo de aleitamento
[CRITÉRIO criterio-4 tipo=PERGUNTA] subitem (4): asma ou atopia na família
[NÍVEL adequado pontos=0,5 mínimo=3] Investiga 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,25 mínimo=2] Investiga 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Investiga 1 critério ou nenhum.

[ITEM item-06] Exame físico e verbalização dos achados
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-1-exame-fisico] subitem (1): solicita o exame físico segmentar com contagem da FR em 1 minuto e oximetria de pulso
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] subitem (2): verbaliza desconforto respiratório (FR 64 irpm, tiragem subcostal e intercostal, batimento de asa nasal)
[CRITÉRIO criterio-3 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] subitem (3): verbaliza ausculta com expiração prolongada, sibilos expiratórios difusos e crepitantes finos bibasais
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-1-exame-fisico] subitem (4): verbaliza hipoxemia (SpO2 89% em ar ambiente) e desidratação leve (mucosas discretamente secas)
[NÍVEL adequado pontos=1,0 mínimo=3] Realiza 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,5 mínimo=2] Realiza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza 1 critério ou nenhum.

[ITEM item-07] Exames complementares
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-2-painel-viral] subitem (1): solicita pesquisa de vírus respiratórios em aspirado de nasofaringe para orientar o isolamento hospitalar
[CRITÉRIO criterio-2 tipo=VERBALIZAÇÃO após=impresso-2-painel-viral] subitem (2): identifica o vírus sincicial respiratório (VSR) detectado por RT-PCR
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] subitem (3): explica que o diagnóstico é clínico e que radiografia de tórax, hemograma e PCR não são indicados de rotina
[NÍVEL adequado pontos=0,6 mínimo=3] Realiza os 3 critérios.
[NÍVEL parcialmente_adequado pontos=0,3 mínimo=2] Realiza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza 1 critério ou nenhum.

[ITEM item-08] Hipótese diagnóstica e classificação de gravidade
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] subitem (1): formula a hipótese de bronquiolite viral aguda (primeiro episódio de sibilância em lactente menor de 2 anos após pródromo de vias aéreas superiores)
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): classifica como bronquiolite com indicação de internação, citando SpO2 menor que 92%, FR acima de 60 irpm com tiragem e aceitação alimentar menor que 50%
[NÍVEL adequado pontos=1,2 mínimo=2] Realiza os 2 critérios.
[NÍVEL parcialmente_adequado pontos=0,6 mínimo=1] Formula a hipótese sem classificar a gravidade.
[NÍVEL inadequado pontos=0 mínimo=0] Não formula a hipótese de bronquiolite viral aguda.

[ITEM item-09] Conduta — suporte respiratório e internação
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO OBRIGATÓRIO] subitem (1): prescreve oxigênio por cateter nasal de baixo fluxo, 0,5 a 1 L/min (até 2 L/min), com alvo de SpO2 igual ou maior que 92%
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): indica internação em enfermaria pediátrica, com transferência pela central de regulação em uso de oxigênio
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] subitem (3): indica monitorização contínua com oximetria de pulso e reavaliação seriada de FR, FC e esforço respiratório
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] subitem (4): indica precauções de contato e gotículas e higienização das mãos
[CRITÉRIO criterio-5 tipo=COMUNICAÇÃO] subitem (5): posiciona a lactente com cabeceira elevada a 30 graus
[NÍVEL adequado pontos=1,4 mínimo=4] Realiza 4 ou 5 critérios.
[NÍVEL parcialmente_adequado pontos=0,7 mínimo=2] Realiza 2 ou 3 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Não prescreve oxigênio suplementar.

[ITEM item-10] Conduta — desobstrução, hidratação e sintomáticos
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] subitem (1): prescreve lavagem nasal com soro fisiológico 0,9%, 0,5 a 1 mL por narina, seguida de aspiração das vias aéreas superiores antes das mamadas
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): mantém aleitamento materno fracionado e indica sonda nasogástrica ou hidratação venosa com solução isotônica se a aceitação persistir insuficiente ou a FR passar de 60 a 70 irpm
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] subitem (3): prescreve paracetamol 10 a 15 mg/kg por dose (6 a 9 gotas da solução de 200 mg/mL) por via oral, até de 6/6 h se febre
[CRITÉRIO uso-de-medicacoes-ineficazes tipo=COMUNICAÇÃO PROIBIDO] subitem (4): prescreve salbutamol inalatório, corticoide sistêmico (prednisolona) ou antibiótico (amoxicilina) de rotina
[NÍVEL adequado pontos=1,2 mínimo=3] Realiza os 3 critérios.
[NÍVEL parcialmente_adequado pontos=0,6 mínimo=2] Realiza 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Realiza 1 critério ou nenhum, ou prescreve broncodilatador, corticoide ou antibiótico de rotina.

[ITEM item-11] Orientações preventivas
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO] subitem (1): orienta a cessação do tabagismo domiciliar e oferece ao pai o tratamento do tabagismo na UBS
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO] subitem (2): orienta higiene das mãos e evitar o contato próximo da lactente com o irmão sintomático
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO] subitem (3): reforça o aleitamento materno exclusivo até os 6 meses
[NÍVEL adequado pontos=0,5 mínimo=2] Realiza 2 ou 3 critérios.
[NÍVEL parcialmente_adequado pontos=0,25 mínimo=1] Realiza 1 critério.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhum critério.

[ITEM item-12] Comunicação e Resolução de Dúvidas
[CRITÉRIO criterio-1 tipo=COMUNICAÇÃO perguntas=duvida-mae-01] subitem (1): justifica a internação pela hipoxemia, pelo desconforto respiratório e pela baixa aceitação alimentar, e explica que a nebulização em casa não substitui o oxigênio
[CRITÉRIO criterio-2 tipo=COMUNICAÇÃO perguntas=duvida-mae-02] subitem (2): explica que a causa é viral e que antibiótico, xarope, corticoide e broncodilatador não são indicados
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO perguntas=duvida-mae-03] subitem (3): informa recuperação completa na maioria dos casos, tosse por 2 a 4 semanas e possibilidade de sibilância recorrente sem diagnóstico de asma
[CRITÉRIO criterio-4 tipo=COMUNICAÇÃO] subitem (4): mantém postura empática e linguagem acessível, sem jargões
[NÍVEL adequado pontos=1,3 mínimo=3] Cumpre 3 ou 4 critérios.
[NÍVEL parcialmente_adequado pontos=0,65 mínimo=2] Cumpre 2 critérios.
[NÍVEL inadequado pontos=0 mínimo=0] Cumpre 1 critério ou nenhum.
