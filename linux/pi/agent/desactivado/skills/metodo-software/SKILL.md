---
name: metodo-software
description: "Método de trabajo para construir y cambiar software pensando en agentes. Usala en cualquier tarea de software (features, bugs, refactors, apps) y cuando haya que optimizar o bajar el consumo. Triggers: implementar, feature, bug, refactor, app, verificar, test, arquitectura, escalar, agentes, rendimiento, optimizar, lento, presupuesto colibrí."
---

# Método de software (pensado para agentes)

El objetivo no es escribir más código, es que **otro agente entienda y extienda
esto sin contexto previo**, que **pueda verificar que funciona** antes de
publicar y que **aproveche el hardware que hay sin trabarlo**. Menos código, más
claro, más barato.

## Los seis pasos

1. **Leé el árbol de features.**
   Antes de tocar nada, buscá el árbol de features del repo (`features/`,
   `docs/features/`, o como se llame). Ahí está qué necesita la app, una feature
   por archivo, con su criterio de aceptación.

2. **Un verificador determinista por feature.**
   Cada feature tiene un script que la chequea sola (`scripts/verify/<feature>.sh`).
   Determinista = mismo resultado siempre, sin modelo, sin red, sin criterio humano.
   Si agregás una feature, agregás su verificador. Sin verificador no está terminada.

3. **Verificá antes de publicar.**
   Corré el verificador de las features que tocaste y el global
   (`make check` o `scripts/verify/run-all.sh`). Si falla, el cambio no está listo.
   Si no podés correrlo, decilo con claridad.

4. **Dejá rastro de decisiones.**
   Las decisiones de arquitectura van a `DECISIONS.md`: qué se eligió, por qué y
   qué se descartó. Agregá entradas, no reescribas la historia.

5. **Hacelo fácil para el próximo agente.**
   Nombres claros, un solo lenguaje de backend si se puede, sin pasos de build
   ocultos, docs en `AGENTS.md`. Si un agente nuevo no entiende el repo en cinco
   minutos, el repo está mal.

6. **Eficiencia primero: presupuesto adaptativo (colibrí).**
   Antes de escribir, estimá el costo en CPU, memoria, red y batería, y elegí la
   opción más barata que cumpla. Lo que consuma recursos (video, imágenes,
   animación, polling, IA local, build) detecta el hardware y el contexto,
   arranca con un techo conservador, se degrada sola cuando el equipo no da y
   deja un override explícito al usuario.
   **Terminado** = el techo es explícito, la señal de degradación se mide y la
   matemática del presupuesto tiene su test determinista.

## Cómo se ve una feature

```markdown
# Feature: <nombre>

## Qué hace
<una o dos frases>

## Criterio de aceptación
- [ ] <algo verificable>

## Verificador
scripts/verify/<nombre>.sh

## Estado
verificado | pendiente
```

## Presupuesto adaptativo (colibrí)

Un **presupuesto colibrí** es un techo de trabajo simultáneo que el sistema se
impone solo: chico, rápido y sin gastar de más. Elegís el techo **antes** de
escribir y lo hacés cumplir en el código: no es una optimización que queda para
el final.

### El modelo

1. **Costo por unidad.** Escribí qué cuesta una unidad de trabajo: un video
   decodificando, una request de IA, un proceso, un frame. Si no sabés el costo,
   medilo primero.
2. **Techo conservador.** Arrancá por debajo de lo que aguanta el equipo más
   flojo que te importa. Un techo que solo se cumple en tu máquina no es un techo.
3. **Niveles, no un booleano.** Tres estados (`full` / `lite` / `off`) con un
   techo numérico por tipo de consumidor. El nivel se elige, no se improvisa.
4. **Señales de entrada.** Hardware y contexto: `hardwareConcurrency`,
   `deviceMemory`, ahorro de datos, `prefers-reduced-motion`, batería,
   temperatura, concurrencia del server. Con eso elegís el nivel inicial.
5. **Medición en vivo con histéresis.** El nivel baja solo con evidencia
   sostenida: FPS bajo, frames de video descartados, memoria, latencia o CPU
   alta durante varias ventanas. Volver a subir es decisión del usuario o de una
   ventana estable larga; un pico aislado no cambia el nivel.
6. **Persistencia y override.** Guardá el nivel degradado para ese equipo y
   mostralo en la UI en lenguaje humano. El usuario puede pedir el máximo y
   reintentar la medición. El default sigue siendo automático.

### Alrededor del presupuesto, siempre

- Cargá al acercarse (lazy), no en el montaje.
- Reusá nodos, conexiones, buffers y resultados antes que recrearlos.
- Procesá en lotes por frame o por chunk; nada de N ítems en un tick.
- Soltá lo que no está a la vista: pausá, descargá, cerrá handles y liberá
  decodificadores.
- Preferí compositor/CSS para animar y dejá el main thread para la lógica.
- Medí antes de afirmar que algo es eficiente; después de tocar, medí de nuevo.
- Presupuestá también en backend y agentes: colas, concurrencia, tamaño de
  contexto y cantidad de llamadas al modelo.

### Dónde suele esconderse el costo

| Consumidor | Qué medir | Techo típico |
| --- | --- | --- |
| Video | decodificadores activos, frames descartados | 1-3 según nivel |
| Imágenes | requests simultáneas, bytes | por viewport + margen |
| IA local | RAM/VRAM, tokens/s, cola | concurrencia 1 |
| Agentes | contexto, llamadas, subagentes | presupuesto por tarea |
| Build/indexado | CPU, I/O, memoria | paralelismo = núcleos |

### Verificación

- La matemática del presupuesto vive en un módulo puro (`capFor`, `degrade`,
  `shouldDegrade`, `averageFps`) y tiene tests deterministas.
- La degradación se prueba forzando el escenario (CPU ocupada,
  `reduced-motion`, hardware simulado), no mirando si "parece andar".
- El override y la persistencia se prueban leyendo el estado guardado.

### Caso de referencia: Foldertinder

`static/js/lib/video-budget.js` + `static/js/lib/video.js`. Tres niveles
(`full` 3/4 videos, `lite` 1/2, `off` 0), señales de hardware, medición de FPS y
frames descartados en ventanas de 30 frames, degradación tras 3 ventanas lentas,
nivel persistido, override en Ajustes, suspensión al abrir detalle/lightbox o
esconder la pestaña, y test determinista de la matemática. La regla vive en
`AGENTS.md` del repo como invariante.

## Regla de oro

Si no podés mostrar cómo se verifica, no terminaste.
