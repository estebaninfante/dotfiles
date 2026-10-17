---
name: metodo-software
description: Método de trabajo para construir y cambiar software pensando en agentes. Usala en cualquier tarea de software (features, bugs, refactors, apps). Triggers: implementar, feature, bug, refactor, app, verificar, test, arquitectura, escalar, agentes.
---

# Método de software (pensado para agentes)

El objetivo no es escribir más código, es que **otro agente entienda y extienda
esto sin contexto previo**, y que **pueda verificar que funciona** antes de
publicar. Menos código, más claro.

## Los cinco pasos

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

## Regla de oro

Si no podés mostrar cómo se verifica, no terminaste.
