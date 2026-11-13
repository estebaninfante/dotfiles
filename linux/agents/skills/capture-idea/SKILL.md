---
name: capture-idea
description: Turn an outside inspiration (an X/Twitter link, a video, a screenshot, "vi esto y quiero hacerlo acá") into a named idea in `machine`, with a one-line verdict and, if it goes ahead, an objective and a way to check it. Use when the user pastes a link or an image with the intent to implement it, or says "quiero hacer X", "me gusta esto", "vi esto", "quisiera que el harness haga Y".
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

## 3. Verdict in four lines, no rambling

1. **What it proposes** (one sentence, plain words).
2. **What it would cost here** (sessions, at the smallest version).
3. **Which existing piece it resembles** (so nothing is built from zero).
4. **Recommendation**: do it, do it small, park it, or drop it.

## 4. If it goes ahead: objetivo + tareas + la prueba

Only three things, nothing more:

- **Objetivo**: one sentence, what should happen.
- **Tareas**: the ordered list, added as you go. No scope freeze, no approval per
  step.
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
