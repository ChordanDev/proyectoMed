# PRD Maestro de Producto — MVP Revisado

> Borrador en proceso de reescritura alineado al MVP rebasado. Esta versión todavía no está congelada.

## 1. Propósito

Plataforma educativa independiente para médicos formados en el extranjero que se preparan para la etapa práctica de Revalida.

Permite practicar estaciones clínicas similares a Revalida, recibir retroalimentación estimada basada en evidencia, comprender las acciones realizadas u omitidas e identificar cómo mejorar.

La plataforma:

- No está afiliada a INEP.
- No emite calificaciones ni certificaciones oficiales.
- No garantiza la aprobación.

## 2. Resultado del MVP (rebased)

El producto mínimo viable valida una única capacidad de aprendizaje: un médico completa **una estación clínica original** por voz o texto y recibe una devolución accionable sobre qué acciones realizó correctamente, qué omitió, por qué importan y qué practicar después.

No es una certificación ni una afirmación de que el médico está listo para Revalida.

## 3. Usuarios

### 3.1 Estudiante (único rol del MVP)

Médico formado en el extranjero que prepara la etapa práctica de Revalida. Usa la app sin cuenta, sin suscripción y sin historial personal retenido.

### 3.2 Socio de contenido (fuera de la app)

Profesional responsable de preparar cada estación clínica como un paquete versionado con: contexto clínico, hechos que el paciente IA puede revelar, reglas de respuesta, acciones esperadas y criterios de feedback. No interactúa con el sistema.

### 3.3 Propietario del proyecto (fuera de la app)

Encargado de reclutar participantes y medir, fuera del sistema, si el MVP cumple el criterio de continuación.

## 4. Principios del producto

- **Independencia educativa:** nunca insinuar afiliación con INEP ni carácter oficial.
- **Evidencia antes que veredicto:** el feedback se basa en criterios de la rúbrica preparada por el socio, no en notas globales.
- **IA acotada al paquete:** la IA no inventa hechos clínicos; opera sólo sobre el contenido del paquete preparado por el socio.
- **Incertidumbre explícita:** los criterios sin evidencia suficiente permanecen inciertos.
- **Práctica bajo presión:** cronómetro visible de diez minutos, mecánicas similares a Revalida.
- **Tratamiento justo de fallas:** las fallas técnicas invalidan la estación sin penalizar al usuario.
- **Minimización de datos:** no se conservan cuentas ni historiales personales.

## 5. Alcance del MVP

### Incluido

- Una estación clínica original, en portugués brasileño, preparada por el socio como paquete versionado.
- Experiencia conversacional por voz y texto en iOS y Android, vía Expo Go.
- Paciente IA que responde con voz sintetizada y texto visible, siguiendo sólo los hechos preparados.
- Cronómetro de diez minutos con cuenta regresiva visible.
- Finalización manual o automática por tiempo.
- Devolución accionable por criterio (cumple, omite, incierto) con fragmentos de la transcripción que justifican cada uno.
- Pantalla de aviso educativo antes de la estación.
- Datos efímeros de la sesión eliminados al salir del resultado o por expiración corta.
- Distribución interna del MVP vía Expo Go; sin publicación en stores.

### Excluido del MVP

- Panel médico, gestión de cuentas, suscripciones, pagos o facturación.
- Historial personal de intentos o transcripciones retenidas en el servidor.
- Material oficial de Revalida, público o interno.
- Simulación encadenada de diez estaciones, pacientes 3D, comunidad o red social.
- Integraciones con proveedores externos de IA que excedan el procesamiento necesario para una estación.

## 6. Flujo del usuario

1. Abre la app.
2. Lee la pantalla de aviso (herramienta educativa independiente; no evalúa Revalida; no ingresar datos de pacientes reales).
3. Inicia la estación cronometrada de diez minutos.
4. Conversa con el paciente IA por voz o texto; ve texto en pantalla y escucha su respuesta.
5. Finaliza manualmente o espera al cronómetro.
6. Ve la devolución por criterio con la transcripción destacada.
7. Sale de la pantalla de resultado; los datos de la sesión se eliminan.

## 7. Criterios de calidad del MVP

- La conversación sigue las reglas del paquete preparado; el paciente IA no inventa hechos clínicos.
- Cada criterio del feedback se acompaña de evidencia extraída de la transcripción o se marca como incierto.
- Si voz, transcripción o conectividad fallan durante la estación, se invalida sin feedback parcial ni penalización.
- El aviso educativo aparece antes de iniciar la estación.
- El MVP se entrega como una sola app Expo funcionando en iOS y Android vía Expo Go.

## 8. Criterio de continuación

El MVP merece seguir construyéndose cuando los participantes del piloto pueden completar la estación sin ayuda y explicar qué hicieron bien, qué omitieron y qué practicarían después gracias al feedback. La evaluación la realiza el propietario del proyecto fuera de la app.

## 9. Límites y responsabilidades

- La app no certifica preparación ni emite calificaciones oficiales.
- La IA no crea contenido clínico ni lo improvisa.
- El piloto lo recluta y opera el propietario del proyecto.
- El contenido clínico lo prepara el socio de contenido fuera de la app.
- Cualquier dato personal clínico está prohibido.

## 10. Trabajo técnico previsto

Para entregar el MVP, el equipo trabaja en cuatro frentes coordinados:

1. **Contrato API y modelo de estación** — define el paquete versionado y los endpoints entre cliente y servidor.
2. **Backend Phoenix** — ejecuta la conversación, valida el paquete, aplica la rúbrica y expone la devolución.
3. **Frontend Expo** — voz y texto, cronómetro, transcripción visible y pantalla de feedback.
4. **Integración y verificación** — pruebas end-to-end en iOS y Android vía Expo Go.

## 11. Decisiones diferidas (no del MVP)

- Cuentas, historial personal y persistencia de datos.
- Comercialización, suscripciones y límites de uso.
- Autorización de médicos para revisión clínica.
- Materiales oficiales de Revalida.
- Publicación en App Store o Play Store.
- Escalado a múltiples estaciones, pacientes 3D y simulación encadenada.
