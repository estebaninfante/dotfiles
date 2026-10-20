---
name: crear-skills
description: Crear y mantener skills de IA simples, modulares y versionadas. Usala cuando haya que crear una skill, convertir un aprendizaje o un procedimiento repetido en skill, actualizar o recortar una skill existente, o decidir si algo va en una skill, en AGENTS.md o en un asset. Triggers: crear skill, nueva skill, guardar aprendizaje, convertir en skill, mejorar skill, gestión de skills.
---

# Crear y gestionar skills

Una skill es una receta corta: le dice al agente **cuándo** actuar y **qué pasos**
seguir, con los recursos a mano. No es un manual.

## Cuándo crear una

- El trabajo se repite y siempre lleva el mismo orden.
- Hay una restricción o un formato que el agente no adivina solo.
- Otro agente debe poder encontrarla y ejecutarla sin contexto previo.

No crear para un dato único, para algo que ya dice el repo, ni para algo que el
agente ya hace por defecto.

## Pasos

1. **Definí en una línea** el disparador y el resultado. Si no cabe, son dos
   skills. → hecho cuando podés nombrarla sin explicar el contexto.
2. **Elegí la invocación.** Si otro agente debe encontrarla, va con
   `description` y triggers. Si solo la llama el humano, agregá
   `disable-model-invocation: true` y dejá la descripción en una línea.
3. **Escribí `SKILL.md`** con: frontmatter, una línea de qué resuelve, pasos
   numerados, restricciones y verificación. Cada paso termina en un criterio
   observable ("existe X y pasa Y"), no en "entender".
4. **Nombrá la herramienta exacta** de cada paso (comando, tool, ruta). Si la
   skill recibe datos, decí al inicio dónde entran (URL, ruta, parámetro).
5. **Si hay plantillas o formatos estables**, van a `assets/` y se referencian
   desde el paso que los usa. Lo largo se va ahí, no al cuerpo.
6. **Instalá**: la skill vive en `~/dotfiles/linux/pi/agent/skills/<nombre>/` y
   se enlaza con
   `ln -s ~/dotfiles/linux/pi/agent/skills/<nombre> ~/.pi/agent/skills/<nombre>`.
   Nunca crearla solo bajo `~/.pi`.
7. **Publicá**: `~/dotfiles/scripts/dotfiles-sync.sh --force`.
8. **Pedí revisión humana** con la tool `pedir_revision_humana` (tipo, nombre,
   ruta, qué mirar) y avisá al usuario.
9. **Probá el disparador**: pedí la tarea sin nombrar la skill y mirá si se
   invoca sola.

## Reglas

- Una skill por tarea. Si crece, partila por secuencia o por invocación.
- Que entre en una pantalla. Lo demás va a `assets/`.
- Prohibiciones explícitas: nada destructivo sin confirmación; nunca secretos
  dentro de la skill.
- Una sola fuente de verdad: si el dato ya vive en el repo o en la config,
  apuntá a él en vez de copiarlo.
- Español claro y directo, sin jerga de más.

## Verificación

- [ ] `name` y `description` existen y los triggers son frases reales.
- [ ] El symlink está creado y la skill aparece en la lista.
- [ ] Se invoca con una frase de todos los días.
- [ ] `dotfiles-sync.sh --force` terminó y el repo quedó limpio.

## Lecciones

- Verificá **lo que el usuario ve**, no solo la fuente: si hay build o
  instalación de por medio, reconstruí, instalá y mirá el artefacto final.
- Todo cambio de software: worktree, verificador determinista y `make check`
  antes de decir que está listo.
- Cambio caro de revertir: pedí segunda opinión antes de escribir código.
- Antes de borrar algo, listá qué pierde el usuario y confirmalo.

## Plantilla

`assets/SKILL-template.md`
