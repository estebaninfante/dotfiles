---
name: segunda-opinion
description: >
  Pedir una segunda opinión a otro modelo de mayor tier antes de comprometerse
  con un plan grande, una arquitectura nueva, una migración o cualquier cambio
  caro de revertir. Usala cuando el usuario diga "consultalo con otro agente",
  "pedí opinión", "revisá el plan", o cuando estés por arrancar algo de varias
  sesiones. También cada ~5 decisiones de diseño o antes de un merge grande.
  Triggers: segunda opinión, otro agente, consultá a k3, revisá el plan,
  validar arquitectura, sanity check.
---

# Segunda opinión

Un modelo de mayor tier revisa el plan **sin ejecutar nada**. El valor no es que
tenga razón: es que un par de ojos distintos encuentran el supuesto que te falta
antes de que cueste caro.

## Cuándo

- Antes de comprometerte con una arquitectura, migración o refactor de varias sesiones.
- Antes de construir algo nuevo desde cero (¿existe algo que ya lo hace?).
- Cada ~5 decisiones de diseño acumuladas, o antes de un merge grande.
- Cuando el usuario lo pida explícitamente.

**No** para cambios chicos, bugs acotados, ni para que haga el trabajo. Es una
consulta de opinión, no una delegación.

## Cómo (barato y determinista)

1. Escribí un **brief compacto** (≤300 palabras) en `/tmp/brief.md`. Qué se quiere
   lograr, la propuesta, las restricciones reales y qué decisión está en juego.
   **No pegues el repo ni archivos enteros**: el brief es el contexto completo.
2. Corré:

   ```bash
   segunda /tmp/brief.md              # modelo por defecto: kimi-k3
   segunda -m opus /tmp/brief.md      # si querés el tier más alto
   segunda --json /tmp/brief.md       # veredicto + traza en JSON
   ```

   `segunda` cachea por hash: repetir el mismo brief no gasta tokens. El cache
   evita repetir, **no** garantiza que el modelo responda igual siempre.
   Cada consulta queda en `~/.local/share/segunda-opinion/log/`.
3. Leé el `VEREDICTO`:
   - `SEGUIR` → avanzá, citando los riesgos que aceptás.
   - `AJUSTAR` → aplicá los puntos de `SIMPLIFICAR` y `RIESGOS` **antes** de escribir código, y decí qué cambiaste.
   - `DESCARTAR` → no avances: mostrale la `ALTERNATIVA` al usuario y esperá confirmación.
4. **Vos decidís**, pero no ignores el veredicto en silencio. Si lo ignorás, decí por qué.
5. Dejá constancia con `tarea` (acción `nota`): veredicto, modelo y qué cambiaste.

## Reglas de costo

- Un brief por decisión, no cinco consultas sobre lo mismo.
- Empezá con `k3`; subí a `opus` solo si la decisión es irreversible o hay plata/datos en juego.
- No mandes a revisar algo que ya revisaste sin cambios: usá el cache.
