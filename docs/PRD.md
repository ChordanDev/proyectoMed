# BORRADOR — PRD Maestro de Producto

## 1. Propósito

Plataforma educativa independiente para médicos formados en el extranjero que se preparan para la etapa práctica de Revalida.

Permite practicar estaciones clínicas similares a Revalida, recibir retroalimentación estimada basada en evidencia, comprender las acciones realizadas u omitidas e identificar cómo mejorar.

La plataforma:

- No está afiliada a INEP.
- No emite calificaciones ni certificaciones oficiales.
- No garantiza la aprobación.

## 2. Problema

Los candidatos necesitan práctica repetida y realista para estaciones clínicas cronometradas, acompañada de retroalimentación accionable sobre su desempeño por criterio.

La preparación existente no siempre ofrece simulaciones accesibles y repetibles con evidencia objetiva de lo que el estudiante realizó, omitió o necesita mejorar.

El producto debe proporcionar esta práctica sin presentar sus resultados como una evaluación oficial, supervisión médica o guía para decisiones clínicas reales.

## 3. Usuarios objetivo

### 3.1 Estudiantes

Médicos formados en el extranjero que se preparan para la etapa práctica de Revalida, con distintos niveles de preparación.

### 3.2 Médicos autorizados

Profesionales responsables de crear, validar, publicar, revisar y mejorar los casos clínicos y sus rúbricas.

### 3.3 Administradores

Usuarios responsables de cuentas, acceso de médicos, suscripciones, soporte y operación de la plataforma. No pueden modificar contenido clínico ni puntuaciones.

## 4. Principios del producto

- **Independencia educativa:** nunca insinuar afiliación con INEP ni carácter oficial.
- **Evidencia antes que puntuación opaca:** toda puntuación debe vincularse con evidencia por criterio.
- **Seguridad clínica:** los personajes no pueden inventar información clínica.
- **Responsabilidad médica:** los médicos gobiernan casos y rúbricas.
- **Incertidumbre transparente:** la evidencia incierta debe permanecer visiblemente incierta.
- **Práctica accesible:** interacción principalmente por voz, con alternativas accesibles.
- **Tratamiento justo de fallas:** los problemas de infraestructura no pueden perjudicar al estudiante.
- **Integridad histórica:** los casos, rúbricas, evaluaciones y correcciones deben ser versionados y auditables.
- **Minimización de datos:** recopilar y conservar solamente la información necesaria.

## 5. Mecánicas de Revalida usadas para validación

Los materiales oficiales de 2025/1 pueden utilizarse internamente para comprender y validar mecánicas como:

- Diez estaciones de diez minutos.
- Roles de paciente, madre y enfermero.
- Una estación de examen físico con maniquí.
- Verbalización de acciones de examen físico.
- Restricciones para tocar a personas simuladas.
- Materiales condicionales desbloqueados mediante solicitudes válidas.
- Criterios afectados por el tiempo o el orden de las acciones.

Estos materiales son referencias internas. No deben convertirse en contenido público sin autorización confirmada.

## 6. Alcance

### 6.1 Piloto técnico privado (destino activo)

El piloto activo será:

- Móvil y privado por invitación.
- Gratuito y restringido a validación interna.
- Acotado a **una estación original aprobada por clínico**.
- Ejecutado con **5 a 8** participantes invitados.

Reglas operativas del piloto:

- Se permite ayuda humana antes del intento (instalación, acceso, micrófono y orientación inicial).
- Debe existir al menos un intento **válido y sin guía en estación** por participante inscrito.
- La guía humana durante la estación invalida el intento para cobertura del piloto.
- La modalidad oral y escrita se identifica antes de iniciar y no se mezcla dentro del mismo intento.
- Una interrupción técnica en modo estricto invalida y reemplaza el intento: no se puntúa ni consume.

La decisión de avance del piloto se emite en un **reporte congelado y versionado** (estación, rúbrica, política, rutas proveedor/modelo, build y esquema de telemetría) con tres puertas obligatorias e independientes, sin promedio ni compensación:

