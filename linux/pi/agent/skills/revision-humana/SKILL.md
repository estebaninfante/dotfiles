---
name: revision-humana
description: "Registrar y revisar artefactos que necesitan ojo humano (skills, agentes, extensiones). Usala siempre que crees una skill o un agente, o cuando el usuario pida ver qué quedó pendiente de revisar. Triggers: revisión, revisar, pendiente, aprobar, skill nueva, agente nuevo, cola de revisión."
---

# Revisión humana

Nada nuevo se da por bueno sin que el usuario lo mire. Especialmente **skills** y
**agentes**: se instalan al toque, pero quedan anotados para revisión.

## La regla

1. **Instalá de inmediato** lo que creaste (symlink, registro, copia al lugar que
   corresponda). No esperes la revisión para instalarlo.
2. **Anotalo** con la tool `pedir_revision_humana`:
   - `tipo`: skill, agente, extension, app, doc…
   - `nombre`: cómo se llama.
   - `ruta`: dónde quedó.
   - `nota`: qué debería mirar el usuario.
3. **Avisale** en la respuesta: qué creaste, dónde quedó, y que está pendiente.

## Ver qué hay pendiente

- Tool `revisiones_pendientes` (acción `listar`).
- Comando `/revisiones`.
- Al arrancar cada sesión, si hay pendientes, el rig avisa solo.

## Resolver

Cuando el usuario ya lo revisó, marcalo con `revisiones_pendientes` acción
`resolver`, con el `id` y el estado (`revisada` o `ajustada`).

## Por qué

Si no queda anotado, se olvida. La cola es la memoria externa: el usuario mira
`/revisiones` cuando quiere y nada se pierde.
