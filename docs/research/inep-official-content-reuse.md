# Reusing INEP's published Revalida stations inside a paid product

**Decision of 2026-10-30:** the product does not publish INEP cases. Every case is our own, validated by a doctor, and aims for the same quality and structure as the published stations (#476, #485, #486, #487). The rule in `CONTEXT.md` and the ADR-012 amendment on #124 stays as it is.

Compiled on 2026-10-30. Question: may a private Brazilian company legally reproduce and adapt, inside a paid simulator, the practical-exam stations INEP published for the Revalida (the `Instruções ao participante` and the `Padrão Esperado de Procedimentos`, PEP), labelled as "based on official INEP cases"? Feeds the decision about whether the catalog may include INEP stations. The list of published stations is in `docs/research/revalida-published-stations.md`.

**This is research for a founder, not legal advice. A Brazilian IP lawyer must confirm the conclusion before launch.** The direct answer is at the end (section 8): in short, **unclear**. No source I reached grants permission to adapt INEP's text, one licence signal points against adaptation, and the label raises a separate question. The clinical content itself (the idea and method layer) looks free to reuse.

## 1. Method and source policy

- Primary sources only: statute text from the official Câmara dos Deputados copy of each law (Planalto blocks automated access, see section 9), court pages, INEP and gov.br pages, the Revalida editais published in the Diário Oficial da União (DOU), INEP PDFs, the Creative Commons legal code, CFM resolutions. Blogs and news sites are cited only where the court's own page was unreachable or for the market-practice signal, and are labelled.
- Every claim is tagged one of three ways:
  - **Source says**: the text of a statute, edital, licence or court page that I read.
  - **Not settled**: no source I reached answers it.
  - **Inference**: my own reasoning from the sources. Treat as a hypothesis for the lawyer.
- Quotes are short fragments (under 15 words, at most one per source); everything else is paraphrase.
- Sample of INEP PDFs opened and searched (text layer via `pdftotext`, plus rendered cover pages): 2020 prova ([P-2020]), 2025/2 prova ([P-2025-2]), 2023/1 PEP ([E-2023-1]), 2024/2 PEP ([E-2024-2]). The 2023/1 prova never finished downloading (INEP's download host is slow and drops connections) and was not read. Scratch files were kept outside the repository in the session scratchpad.
- Editais read in full text: Edital INEP nº 14/2026 (2ª etapa, edição 2025/2), nº 86/2025 (1ª etapa, 2025/2), nº 2/2021 and nº 7/2023 (calls for item writers for Revalida and other medical exams), nº 160/2026 (item-writer call for another exam). The 2023/1 to 2025/1 second-stage editais were not read; they are assumed similar (inference).

## 2. Statute: Lei 9.610/1998 (Lei de Direitos Autorais)

Text read from the Câmara's original-publication copy and cross-checked against its consolidated copy for arts. 8, 33 and 47 ([L9610-C], [L9610-A]).

### 2.1 What the law says

| Provision | Content (paraphrased unless quoted) |
|---|---|
| Art. 7 caput, items I and XIII | Protected works are creations of the mind fixed in any medium, including texts and compilations whose selection or arrangement is a creation. |
| Art. 7 §3 | In science, protection falls on the literary or artistic form, not on the scientific or technical content. |
| Art. 8 I | Ideas, normative procedures, systems, methods and projects "as such" are not protected. |
| Art. 8 III | Blank forms and their instructions are not protected. |
| Art. 8 IV | Texts of treaties, laws, decrees, regulations, judicial decisions "demais atos oficiais" are not protected. |
| Art. 8 VII | The industrial or commercial use of the ideas contained in works is not protected. |
| Art. 4 | Legal transactions about copyright are interpreted restrictively. |
| Art. 11 and sole paragraph | The author is the natural person who creates the work; protection may extend to legal entities only in the cases the law provides. |
| Art. 5 VIII h; art. 17 §2 | A collective work is created on the initiative and responsibility of a person or entity; the organiser holds the economic rights over the whole, while individual contributions stay protected (art. 17 caput). |
| Arts. 49 and 50 | Economic rights can be assigned or licensed; any assignment must be in writing and is presumed paid. |
| Art. 27; art. 24 II and IV | Moral rights are inalienable and unwaivable; they include being credited and opposing modifications that harm the work or the author's honour. |
| Art. 29 I, II, X; art. 33 | Reproduction, edition and any other use need the author's prior and express authorization; nobody may reproduce a protected work "to annotate, comment or improve" it without permission. |
| Art. 46 II, III, VII, VIII | Exceptions: single private copy without profit; quotation for study, criticism or polemic to the extent justified, with credit; use to produce judicial or administrative evidence; small excerpts of pre-existing works when the reproduction is not the main purpose and does not harm normal exploitation. |
| Art. 47 | Paraphrases and parodies are free if they are not true reproductions of the original and do not discredit it. |
| Art. 41 | Economic rights last 70 years from 1 January of the year after the author's death. |
| Arts. 102 to 109 | Remedies: seizure and suspension, loss of copies, joint liability of whoever sells or distributes infringing copies for gain, injunction against transmission, destruction, damages. |
| Art. 6 | Works only subsidised by the State do not become State property. |

I found no provision in this law that makes works produced by or for the State free by default. The only State-related carve-out is the list in art. 8 IV, and the only mention of state ownership (art. 6) points the other way (subsidy alone does not transfer rights). **Inference:** there is no general "government works are in the public domain" rule in this statute; if one exists it is elsewhere and I did not find it.

### 2.2 Does an exam prova count as an "ato oficial"?

- **Source says:** art. 8 IV lists treaties, laws, decrees, regulations and judicial decisions, then closes with the general category of other official acts. The statute does not define the category.
- **Not settled:** I found no court decision or doctrine from a primary source applying art. 8 IV to exam papers, stations or answer keys. The one court decision I found on exam questions (section 3) does not rely on art. 8 IV in the pages I read.
- **Inference (argument for protection being excluded):** the PEP is the criterion INEP uses to score candidates and it is formally challenged through appeals and republished in definitive versions (Edital 14/2026 items 14.3 to 14.7), so it behaves more like an administrative standard than a stem. A court could treat it as an official act.
- **Inference (argument against):** the listed examples are all normative or adjudicative texts; a closing general category is usually read in line with them. A clinical case stem written for an exam is closer to an educational text than to a norm. I read art. 8 IV as a weak basis for the stem and a plausible but untested basis for the PEP checklist. A lawyer should assess this, since it is the strongest "free to use" argument and the one with the least support.

### 2.3 Does it matter that outside authors wrote the items?

- **Source says:** the author is a natural person (art. 11). An entity can hold the economic rights through a written assignment or licence (arts. 49 and 50), or as organiser of a collective work (art. 17 §2). Moral rights stay with the individual and cannot be assigned (art. 27).
- **Source says (editais 2/2021 and 7/2023, calls for item writers for Revalida and other medical exams):** collaborators sign a confidentiality term and undertake not to use or disclose the instruments they write, and to produce unpublished items. Neither edital contains a clause assigning copyright (I searched both texts for "autoral", "cessão", "titularidade", "propriedade" and found none).
- **Not settled:** who owns the economic rights in the Revalida station texts. I found no assignment term for Revalida item writers. Search results indicated that INEP's calls for some other exams (ENEM, ENCCEJA, vocational-education items) mention a "Termo de Cessão de Direitos Autorais", but I did not read those editais, and the one comparable call I did read (nº 160/2026) shows only a confidentiality term. The text of any assignment term was not found.
- **Inference:** if the assignment chain is incomplete or covers only INEP's own uses, permission from INEP alone might not be enough, and the individual authors' moral rights (credit, integrity) could be invoked against an adaptation. This is a question for the lawyer and, ultimately, for INEP.

### 2.4 Which parts are probably not protected at all

- **Source says:** the clinical content (diagnosis, expected conduct, scientific facts) is not protected (art. 7 §3, art. 8 I). Only the form is.
- **Inference:** the PEP is largely a checklist of expected procedures, which is method and technical content. The creative layer, if any, is in the narrative of the stem, the wording and ordering of the checklist, and the simulated-patient lines. Reproducing that wording is where the risk sits; re-expressing the same clinical situation independently is where it is lowest.

## 3. Case law

Searched: STF, STJ, TRF and state-court decisions on copyright in exam questions (concurso, ENEM, vestibular) and on commercial reproduction. I could not query the STF and STJ jurisprudence databases directly (they are interactive pages that did not load through my tools), so a negative result here is weak.

| Court | Reference | Date | What I could verify |
|---|---|---|---|
| TJSP, 3ª Câmara de Direito Privado | Apelação nº 1112376-68.2021.8.26.0100 ([TJSP-NEWS]; also reported by [CONJUR]) | Reported 2024-04-05 (TJSP page) and 2024-04-08 (Conjur); the judgment date is not on either page | Two associations that write and run professional-certification exams for the financial market sued a preparatory-course company for reusing past questions. The first instance dismissed the claim; the appeal court upheld it **by majority**. Per TJSP's page: the question bank was not a protected database, the questions lacked originality and fall within the statute's exclusions (it described writing questions as "um método de estudo ou avaliação"), and public disclosure and correction of questions serve the transparency of public exams. |

- **Not settled:** I found **no** STF, STJ or TRF decision on copyright in exam questions or on reusing INEP exams commercially. A search result attributed to the STF a statement that merely reproducing vestibular questions with the source cited does not infringe copyright; I could not reach the decision, its number or its date, and I do not rely on it. The STF Tema 485 (RE 632.853, 2015) that came up concerns judicial review of exam questions, not copyright.
- **Inference (weight of the TJSP decision):** it is a single, majority, state appellate decision; it is not binding on other courts; the plaintiffs were private associations; the content was multiple-choice items and a question bank, not narrative clinical stations with simulated-patient scripts; and I did not read the judgment itself or see whether a further appeal was filed. It supports the position that short exam questions are not protected, but it does not settle the question for station narratives and PEP checklists. The statement that disclosure supports public-exam transparency is helpful, but it is a policy argument, not a holding on reuse by a for-profit company.
- A decision unrelated to exams, about unauthorised reuse of an artist's work in apostilas distributed by a public body (STJ, reported by a law-firm blog only), appeared in results. I did not verify it and it does not bear on exam content, so it is not used.

## 4. INEP's own terms

### 4.1 Site-wide licence: CC BY-ND 3.0

- **Source says:** the footer of the INEP Revalida pages, including `Provas e Gabaritos` and `Orientações`, states that all content of "this site" is published under the licence "Atribuição-SemDerivações 3.0 Não Adaptada" ([INEP-PG], [INEP-REV], [INEP-ORI]). That is Creative Commons Attribution-NoDerivatives 3.0 Unported.
- **Source says (CC legal code 3.0, [CC-LEGAL]):** the licence grants worldwide, royalty-free, perpetual rights to reproduce the work, include it in collections and distribute it; commercial use is not excluded (there is no non-commercial limit in this version). It does **not** grant the right to make adaptations, beyond modifications technically necessary to use another medium. An "adaptation" is any work based on the original, including translations and arrangements. Attribution is required, copyright notices must be kept, and you may not imply the licensor's endorsement. The licence ends automatically on breach, and it states that it does not reduce any uses the law already allows ("Nothing in this License is intended to reduce, limit, or restrict any uses").
- **Not settled:** whether this footer licence covers the exam PDFs. The PDFs are hosted on a different host (`download.inep.gov.br`), and I found no licence notice inside any of the four PDFs I opened (section 4.2). The footer says "this site"; it is unclear whether linked downloads are part of it.
- **Inference:**
  - If the licence does cover the PDFs, then verbatim reuse with credit, even in a paid product, would be licensed, but **adapting** them (rewriting, adding an actor script, restructuring the case) is exactly what "NoDerivatives" excludes, so the product described in the question would fall outside the licence.
  - If the licence does not cover the PDFs, there is no licence at all and the default rule of art. 29 applies to anything that is protected.
  - A licence can only grant what the licensor holds. If INEP does not hold the economic rights over parts of a PDF (for example the item writers' rights, or third-party images), the licence would not clear those parts.
  - The licence adds nothing where the text is not protected in the first place (art. 8 and the TJSP reasoning): then neither the licence nor its NoDerivatives clause matters.
  - The ND clause also restricts the claim that you may "adapt freely and credit INEP". It gives a reason to keep station text out of the product even if the law is permissive.

### 4.2 Notices inside the PDFs

- **Source says (what I observed):** none of the four PDFs I opened and searched (2020 prova, 2025/2 prova, 2023/1 PEP, 2024/2 PEP; 34, 38, 55 and 59 pages) contains a copyright notice, "direitos reservados", a reproduction rule, a Creative Commons notice, or a confidentiality statement in the text layer. The rendered cover pages of the 2025/2 prova and the 2024/2 PEP show the **Revalida wordmark and edition** at the top and the **INEP logo** in the footer. The image-only parts were not OCR-read, so a notice printed as an image on a page I did not render would have been missed.
- **Source says:** the PDFs' Word metadata names individual authors. That is not a rights notice and says nothing about who owns the content (see 2.3).
- **Source says (recorded observation, correcting an assumption in the brief):** the PEP is **not** limited to a checklist. In the 2023/1 and 2024/2 PEPs, each station's síntese includes a list of what the simulated patient (or the simulated mother or father) "could say" if the participant asks the right questions, and the questions the simulated person would ask. I found this pattern by text search and did not read every station; the 2020 PEP is a scan and was not checked, and the 2025/2 PEP was not downloaded. The consequence is that INEP **does** publish part of an actor script, so our authored patient facts may overlap with INEP's expression more than assumed. For copyright purposes these lines are narrative content of the kind the law protects, not method.
- **Inference:** the absence of a notice does not remove protection (art. 18: protection does not depend on registration; I read this article in the same text, not quoted here). It only means INEP did not take the step of stating its position inside the files.

### 4.3 Editais (participant rules)

- **Source says (Edital 14/2026, 2ª etapa 2025/2; Edital 86/2025, 1ª etapa 2025/2):** neither text contains a clause on copyright, licence, intellectual property or ownership of the exam (searched for those terms). They do contain participant conduct rules: not to receive information about the content of the exam, not to record or disclose the exam or any material used in it by image, video or sound, and, for the clinical-skills stage, not to download or disclose the recordings of the stations even "ainda que para uso próprio e sem fins lucrativos" (items 11.1.26, 11.1.27, 12.1.7, 12.1.8, 12.1.8.1 and 14.10 of Edital 14/2026). Breach carries elimination from the exam.
- **Source says:** the same edital schedules the INEP publication of the stations and the preliminary PEP a couple of days after the exam (schedule table, "Divulgação das estações de prova e das versões preliminares dos PEP"). So the stations are published by INEP itself; the confidentiality rules protect the exam while it runs and the recordings, not the published papers.
- **Inference:** these rules bind candidates, not third parties. They matter to the product in one way: **do not source any station content from candidates' memories, notes or recordings of the exam**, and make sure the doctors who validate cases are not candidates who would be breaching the edital by contributing recollections. Using only the published PDFs avoids that.
- **Not settled:** whether the confidentiality rules reflect an INEP position that the published stations remain INEP-owned content. The editais do not say it.
- Item-writer calls (editais 2/2021 and 7/2023): see 2.3.

### 4.4 Lei 13.959/2019 and its regulations

- **Source says (Câmara text, current version, [L13959]):** the law creates the Revalida, sets its two stages, says it is coordinated by the federal public administration, and says the clinical-skills stage is held under an edital. It says nothing about copyright, publication or ownership of exam content, and it does not name a regulation on those points. The Câmara text lists amendments by MP 1.370/2026 to §3 I, §4 and §5 II; I did not check whether it has been converted into law, and none of the amended items touch this topic.
- **Source says:** Edital 14/2026 cites, as its legal basis, Lei 13.959/2019, Portaria Interministerial MEC/MS nº 278/2011, Portaria MEC nº 1.151/2023, Resolução CNE/CES nº 2/2024 and Portaria nº 530/2020. I did not read these four instruments. Search results describe Portaria MEC 1.151/2023 as being about the revalidation of foreign diplomas generally.
- **Not settled:** whether any of those instruments addresses ownership or reuse of exam content.

### 4.5 Does INEP state that the items belong to it?

- **Source says:** in the Revalida material I read, no. A different INEP document, the guide for item writers of another exam (BNI-Enade), states in its colophon that its own text may be reproduced in whole or part with the source cited, and separately marks the guide as restricted use. That concerns the guide, not exam items, and not Revalida.
- **Not settled:** INEP has not, in the pages I read, said either that the published stations are free to reuse or that they are reserved. A direct question to INEP (see section 8.3) may be the cleanest way to settle it.

## 5. Access to information and open-data terms

- **Source says (Lei 12.527/2011, LAI, original text, [L12527]):** art. 8 requires public bodies to publish information of collective interest proactively, on official sites, and art. 8 §3 requires machine-readable open formats. I searched the text for copyright, reuse and licence terms and found none. The LAI regulates access and transparency, not reuse rights.
- **Source says (Decreto 8.777/2016, Federal Executive open-data policy, as amended by Decreto 9.903/2019, [D8777-A]):** data made available by the federal Executive and active-transparency information "são de livre utilização pelos Poderes Públicos e pela sociedade" (art. 4 caput). A new §1 authorises free use of **databases and information under art. 7 XIII of Lei 9.610 (compilations) whose economic copyright holder is the União**. A §2 obliges the Executive to name third-party rights holders when it publishes protected databases. The decree defines "dados abertos" as data in open, machine-readable formats published under an open licence.
- **Not settled:** whether this decree reaches exam stations. Open questions: INEP is an autarchy (a separate legal entity from the União); the stations are narrative texts, not databases in the sense of art. 7 XIII; and §1 is limited to rights held by the União. I did not find INEP's Plano de Dados Abertos or any INEP open-data licence statement for exam papers (section 9).
- **Inference:** public availability does not by itself change copyright. The LAI and the decree are arguments, not permissions, for reuse of the stations; the decree's art. 4 caput is the most helpful text I found, but it is aimed at data publication policy and has not been applied to exam papers in any source I read. Treat as an argument for the lawyer.

## 6. Labels and trademarks

- **Not reached:** the INPI trademark database (`busca.inpi.gov.br`) did not respond to my tools. I therefore **cannot say** whether "INEP", "Revalida" or the Revalida wordmark and logo are registered marks, nor in which classes. A web search surfaced no evidence of a registration either way; that is not proof of absence.
- **Source says (Lei 9.279/1996, [L9279]):**
  - Art. 124 I and IV: official emblems and the designation or acronym of a public body cannot be registered as a mark by others, unless the body itself applies. This suggests INEP's name and acronym are protected from third-party registration, not that INEP has registered them.
  - Art. 132 IV: a mark owner cannot stop citation of the mark in a publication "desde que sem conotação comercial". A paid product advertising the INEP name is commercial, so this safe harbour would not obviously apply. Art. 132 has no express rule for descriptive references to an exam's name in advertising.
- **Source says (CDC, Lei 8.078/1990, [CDC]):**
  - Art. 36: advertising must be identifiable as advertising, and the advertiser must keep the factual and technical data that support the message.
  - Art. 37 §1: advertising is misleading if wholly or partly false, or by any means, including omission, "capaz de induzir em erro o consumidor" about nature, characteristics, quality or **origin**.
  - Art. 38: the advertiser bears the burden of proving the truth of the claim.
- **Not settled:** I found no statute or decision specifically on "false association" with a public body, or on nominative references to an official exam in commercial advertising. I did not read Lei 9.279 art. 195 (unfair competition).
- **Inference on the label "baseado em caso oficial do INEP":**
  - Accurate and neutral wording about the *origin of the clinical situation* is easier to defend than wording that implies *the station itself, or an official reproduction*. A station rewritten, with an invented patient script validated by our doctors, is not "an official case"; calling it one could be read as misleading about origin (CDC art. 37 §1), and under art. 38 the burden would fall on us.
  - The label can imply endorsement or affiliation with INEP even if literally true. A reader could think INEP licensed or reviewed the station. A visible "not affiliated with or endorsed by INEP" notice reduces that risk but does not remove it.
  - Do not use the INEP logo or the Revalida wordmark and edition artwork seen on the PDFs: they are visual identity elements, not text, and I found no permission to use them.
  - The CC BY-ND legal code (attribution section) also forbids implying a licensor's endorsement; this applies if we rely on that licence.

## 7. Medical regulation and market practice

### 7.1 CFM and MEC

- **Source says:** I found no CFM or MEC rule restricting the use of official exam content in commercial preparatory products. Resolução CFM 2.336/2023 (medical advertising, [CFM-2336]) binds doctors and medical establishments; art. 9 XIII allows courses for doctors to discuss clinical cases if participation is restricted to registered physicians and confidentiality is observed, and art. 9 XII bars teaching acts reserved to doctors to lay audiences. Resolução CFM 2.277/2020 ([CFM-2277]) governs medical establishments' conduct towards students from foreign universities and cites the Revalida law; it does not address exam material. Its recitals cite the Medical Act (Lei 12.842/2013, art. 5 III and IV) for the rule that teaching medical disciplines is reserved to doctors.
- **Inference:** these rules say nothing on INEP content. The one practical point is that clinical content in an educational product should be authored and validated by registered physicians, which the plan already includes. Whether the CFM would treat the product as "advertising by a medical establishment" depends on who runs it; I did not analyse that. I did not read the Medical Act itself, only the recital that cites it.
- **Not settled:** MEC rules beyond those cited in the edital (not read). The Revalida reference matrix (Portaria Inep nº 540/2020) is cited in INEP editais but I did not read it.

### 7.2 Market practice (weak signal only, not proof of legality)

- Two large Brazilian prep companies (Medway, Estratégia MED) publish pages on the 2025/2 PEP that summarise the exam and host copies of INEP's PDFs on their own servers; neither page reproduces the station text in the page body ([MEDWAY], [ESTRATEGIA]). Their page titles also advertise commented corrections of Revalida stations (I did not open any paid product). I did not find an INEP complaint against any prep company, but I did not search for one beyond a single web query.
- Their practice is **mirroring and commenting**, not rewriting INEP cases into a new product with an invented actor script. Mirroring may rely on different reasoning (for example, the public-availability arguments or the CC verbatim permission, if it applies) than adaptation does.
- **Inference:** tolerance by INEP so far, if it exists, is consistent with INEP not objecting to commentary and mirroring. It says nothing about derivative products. No company is a safe harbour for another; absence of enforcement is not a licence.

## 8. Conclusion

### 8.1 Direct answer

**Unclear, with two different answers for two layers.**

1. **The clinical idea layer** (the diagnosis, setting, tasks and expected conduct as such): **likely allowed**. The law excludes ideas and methods (art. 8 I) and the technical content of science (art. 7 §3), and it protects only expression. I found no source that restricts this layer.
2. **The expression layer** (the stem wording, the PEP wording and ordering, the simulated-patient lines, images): **unclear, leaning not safely allowed for adaptation**. No source I reached permits adaptation. The only reuse permission in sight is the CC BY-ND 3.0 footer, which (if it even covers the PDFs) excludes adaptation. Art. 8 IV ("demais atos oficiais") is an untested argument. The single exam-question decision (TJSP) favours reuse but is narrow, non-binding and not about stations. The ownership chain (outside authors) is not documented in a source I could read.
3. **The label** "based on official INEP cases" adds a separate risk (misleading origin or implied endorsement, CDC art. 37; unknown trademark status). It is lower risk when accurate and visibly non-affiliated, higher when the station was modified.

The current internal rule (no reproduction of official content) is not required by any statute I found, but it is a defensible conservative position because of the ND clause and the ownership gap. The existing note in `revalida-published-stations.md` (scripts must be authored from clinical guidelines) fits it.

### 8.2 Safest way to use the material

Ordered from most to least conservative:

1. **Use only the idea layer.** From each INEP station, take only facts a clinician would take from a guideline: the case type, setting, area, tested competencies, and the general expected conduct. Write the stem, patient script and checklist **from scratch from clinical guidelines**, with doctors validating. Do not copy the PEP's wording, ordering, scoring items or patient lines (the 2023/1 and 2024/2 PEPs publish patient facts, so check overlaps). Do not reuse INEP images, printed exam sheets or photos (they may be third-party works).
2. **Describe provenance neutrally**, for example "inspired by the clinical situation assessed in Revalida YYYY/N, station X", with a visible statement that the product is independent and not affiliated with or endorsed by INEP. Avoid "official case", INEP or Revalida logos, and edition artwork.
3. **Keep a provenance log**: for each case, the INEP document used, what was taken (idea only), who wrote and validated the text, from which guidelines. It supports the burden of proof under CDC art. 38 and any later copyright defence.
4. **Do not source content from candidates' recollections or recordings** of the exam (edital rules, section 4.3).
5. **If you want to use INEP text or label cases as official**, ask INEP in writing for authorization, naming the exact use, and ask it to confirm the ownership chain. A written authorisation for adaptation would also deal with the ND clause and any moral-rights question about the item writers.
6. **Link to INEP's own PDFs** rather than hosting copies, where you want users to see the original. This is an inference: linking is not reproduction, but I found no source on it.

### 8.3 Questions for the Brazilian IP lawyer

1. Does a Revalida station (stem, simulated-patient lines) have enough originality to be a protected work, in light of the TJSP decision, and does art. 8 IV or art. 7 §3 exclude any part of it? Is the PEP, as the scoring standard, an "ato oficial"?
2. Does the CC BY-ND 3.0 footer on gov.br/inep cover the PDFs on `download.inep.gov.br`? If it does, does our product (rewriting plus a new patient script) count as an adaptation outside the licence?
3. Who owns the economic rights over the stations: INEP (and by what instrument) or the item writers? Do the editais 2/2021 and 7/2023, which require confidentiality but show no assignment, leave the item writers' rights untouched? What do the Revalida item writers' confidentiality terms add?
4. Is paraphrase (art. 47) or small-excerpt use (art. 46 VIII) a safe route for a station re-expressed from the original, and where is the line against "true reproduction"?
5. Does Decreto 8.777/2016 art. 4 (as amended by Decreto 9.903/2019) give any reuse right over INEP exam papers, given INEP is an autarchy and the stations are narrative texts?
6. Is "INEP" or "Revalida" registered at INPI, and in which classes? Can the names be used descriptively in paid advertising ("based on", "inspired by"), and what disclaimer is enough? (Lei 9.279 arts. 124 IV, 132 IV, 195; CDC arts. 36 to 38.)
7. Would a written request to INEP for authorization be advisable, or would it create a record that weakens our position if INEP refuses?
8. If doctors who sat the Revalida validate our stations, is there any risk under the edital's confidentiality rules or under their own obligations?
9. Remedies exposure: what would an injunction (arts. 102 to 105) or a damages claim cost for a subscription product, and is there advantage in an opinion letter before launch?

### 8.4 What would change the answer

- **To "allowed":** a written INEP statement or licence that covers the PDFs and allows derivatives (or a CC licence without ND); a court decision (STJ or a TRF) applying art. 8 IV or the originality reasoning to Revalida-type content; documented assignment of the item writers' rights to INEP plus an INEP authorization; a lawyer's conclusion that the station text is unprotected.
- **To "forbidden":** INEP stating the exam content is reserved or that the CC footer does not cover the PDFs; evidence that item writers retained their rights; a decision protecting station narratives or checklists as works; INPI registrations of INEP/Revalida in relevant classes combined with a misleading label; an INEP complaint or notice to any prep company.
- **Either way:** if the product reuses images, printed sheets, ECGs or photos from the PDFs, or if our patient script tracks INEP's published patient lines closely, the risk goes up regardless of the answer on the idea layer.

## 9. Sources I could not reach or read

- **Planalto (`planalto.gov.br`)** returned an "access denied" block to every tool (browser pane, web fetch, curl). Statutes were read from the Câmara's copy instead: Lei 9.610 original text plus its consolidated text, Lei 13.959 consolidated text, and the *original publications* of Lei 9.279, Lei 8.078 and Lei 12.527. Later amendments to those three laws were not cross-checked, so confirm arts. 36 to 38 (CDC), art. 132 (Lei 9.279) and art. 8 (LAI) are still in force as read. Decreto 8.777/2016 was read both as originally published and in the consolidated PDF.
- **INPI trademark database**: unreachable (connection timed out).
- **STF and STJ jurisprudence portals**, JusBrasil, and the STJ revista eletrônica: not reachable or blocked (HTTP 403 or interactive pages). No decision was verified from a court's own database. The TJSP page is a court news page, not the judgment.
- **INEP 2023/1 prova PDF**: download incomplete; not read. 2025/2 PEP, 2020 PEP (scanned), and the other editions' PDFs were not opened.
- **Editais of 2023/1 to 2025/1 second stage**: not read. **Portarias** MEC 1.151/2023, MEC/MS 278/2011, INEP 530/2020 and 540/2020 and Resolução CNE/CES 2/2024: not read.
- **INEP's Plano de Dados Abertos** and any open-data licence statement: not found.
- **INEP item-writer assignment terms for Revalida** (Termo de Cessão, if any): not found.
- **Lei 12.842/2013 (Medical Act)**: cited from a CFM recital only.
- **Lei 9.279 art. 195**: not read.
- **INEP and gov.br "Termos de uso"**: no general gov.br terms-of-use page for INEP content surfaced; the footer licence is the only terms text I found.

## References

Statutes and regulations

[L9610-C]: https://www2.camara.leg.br/legin/fed/lei/1998/lei-9610-19-fevereiro-1998-365399-publicacaooriginal-1-pl.html
[L9610-A]: https://www2.camara.leg.br/legin/fed/lei/1998/lei-9610-19-fevereiro-1998-365399-normaatualizada-pl.html
[L9610-PLANALTO] (blocked to my tools): https://www.planalto.gov.br/ccivil_03/leis/l9610.htm
[L13959]: https://www2.camara.leg.br/legin/fed/lei/2019/lei-13959-18-dezembro-2019-789607-normaatualizada-pl.html
[L12527]: https://www2.camara.leg.br/legin/fed/lei/2011/lei-12527-18-novembro-2011-611802-publicacaooriginal-134287-pl.html
[D8777-A]: https://www2.camara.leg.br/legin/fed/decret/2016/decreto-8777-11-maio-2016-783082-normaatualizada-pe.pdf
[D8777-O]: https://www2.camara.leg.br/legin/fed/decret/2016/decreto-8777-11-maio-2016-783082-publicacaooriginal-150347-pe.html
[L9279]: https://www2.camara.leg.br/legin/fed/lei/1996/lei-9279-14-maio-1996-374644-publicacaooriginal-1-pl.html
[CDC]: https://www2.camara.leg.br/legin/fed/lei/1990/lei-8078-11-setembro-1990-365086-publicacaooriginal-1-pl.html
[CFM-2336]: https://sistemas.cfm.org.br/normas/arquivos/resolucoes/BR/2023/2336_2023.pdf
[CFM-2277]: https://sistemas.cfm.org.br/normas/arquivos/resolucoes/BR/2020/2277_2020.pdf

Case law

[TJSP-NEWS]: https://www.tjsp.jus.br/Noticias/Noticia?codigoNoticia=97809
[CONJUR] (secondary, press): https://conjur.com.br/2024-abr-08/questoes-de-prova-nao-tem-protecao-de-direito-autoral-diz-tj-sp/

INEP, gov.br and licence

[INEP-PG]: https://www.gov.br/inep/pt-br/areas-de-atuacao/avaliacao-e-exames-educacionais/revalida/provas-e-gabaritos
[INEP-REV]: https://www.gov.br/inep/pt-br/areas-de-atuacao/avaliacao-e-exames-educacionais/revalida
[INEP-ORI]: https://www.gov.br/inep/pt-br/areas-de-atuacao/avaliacao-e-exames-educacionais/revalida/orientacoes
[INEP-LEG] (year tabs did not load): https://www.gov.br/inep/pt-br/centrais-de-conteudo/legislacao/revalida
[CC-LEGAL]: https://creativecommons.org/licenses/by-nd/3.0/legalcode
[CC-DEED]: https://creativecommons.org/licenses/by-nd/3.0/deed.pt_BR

Editais (DOU copies hosted by ABMES)

[ED-14-2026]: https://www.abmes.org.br/arquivos/legislacoes/Edital-inep-014-2026-03-12.pdf
[ED-86-2025]: https://abmes.org.br/arquivos/legislacoes/Edital-inep-086-2025-07-02.pdf
[ED-2-2021]: https://abmes.org.br/public/arquivos/legislacoes/Edital-inep-002-2021-01-21.pdf
[ED-7-2023]: https://abmes.org.br/public/arquivos/legislacoes/Edital-inep-007-2023-01-30.pdf
[ED-160-2026]: https://abmes.org.br/arquivos/legislacoes/edital-inep-no-160-2026-10-21-f987f11f.pdf
[GUIA-BNI-ENADE]: https://download.inep.gov.br/bni/enade/guia_de_elaboracao_revisao_de_itens_v1.pdf

INEP PDFs opened (data only)

[P-2020]: https://download.inep.gov.br/educacao_superior/revalida/provas/2020/habilidades_clinicas.pdf
[P-2025-2]: https://download.inep.gov.br/revalida/provas_e_gabaritos/2025_2_prova_habilidades_clinicas.pdf
[E-2023-1]: https://download.inep.gov.br/revalida/provas_e_gabaritos/2023_1_PEP_publicacao.pdf
[E-2024-2]: https://download.inep.gov.br/revalida/provas_e_gabaritos/revalida_2024_2_pep_definitivo.pdf

Market practice (weak signal)

[MEDWAY]: https://www.medway.com.br/conteudos/prova-pratica-do-revalida-2025-2-confira-o-pep-preliminar-e-recursos
[ESTRATEGIA]: https://med.estrategia.com/portal/noticias/revalida-inep-2025-2-pep-divulgado/

Related internal document: `docs/research/revalida-published-stations.md`.
