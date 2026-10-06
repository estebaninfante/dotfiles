---
name: obsidian
description: >
  Braindump en el vault de Obsidian "alicia" (~/alicia). Guardar ideas, tareas,
  recordatorios, pensamientos largos o cualquier cosa que el usuario quiera
  capturar sin perder el hilo. Usar cuando el usuario diga "apunta esto",
  "guarda mi idea", "anótalo", "deja esto pendiente", "recordame", "braindump",
  "en alicia", "en obsidian", o pida listar/promover/completar notas.
---

# Obsidian (alicia)

Vault: `~/alicia` — estructura `Inbox/` (captura cruda), `Proyectos/` (en-curso |
estancado | hecho), `Areas/`, `Daily/`, `Archivo/`.

## Captura (uso principal)

El usuario piensa mucho y se desconcentra: **capturar es el flujo número uno**.
Reglas:

1. UN comando, confirmación de UNA línea, y **retomar la tarea anterior sin
   preguntas ni rodeos**. No frenar el trabajo en curso.
2. Contenido mezclado y libre: ideas cortas, tareas, recordatorios, pensamientos
   largos. Cuerpo lo que sea, longitud lo que sea.
3. Detectar `tipo` del contenido:
   - `idea` → propuesta, concepto, "y si hacemos..."
   - `tarea` → algo concreto a hacer, "hay que...", pendiente
   - `recordatorio` → con o sin fecha, "no olvidar...", "recordarme..."
   - `pensamiento` → reflexión larga, razonamiento, análisis
4. **Auto-captura de conversaciones (REGLA)**: cuando el usuario entra y
   pregunta, razona o piensa algo (pregunta/reflexión, no una orden mecánica de
   acción), capturar SIEMPRE como nota ADEMÁS de responder, sin esperar a que lo
   pida. Destilar tesis + lo útil, no transcribir literal.

```bash
obsidian-note add "<titulo-corto>" --body "<texto>" --tipo <idea|tarea|recordatorio|pensamiento> [--tags a,b]
```

Si el texto viene como voz/transcripción, limpiar muletillas y escribir el
cuerpo fiel (sin inventar). Título: 3-7 palabras en lowercase con guiones no
hace falta — el script slugifica.

Confirmación tipo: `Guardado en Inbox: 2026-1006-titulo.md` — después CONTINUAR
con lo que se estaba haciendo.

## Consulta y organización

```bash
obsidian-note list [--tipo <t>] [--estado <e>]   # TSV: ruta, tipo, estado, titulo
obsidian-note promote <ref> [--to Proyectos] [--estado en-curso]
obsidian-note done <ref>                          # estado: hecha
obsidian-note path                                # ruta del vault
```

`<ref>`: substring del nombre de archivo (basta con palabras clave). "¿qué tengo
pendiente?" → `list --estado pendiente`. "promueve X a proyecto" → `promote`.
"ya lo hice / táchalo" → `done`.

## Tablero / Dataview

`~/alicia/Tablero.md` es el dashboard vivo del vault: queries Dataview agrupadas
por estado/tipo (Inbox pendientes, en curso, recordatorios, últimas capturas).
Plugin Dataview instalado en `~/alicia/.obsidian/plugins/dataview/` (fuera del
repo, es data del usuario) y habilitado en `community-plugins.json`. Dataview
corre SOLO con Obsidian abierto; el plugin se actualiza desde la app. Mantener el
frontmatter (`tipo`, `estado`, `tags`, `fecha`) es lo que alimenta el tablero.

## Verificación

Tras tocar el script: `verify auto ~/.local/bin/obsidian-note` y
`obsidian-note --selftest`.