1. **Operabilidad e integridad técnica:** cada participante tiene al menos un intento válido sin guía; p95 de turno actor `<= 4s` con denominador completo; p95 de feedback final `<= 60s` con denominador completo; y cero defectos críticos sin resolver (técnicos, privacidad, scoring, integridad clínica, pérdida de evidencia, desbloqueo incorrecto o fabricación del actor).
2. **Validez clínica:** revisión ciega criterio por criterio en todo intento válido; acuerdo exacto 100% en criterios críticos y al menos 90% en no críticos; bloqueo por patrones de error sistemático; incertidumbre residual 0% en críticos y máximo 10% en no críticos; `not_evidenced` validado por clínico permanece en denominador.
3. **Utilidad educativa:** todos los participantes aprueban teach-back; y al menos 80% de los inscritos entregan las tres calificaciones (claridad, utilidad y accionabilidad) con mínimo 4/5 en cada una; faltantes permanecen en denominador.

El reporte también incluye diagnósticos (interrupciones, rechazos de validación, fallas de procesamiento, desacuerdos de revisión ciega, disputas/correcciones por criterio, escapes de hechos del actor, desbloqueos, integridad de transcripción/turnos, eliminación/control de acceso y costo p50/p95 por rol/proveedor). Estos diagnósticos y señales longitudinales son no bloqueantes.

### 6.2 MVP público

El MVP incluirá:

- Diez estaciones originales, creadas y validadas clínicamente por médicos.
- Plantillas reutilizables para crear contenido.
- Simulación estricta individual.
- Entrenamiento guiado.
- Cuentas e historial persistente.
- Resultados estimados basados en evidencia.
- Espacio de trabajo para médicos.
- Prueba gratuita limitada seguida de una suscripción.
- Paridad funcional en iOS, Android y web responsiva.

Las estaciones oficiales de Revalida no formarán parte del contenido público.

### 6.3 Post-MVP

- Simulación encadenada de diez estaciones.
- Pacientes 3D complejos.

## 7. Recorridos del estudiante

### 7.1 Incorporación

1. El estudiante se registra o inicia sesión.
2. La plataforma explica su naturaleza educativa e independiente.
3. Una introducción breve presenta el uso del micrófono, las reglas y un ejemplo.
4. La plataforma comprueba el micrófono y la conectividad.
5. El estudiante puede realizar una estación diagnóstica opcional.
6. El estudiante elige entrenamiento guiado o simulación estricta.

La estación diagnóstica será recomendada, pero no obligatoria.

### 7.2 Simulación estricta

1. La plataforma selecciona una estación aleatoria no revelada.
2. El estudiante ve únicamente las instrucciones dirigidas al participante.
3. Interactúa principalmente por voz o mediante texto por accesibilidad.
4. La transcripción permanece visible.
5. No hay pistas.
6. La plataforma registra declaraciones, solicitudes, acciones, tiempos, secuencias, materiales desbloqueados y evidencia.
7. La evaluación ocurre después de finalizar.

Los resultados estrictos se mantienen separados del entrenamiento guiado y la práctica escrita.

### 7.3 Entrenamiento guiado

1. El estudiante selecciona una especialidad, caso o habilidad.
2. Realiza la estación mediante voz o texto.
3. Puede solicitar ayuda progresiva:
   - Orientación general.
   - Área clínica relevante.
   - Acción concreta.
4. Cada pista queda registrada.
5. Los resultados distinguen qué criterios se alcanzaron independientemente y cuáles después de recibir ayuda.
6. La plataforma puede recomendar otra estación o habilidad según las omisiones.

El estudiante conserva la libertad de elegir otra práctica.

### 7.4 Resultados y mejora

Los resultados muestran:

- Puntuación estimada de entrenamiento.
- Puntos obtenidos y máximos.
- Evidencia por criterio.
- Omisiones.
- Confianza del reconocimiento.
- Criterios inciertos.
- Rango mínimo y máximo cuando exista incertidumbre.
- Orientación accionable.
- Modalidad estricta, asistida, oral o escrita.

El estudiante puede consultar su historial, seguir su progreso y cuestionar criterios específicos.

### 7.5 Interrupciones técnicas

#### 7.5.1 Entrenamiento guiado

- Se conserva el progreso.
- El estudiante puede reanudar.

#### 7.5.2 Simulación estricta

- La estación se marca como interrumpida por el sistema.
- Se registran diagnósticos técnicos.
- No se puntúa evidencia incompleta.
- No se consume el intento.
- Se concede un nuevo intento.
- La estación interrumpida no puede reanudarse.

