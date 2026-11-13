---
name: capture-idea
description: Convierte un link, video o captura que el usuario quiere implementar en una idea con nombre en machine.
---
# Capture idea → project

The user is scattered: dropping an idea is easy, finishing it is not. This flow
exists so **nothing gets lost** and the idea is named in one line.

Base rule: **read the source, capture it, give a verdict.** No documents, no
phases, no "definition of done".

## 1. Read the source (never guess)

- Link: `web_fetch`. Image: look at it. Video: use the `watch-video` skill.
- If the source does not give the content (video with only audio, cut thread,
  login wall), say it in one line and ask only for the missing part: *"del video
  no puedo ver nada; contame en una frase qué muestra"*.
- **Never invent** what a video or a thread says.

## 2. Capture right away, with a short name

```bash
machine idea --title "Two or three words" "<what it is + link + why it matters>"
```

- The name is **short and sayable**: "Interacción intra-turno", "Estándar de apps".
  The rest goes in the body, never in the name.
- If something similar exists (`machine idea` lists them), extend that one.
- Never write the idea into `~/alicia` or into a Markdown file: the vault is
  frozen, `machine` is the only place.

## 3. Ask, don't opine (modal, never prose)

Use the **questions modal** (`ask_user_question`), not chat text. Two or three
questions, only the ones that change the work:

- **Tareas**: "what tasks do you want this to have?" — the user names them.
  - A task is a **big step of the project**: "build the app", "use it for a week",
    "fix what breaks".
  - It is **not a feature** or a technical detail: "a screen with a field", "save to
    a database", "an export button" are **subtasks** — the builder decides those.
  - Turning features into tasks is the mistake to avoid.
- **La prueba**: "how do you know it worked?".
- **Scope**, only if it changes the build (for you alone, or for other people).

**Never** do any of these:

- Estimate time or effort ("2-3 sessions", "a few hours", "a day"). The model is a
  bad predictor and the number is useless for deciding anything.
- The four-point summary (what it proposes / what it costs / what it resembles /
  whether it fits / recommendation). The user called it garbage: drop it.
- Answer your own questions in prose when the modal exists.

## 4. If it goes ahead: objetivo + tareas + la prueba

Only three things, nothing more:

- **Objetivo**: one sentence, what should happen.
- **Tareas**: the ordered list, exactly the ones the user named in the modal. No
  scope freeze, no approval per step.
- **La prueba**: how we know it worked (a number, a screenshot). Optional at the
  start.

```bash
machine promote <idea> --to <slug> --goal "…" --check "…"
machine task add <slug> "first task"
```

No explicit approval ceremony: show the plan in those three lines and keep going.
The full protocol is in `delegacion-claude.md`, "Protocolo de proyectos (simple)".

## Limits

- One idea per message; if the user drops five, capture five and say so in one
  line.
- An idea without a short name does not go in: the name is what lets us talk
  about it.
- No code until step 4 exists.
