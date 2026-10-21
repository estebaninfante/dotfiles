# Instrucciones globales

- Antes de comprometerte con un plan grande, una arquitectura nueva, una migración o un cambio caro de revertir, pedí segunda opinión: escribí un brief de ≤300 palabras y corré `segunda /tmp/brief.md` (skill `segunda-opinion`). No lo uses para cambios chicos.
- Cada ~5 decisiones de diseño, o antes de un merge grande, corré `segunda` sobre las decisiones acumuladas.
- Si el veredicto es `DESCARTAR`, no avances sin confirmarlo con el usuario. Si es `AJUSTAR`, aplicá los ajustes antes de escribir código. Si ignorás el veredicto, decí por qué y dejá nota con `tarea`.

## Respuesta escrita y por voz

- Toda respuesta final va **escrita** en el mensaje, completa y legible, y además se dice por voz: `hablar` para un avance, contexto o pregunta; `avisar` al cerrar la corrida. La voz acompaña, nunca reemplaza al texto.
- Lo que digas por voz tiene que estar también en la respuesta escrita. Si el usuario solo leyera el texto, tiene que entender lo mismo; nada de dejar el contenido principal únicamente en la voz.
- La versión hablada es un resumen fiel en una o dos frases llanas: sin tecnicismos, rutas ni nombres de herramientas, y sin datos que no estén en el texto.
- Si la voz está apagada o falla, no la inventes: seguí por texto y avisá que no se pudo hablar.

## Ritmo de los agentes (modo de voz)

- El usuario cambia el ritmo por voz: **"modo fluido"**, **"modo concentración"** o **"modo campana"** (también `voice modo fluido|concentracion|campana`).
- **Modo fluido**: podés narrar avances con `hablar` mientras trabajás; el cierre sigue con `avisar`.
- **Modo concentración**: no narres y no suene. Guardá lo importante para el cierre con `avisar`, en puntos clave (una o dos frases); el mensaje queda en el buzón y el usuario lo escucha con "dime". `hablar` no está disponible. El indicador de la barra muestra el modo y los pendientes.
- **Modo campana**: no se habla; el mensaje queda en el buzón y el usuario lo escucha con "dime". Igual escribí todo en la respuesta.
- Los **subagentes no hablan al usuario**: reportan sólo al agente que los lanzó, y ése decide qué contarle. No los presentes como voces propias.

## Modo velocidad

- El usuario elige un nivel de **Velocidad**: Turbo, Rápido, Normal o Cuidadoso.
  Si no lo dice, Normal.
- Turbo: razonamiento mínimo, **sin verificadores ni revisión automática**;
  la revisión es del usuario. Se prioriza desplegar.
- Rápido: compilar y verificar solo la feature tocada.
- Normal: verificadores de lo que cambió.
- Cuidadoso: suite completa y revisión.
- Anotalo en el encargo de cada agente: `MODO VELOCIDAD: <nivel>`.

## Investigaciones

- Si el usuario pide una investigación, **no empieces a buscar ni a escribir**.
  Primero hacé preguntas: objetivo, pregunta a resolver, problema, alcance,
  decisión que depende del resultado, restricciones y qué evidencia le sirve.
- No arranques hasta tener: **problema, pregunta, objetivo, hipótesis, método y
  qué prueba manual se va a hacer**.
- Las investigaciones actuales son sobre **harness, LLMs y sistemas agénticos**.
  El foco es cómo lograr que los agentes construyan mejor, no el dominio de
  ejemplo.
- Documentá en `~/alicia/investigaciones/<slug>/`: paper, `fuentes.md` y
  experimento. El título debe afirmar el objetivo o la pregunta, no un tema.
- El paper es para aprender, no para publicar: sin abstract, sin palabras clave,
  sin introducción. Cada frase debe aportar un dato, una relación o una
  consecuencia. Incluir contradicciones, dudas y fuentes.
- **Las pruebas de aprendizaje son manuales y bajo observación.** Las construyen
  el usuario y el agente juntos, y se corren cuando el usuario lo pide. El
  agente **no** corre tests automáticos para declarar que el agente “aprendió”
  o “no memorizó”.
- El agente sí puede correr checks mecánicos (build, lint, a11y) para verificar
  el software; no los use como prueba de aprendizaje del harness.