## 8. Requisitos funcionales

### 8.1 Idioma y accesibilidad

El MVP debe:

- Operar íntegramente en portugués brasileño.
- Utilizar voz como modalidad principal.
- Ofrecer entrada opcional por texto.
- Mostrar transcripción en vivo.
- Identificar la práctica escrita como no equivalente al desempeño oral.
- Admitir lectores de pantalla.
- Permitir navegación por teclado en web.
- Proporcionar contraste suficiente.
- Respetar el tamaño de texto configurado en el sistema.

### 8.2 Simulación de pacientes y actores

El MVP utilizará personajes 2D animados y expresivos para representar roles, estados y respuestas.

Los personajes deberán:

- Utilizar únicamente hechos aprobados del caso.
- No inventar síntomas, antecedentes, hallazgos ni resultados.
- Responder de forma neutral cuando la información solicitada no exista.
- Registrar esa ausencia como una brecha para revisión médica.
- Revelar materiales condicionales solamente tras solicitudes válidas.
- Respetar las reglas de tiempo y orden definidas en el caso.

Los pacientes 3D complejos quedan para después del MVP.

### 8.3 Evaluación

El sistema de evaluación debe:

- Utilizar IA para interpretar el lenguaje y extraer evidencia por criterio.
- Utilizar un proceso determinista y versionado para aplicar los puntos y ponderaciones.
- Impedir que la IA invente una calificación global.
- Conservar la evidencia que respalda cada resultado.
- Evitar marcar automáticamente como omitida evidencia con baja confianza.
- Enviar solamente los criterios inciertos a una segunda IA independiente.
- Impedir que la segunda IA conozca la conclusión de la primera.
- Aplicar la puntuación determinista cuando ambas coincidan con suficiente confianza.
- Mantener el criterio como incierto cuando no coincidan.
- Mostrar un rango de puntuación cuando la incertidumbre afecte el total.
- Impedir debates ilimitados entre agentes de IA.

El objetivo será entregar la retroalimentación completa en menos de un minuto.

Si el procesamiento demora más:

- Se conserva la sesión.
- El estudiante puede salir.
- El análisis continúa en segundo plano.
- El estudiante recibe una notificación cuando finaliza.

El minuto es un objetivo de producto, no una garantía del proveedor.

### 8.4 Cuestionamientos y correcciones

El estudiante puede cuestionar un criterio de puntuación utilizando su transcripción y evidencia.

El cuestionamiento:

- No modifica automáticamente la puntuación.
- Es revisado por un revisor clínico autorizado.
- Puede generar una corrección documentada.
- Puede identificar un defecto en el caso, la rúbrica o el sistema de evaluación.

Cuando se confirme un defecto sistemático:

- Se reevaluarán los intentos afectados cuando la evidencia conservada lo permita.
- Se conservará el resultado original.
- Se mostrará el resultado corregido.
- Se explicará el motivo.
- Nunca se reescribirá el historial silenciosamente.

### 8.5 Cuentas e historial

El prototipo puede funcionar sin cuentas.

El MVP requiere autenticación ligera y almacena solamente:

- Correo electrónico.
- Nombre opcional.
- Preferencia de idioma.
- Historial de intentos.
- Resultados de entrenamiento.

La plataforma no recopilará información clínica de pacientes reales.

Los estudiantes podrán:

- Consultar sus intentos y resultados.
- Eliminar su cuenta.
- Eliminar transcripciones, intentos y resultados identificables.

Después de la eliminación solo podrán conservarse métricas agregadas irreversiblemente anonimizadas.

### 8.6 Audio y transcripciones

El audio original no se conservará de forma predeterminada.

La plataforma podrá conservar:

- Transcripciones.
- Eventos relevantes.
- Resultados de entrenamiento.

Conservar audio requerirá:

- Consentimiento explícito.
- Propósito declarado.
- Período de retención definido.
- Opción accesible de eliminación.

### 8.7 Espacio de trabajo para médicos

Los médicos autorizados podrán:

