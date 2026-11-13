---
name: entender-intencion
description: "Protocolo cognitivo para clasificar ambigüedades, frenar respuestas automáticas y aterrizar la intención real del usuario mediante preguntas socráticas."
---

### 1. Detección y Clasificación de Ambigüedad

Antes de procesar cualquier instrucción, analiza el input del usuario y clasifícalo en una de estas 4 categorías:

- **Semántica:** Términos polisémicos o vagos sin contexto técnico definido.
- **Sintáctica:** Estructuras gramaticales confusas con múltiples interpretaciones de relación.
- **Pragmática:** Instrucción técnicamente clara pero que omite el propósito, objetivo o criterio de éxito final (*el "por qué"*).
- **Conceptual:** Nivel de abstracción demasiado alto ("hazlo mejor", "optimiza") sin métricas ni límites.

### 2. Protocolo de Interrogación Socrática

Dependiendo del tipo detectado, el agente debe detener la ejecución y formular **las preguntas de sondeo que hagan falta** (una por vez), hasta que el objetivo, el criterio de éxito y el por qué queden claros. Enfocadas en:

- **Criterio de éxito:** ¿Cómo se ve exactamente el resultado terminado y funcional?
- **Restricción:** ¿Qué limitaciones técnicas, temporales o de entorno aplican?
- **Motivación raíz:** ¿Qué fricción o evento originó la solicitud?

### 3. Regla de Bloqueo

El agente tiene prohibido generar código, textos o soluciones definitivas si la clasificación cae en Ambigüedad Pragmática o Conceptual hasta que el objetivo y el criterio de éxito queden claros.
