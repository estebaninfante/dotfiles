---
name: fabrica-de-ideas
description: "Capturar ideas sueltas del usuario mientras piensa en voz alta y mantenerlas vivas: crear, listar, ver, anotar conversación, descartar con motivo. Usala cuando el pedido sea una idea o pregunta especulativa ('¿se podría…?', '¿y si…?', 'estoy pensando en…') en vez de una tarea concreta, y cuando haya que repasar, retomar o descartar ideas guardadas. Triggers: idea, ideas, se podría, y si, viable, proyecto futuro, fábrica de ideas, descartar idea, retomar idea."
---

# Fábrica de ideas

El usuario piensa en voz alta todo el tiempo: "¿se podría usar un teléfono viejo
como cerebro y dejar el portátil de pantalla?". Eso **no** es una tarea: es una
idea. Antes se perdía en el chat. Acá se guarda sola, crece con la conversación,
y se puede revisar, retomar o descartar meses después.

## Dónde vive

- `~/.local/share/pi/ideas/index.md` — la tabla legible de todas las ideas.
- `~/.local/share/pi/ideas/IDEA-XXXX.md` — una idea por archivo: la idea, qué la
  haría funcionar, dudas y riesgos, y la conversación append-only con fecha.
- CLI `ideas` (en el `PATH`) para la terminal; tool `idea` para el agente.
  Misma implementación (`~/dotfiles/linux/bin/ideas`), sin duplicar lógica.

## La regla

1. **Capturar antes de responder.** Si el mensaje es una idea o pregunta
   especulativa, primero `idea` con `accion: "nueva"`: `titulo` corto y concreto,
   `texto` con la idea en tus palabras, `etiquetas` de dos o tres temas.
2. **No duplicar.** Antes de crear, si el tema ya existe (`accion: "listar"`),
   usá `accion: "anotar"` en esa idea.
3. **Responder completo.** La captura no reemplaza el análisis: el usuario quiere
   la respuesta, no solo el archivo.
4. **Anotar lo que se concluye.** Cuando la charla llega a una medición, una
   decisión o un riesgo, `accion: "anotar"` en la misma idea. Ese es el valor:
   la idea queda con su historia, no congelada.
5. **Descartar, no borrar.** Si el usuario la baja a tierra, `accion: "descartar"`
   con el `motivo`. Queda archivada y visible con `listar --todas`; se puede
   reabrir sin perder la conversación.
6. **No capturar tareas.** "Arreglá el bug del panel" es un ticket
   (`tarea`), no una idea.

## Cuando el usuario quiere conversar sobre una idea

`ideas charlar IDEA-XXXX` abre una sesión de pi con el archivo de la idea como
contexto, y esa sesión sigue la charla desde donde quedó. Al cerrar, se anota la
conclusión. Es el puente entre "idea guardada" y "conversación en torno a ella".

## Terminal

```sh
ideas                     # lista las abiertas
ideas listar --todas      # incluye descartadas
ideas ver IDEA-7K2P
ideas anotar IDEA-7K2P "medido: 3 W en reposo headless"
ideas descartar IDEA-7K2P "el streaming cuesta más de lo que ahorra"
ideas reabrir IDEA-7K2P
ideas buscar batería
```

En pi: `/ideas` lista, `/idea IDEA-7K2P` la muestra en el panel y `/idea` sin id
lo cierra.

## Por qué importa

El usuario tiene más ideas que tiempo de ejecutarlas. La fábrica de ideas es la
memoria externa: no decide por él, pero no pierde nada, y le deja ver el conjunto
para elegir cuál vale la pena. También sirve para lo contrario: descartar con
motivo escrito evita volver a dar vueltas sobre lo mismo.
