---
name: entender-intencion
description: "Aterrizar la intención real antes de construir: cuando dice 'entiende mi intención', 'aterrizá mi idea' o 'no me entendiste'."
---
# Entender la intención

El pedido suele ser un medio. Leer, nombrar el problema, preguntar poco, devolver la lectura. Recién después construir.

## 1. Leer antes de preguntar

Código, datos, capturas, `machine ls --all --json`, git. Si la respuesta está en la base, preguntarla quema confianza.

## 2. Separar tres cosas

- **Lo que dijo**: una frase, con sus palabras.
- **El problema**: qué quiere dejar de sufrir. Si no lo podés decir sin su solución, no lo entendiste.
- **Lo que asumo**: cada hueco, marcado "asumo", nunca como hecho.

Ejemplo real: pidió "un lienzo infinito para mis proyectos". El problema era "no entiendo cómo se relacionan mis proyectos y no tengo un lugar donde empezar a trabajar cada día". El lienzo era el medio.

## 3. Preguntar poco, en el modal

2 o 3 decisiones que cambien el diseño, con opciones y una recomendada, en `ask_user_question`. Nunca un cuestionario.

- Si contesta "no te entiendo", la pregunta está mal: cambiála a sus palabras, no la repitas.
- Prohibido inventar jerga propia ("familias", "nodos", "entidades"). Decí problemas, proyectos, tareas.

## 4. Devolver la lectura y frenar

"**Así lo entendí:** … / **Asumo:** … / **Decidís vos:** …". Una corrección y arrancás. No vuelvas a preguntar lo mismo.

## 5. Guardar la intención en `machine`

Lo entendido tiene que quedar donde el copiloto lo lee, no en el chat:

```bash
machine set <slug> --goal "para qué existe" --check "cómo se comprueba"
machine idea "<problema>" --title "<2-4 palabras>"
machine promote <slug> --goal "…" --check "…"
```

No: repetir sus palabras de loro, meter la solución en el resumen, pedir permiso para lo que ya pidió, preguntar estética antes del problema.