- Crear casos originales.
- Crear plantillas reutilizables.
- Editar borradores.
- Probar un caso ejecutando la simulación como candidatos.
- Revisar el comportamiento del actor y los materiales condicionales.
- Inspeccionar el reconocimiento de evidencia y la puntuación.
- Confirmar y publicar clínicamente los casos.
- Revisar cuestionamientos y problemas clínicos.
- Consultar analítica anonimizada sobre la calidad de los casos.

El flujo de contenido admitirá:

1. Borrador.
2. Revisión médica o confirmación clínica.
3. Publicado.

Cada caso y rúbrica será versionado. Los intentos históricos conservarán las versiones exactas usadas en su evaluación.

Inicialmente, un médico podrá crear, confirmar y publicar sus propios casos mediante confirmación explícita e historial auditable.

La revisión por un segundo médico podrá incorporarse posteriormente, pero no será obligatoria en el MVP.

La IA podrá asistir al médico durante la redacción, pero nunca generar ni publicar casos de manera autónoma.

### 8.8 Acceso médico a datos del estudiante

Los médicos no podrán navegar libremente todas las transcripciones.

Solo podrán acceder a intentos relacionados con:

- Un cuestionamiento.
- Una falla clínica señalada.
- Una muestra autorizada explícitamente.

La información deberá anonimizarse cuando sea posible.

Los médicos podrán consultar analítica agregada por versión de caso:

- Criterios omitidos frecuentemente.
- Preguntas no contempladas.
- Abandono de estaciones.
- Cuestionamientos relacionados.

### 8.9 Roles y permisos

Los permisos permanecerán separados, incluso cuando inicialmente una persona posea varios roles.

#### 8.9.1 Administradores

Pueden:

- Gestionar cuentas.
- Gestionar el acceso de médicos.
- Gestionar suscripciones.
- Prestar soporte operativo.

No pueden:

- Modificar contenido clínico.
- Modificar rúbricas.
- Cambiar puntuaciones.

#### 8.9.2 Médicos

Pueden:

- Gestionar casos.
- Gestionar plantillas y rúbricas.
- Realizar revisiones clínicas.
- Revisar cuestionamientos autorizados.

No pueden acceder a facturación.

### 8.10 Acceso comercial

El prototipo será gratuito y por invitación.

El MVP ofrecerá:

- Prueba gratuita limitada.
- Suscripción para acceder a la biblioteca completa.
- Historial.
- Seguimiento del progreso.

No se cobrará por intento.

Los futuros límites de uso deberán:

- Basarse en costos y evidencia de uso.
- Comunicarse antes de utilizar el servicio.
- Evitar cargos inesperados.

## 9. Reglas de negocio

- Todo el contenido orientado al estudiante estará en portugués brasileño.
- Todos los resultados serán estimaciones educativas.
- El desempeño asistido, estricto, oral y escrito debe permanecer diferenciado.
- Las fallas técnicas no pueden consumir intentos ni producir puntuaciones.
- Los materiales oficiales permanecerán restringidos al prototipo interno.
- El contenido público debe ser original y gobernado por médicos.
- Los cambios clínicos requieren confirmación médica e historial de versiones.
- Las puntuaciones requieren evidencia por criterio y rúbricas versionadas.
- La incertidumbre no puede convertirse silenciosamente en una omisión.
- Los cuestionamientos requieren revisión clínica autorizada.
- Las correcciones sistemáticas deben ser transparentes y auditables.
- El producto no puede afirmar carácter oficial, certificación, calificación oficial ni aprobación garantizada.

## 10. Límites de seguridad, privacidad y legales

Durante el registro y desde cada resultado debe indicarse que:

- La plataforma es independiente de INEP.
- Es una herramienta educativa.
- Las puntuaciones son estimaciones de entrenamiento.
- No reemplaza educación, supervisión ni criterio médico.
- No sirve para diagnóstico ni consulta de pacientes reales.

También se requiere:

- No recopilar datos clínicos de pacientes reales.
- No conservar audio original por defecto.
- Solicitar consentimiento para retención opcional.
- Permitir eliminar cuenta e historial identificable.
- Restringir el acceso médico a transcripciones.
- Anonimizar cuando sea posible.
- Limitar los personajes a hechos clínicos aprobados.
- No reutilizar públicamente estaciones oficiales sin autorización.

## 11. Métricas de éxito

Métricas principales:

