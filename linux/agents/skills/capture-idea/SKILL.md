---
name: capture-idea
description: Turn an outside inspiration (an X/Twitter link, a video, a screenshot, "vi esto y quiero hacerlo acá") into a named idea, a short verdict, scope questions and a Definition of Done before any code is written. Use when the user pastes a link or an image with the intent to implement it, or says "quiero hacer X", "me gusta esto", "vi esto", "quisiera que el harness haga Y".
---
# Capture idea → project

The user is scattered by nature: dropping an idea is easy, sustaining it is not.
This flow exists so **nothing gets lost** and no project starts without edges.

Base rule: **capture first, then give a verdict, then define, and only then write
code.** Skip a step and the project dies.

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
  The long text goes in the body, never in the name.
- If something similar exists (`machine idea` lists them), extend it instead of
  duplicating.

## 3. Verdict in five lines

Fixed shape, no rambling:

1. **What it proposes** (one sentence, plain words).
2. **What it would cost here** (hours or sessions, at the minimum scope).
3. **Which existing piece it resembles** (so nothing is built from zero).
4. **Whether it fits the harness** or belongs elsewhere.
5. **Recommendation**: do it, do it small, park it, or drop it.

## 4. Scope questions (three, maximum)

Only the ones that change the work:

- Is this for *you* or for someone else to use?
- What is the smallest version that already helps you?
- How do we check that it works, in one sentence?

## 5. Definition of Done, then approval

- Write the DoD using the template in
  [protocolo-proyectos.md](../../protocolo-proyectos.md): measurable goal, scope
  **YES**, scope **NO**, definition of done.
- **Wait for an explicit yes.** Silence is not approval.

## 6. Promote and track

Once approved:

```bash
machine promote <idea> --to <folder-name> --dod /tmp/dod.md
```

It becomes an `active` project with the DoD stored. From then on the
[project protocol](../../delegacion-claude.md) rules: one milestone per session,
closing with **Cerrado / Pendiente / Siguiente paso**.

## Limits

- **At most 3 ideas in definition at once.** With 4, stop and ask which one is
  paused: that is the scatter pattern, not a detail.
- An idea without a short name does not go in: the name is what lets us talk
  about it.
- No code in steps 1-5. Not even "just a quick test".
