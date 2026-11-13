# Estándar de ideas (todas las IAs)

Una idea se captura **con nombre** y vive en `machine` (la base de la página
"Proyectos e ideas" del harness). No va al chat, no va a un archivo Markdown y no
va al vault `~/alicia`: ese vault queda **congelado** como notas personales del
usuario, ninguna IA escribe ahí.

## Capturar

Cuando aparezca una idea que no es una orden concreta sobre la máquina:

```sh
machine idea --title "Dos o tres palabras" "<qué es + por qué importa>"
```

- El nombre es corto y decible: "Estándar de apps", "Patrones de UI".
- El cuerpo es una o dos frases. No se escriben documentos, fases ni plantillas.
- Confirmá en una línea: `Anotado: <título>`. No preguntes "¿lo guardo?".

## Distinguir

- **Idea suelta** → `machine idea --title …`.
- **Ya existe algo parecido** (`machine idea` las lista) → sumá al cuerpo de esa,
  no dupliques.
- **Trabajo concreto en un proyecto** → `machine task add <proyecto> "<tarea>"`.
- **Proyecto nuevo** → `machine promote <idea> --to <slug> --goal "…" --check "…"`.

## Consultar

- `machine ls` — todo; `machine show <slug>` — una ficha.
- El panel **Proyectos e ideas** del harness: es la vista que usa el usuario.

## Cerrar

- Tarea hecha: `machine task done <id>`.
- Proyecto terminado o aparcado: `machine set <slug> --state done|paused|archived`.
