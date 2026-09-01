## Propuesta de tickets para el MVP

Tickets en orden de dependencia (los bloqueantes primero). Cada uno es una vertical slice fina que entrega comportamiento observable.

| # | Título | Bloqueado por | Lo que entrega |
|---|--------|---------------|----------------|
| 1 | Restablecer runtime Expo en este checkout | Ninguno | `mobile/` queda operativo; `scripts/test.sh` corre Jest + ExUnit en verde desde `main`. |
| 2 | Definir formato del Station Package + `Backend.StationLoader` | #1 | Phoenix levanta un paquete válido desde `priv/stations/<id>/package.json` y falla ruidosamente si está malformado. |
| 3 | Sesión efímera en `Backend.Conversation` con expiración | #2 | `start/append/complete/fetch` cubren el ciclo de sesión y expiran tras un timeout corto. |
| 4 | `Backend.StationAI` acotado al paquete | #3 | El paciente IA responde solo con `revealable_facts` y `response_rules`; nunca inventa. |
| 5 | `Backend.Evaluator` con feedback por criterio | #3 | Dado un paquete y transcripción final, devuelve `met/omitted/uncertain + evidence` por criterio. Sin score global. |
| 6 | `BackendWeb.StationController` + router `/api/stations` | #4, #5 | Endpoints JSON `active`, `sessions`, `messages`, `finish`, `result` con códigos 404/410. |
| 7 | Cliente Expo: `client.ts` + `useStation` + `NoticeScreen` + i18n pt-BR | #6 | La app muestra el aviso, llama a la API y maneja errores tipados. |
| 8 | Pantallas Expo `StationScreen` + `ResultScreen` con voz, cronómetro y feedback | #7 | El usuario practica la estación completa y ve la devolución con destacados. |

Ticket extra (no numerado para evitar confusión con la numeración de bloqueantes; vive como **#9 Integración y verificación** y se desbloquea con todos los anteriores):

| # | Título | Bloqueado por | Lo que entrega |
|---|--------|---------------|----------------|
| 9 | Integración end-to-end vía `scripts/test.sh` | #8 | Test de integración boot-eando Phoenix desde Jest y validando el flujo completo. Verifica pt-BR, cronómetro, fallo técnico y expiración. |

---

### ¿Te cierra este corte?

- Granularidad: 8 tickets, cada uno demoable por separado y ≤800 líneas.
- Dependencias: backend en orden lineal (#1→#2→#3→#4/#5→#6); frontend engancha después (#7→#8); integración al final.
- Paralelismo: #4 (Station AI) y #5 (Evaluator) podrían hacerse en paralelo con dos devs distintos porque comparten sólo el contrato del paquete.
- No se rompe la regla "un ticket = vertical slice completa".

¿Ajusto algo antes de publicar las issues?