- Simulaciones completadas por estudiante activo.
- Repetición de estaciones.
- Mejora en criterios previamente omitidos.
- Retención durante la preparación.
- Utilidad y capacidad de acción percibidas de la retroalimentación.

La tasa oficial de aprobación de Revalida no se utilizará como indicador principal de éxito.

## 12. Criterios de aceptación del MVP

El MVP debe demostrar que:

- Los estudiantes completan estaciones estrictas y guiadas en portugués brasileño.
- La voz, el texto y la transcripción funcionan en las plataformas admitidas.
- El desempeño asistido y estricto permanece separado.
- Los personajes respetan los hechos aprobados.
- Las acciones válidas desbloquean los materiales correctos.
- El tiempo y el orden son auditables.
- La IA extrae evidencia y las reglas deterministas asignan puntos.
- La incertidumbre permanece visible.
- Las fallas técnicas no fabrican ni puntúan interacciones incompletas.
- La eliminación de cuenta y los controles de privacidad funcionan.
- La autoría, publicación y versionado médico funcionan.
- iOS, Android y web responsiva tienen paridad funcional dentro de una misma ventana de lanzamiento.

## 13. Riesgos y mitigaciones

| Riesgo | Mitigación |
| --- | --- |
| Los estudiantes interpretan los resultados como oficiales | Advertencias persistentes sobre independencia, uso educativo y puntuaciones estimadas. |
| La IA interpreta incorrectamente la evidencia | Extracción por criterio, puntuación determinista, segunda revisión, cuestionamientos y correcciones transparentes. |
| Los actores inventan información clínica | Limitar respuestas al caso aprobado y registrar brechas para revisión médica. |
| Una falla del proveedor perjudica al estudiante | Comprobaciones previas, reanudación guiada, nuevos intentos estrictos y ausencia de puntuación incompleta. |
| El contenido oficial queda expuesto | Restringirlo al prototipo interno. |
| Los médicos acceden a demasiada información | Acceso limitado por finalidad, anonimización y auditoría. |
| La práctica asistida parece equivalente al examen | Etiquetado e historial separados. |
| Un caso defectuoso afecta a muchos estudiantes | Versionado, cuestionamientos, analítica y reevaluación transparente. |
| Los costos producen restricciones inesperadas | Definir límites después del piloto y comunicarlos antes del uso. |
| Las barreras de accesibilidad excluyen estudiantes | Requisitos explícitos de accesibilidad en todas las plataformas. |

## 14. Dependencias y supuestos

### 14.1 Dependencias

- Disponibilidad del médico contratado.
- Contenido original clínicamente validado antes del lanzamiento.
- Proveedores externos de IA y conexión a internet.
- Participantes piloto con distintos niveles de preparación.
- Autorización confirmada antes de cualquier uso público de material oficial.

### 14.2 Supuestos

- Los estudiantes tienen dispositivos iOS, Android o acceso web compatible.
- Los estudiantes cuentan con conectividad suficiente.
- Comprenden que los resultados son estimaciones educativas.
- El piloto proporcionará evidencia diagnóstica y de decisión bajo umbrales ya definidos para avance al MVP.
- El médico contratado definirá el contrato clínico de plantillas y rúbricas.

## 15. No objetivos permanentes

- Preparación para el examen teórico.
- Consulta, diagnóstico o tratamiento de pacientes reales.
- Tutorías humanas en vivo.
- Comunidad o red social.
- Certificación oficial.
- Emisión de calificaciones oficiales.
- Garantías de aprobación.

## 16. Decisiones abiertas

### 16.1 Contrato clínico de plantillas y rúbricas

**Responsable:** médico contratado.

Definir los campos clínicos, campos de rúbrica y requisitos de validación obligatorios.

### 16.2 Obligatoriedad de la prueba médica

Determinar si el médico debe ejecutar la simulación antes de publicar cada caso o nueva versión.

La capacidad de probarla sí forma parte del MVP.

### 16.3 Contrato de avance del piloto

Resuelto: el piloto usa contrato fijo de tres puertas independientes, denominadores completos y reporte versionado congelado para decidir avance/no avance, sin puntuación compuesta.

### 16.4 Precio y límites de uso

Definir después del piloto:

- Precio de suscripción.
- Alcance de la prueba gratuita.
- Límite mensual de simulaciones.
- Límite mensual de voz.
