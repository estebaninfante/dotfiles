# Delegación a Claude Code

Este archivo es la regla global del DeepSeek Harness para esta máquina
(`~/.dsh/AGENTS.md`, symlink a `~/dotfiles/linux/agents/delegacion-claude.md`).

## Cuándo delegar

Cuando un problema **no se resuelve** después de 2 o 3 intentos serios, o cuando cada
arreglo rompe otra cosa, **pará** y delegá a Claude Code (`~/.local/bin/claude`) con la
skill `delegate-a-claude`. No sigas acumulando variaciones de la misma idea: cada
intento con reinicios o cambios a medias le cuesta al usuario tiempo y confianza.

Señales de que ya te estancaste:

- El mismo síntoma sigue igual después de 2-3 intentos con causas distintas.
- Arreglás A y rompés B, y después al revés.
- Estás probando a ciegas (rebuild + reinicio) en vez de instrumentar y medir.
- Ya reescribiste el mismo archivo tres veces con enfoques parecidos.

## Cómo

1. Cargá la skill: `skill delegate-a-claude`.
2. Escribí el brief completo (plantilla en la skill): síntoma exacto con evidencia,
   entorno y sus trampas, **las variantes ya probadas y qué pasó con cada una**, qué no
   se puede romper y cómo verificar.
3. `delegar-claude start <brief.md> --name <tema>` y avisale al usuario que Claude
   está corriendo.
4. Al terminar, leé su resumen (`delegar-claude read`), **verificá vos** lo que dice y
   pasale al usuario: qué cambió, con qué evidencia, qué reinicios hubo y qué queda de
   su lado (sudo, relogin, prueba manual).

## Regla de honestidad

Si te estancaste, decilo antes de que el usuario lo note. Un "esto no lo estoy
resolviendo, lo delego" a tiempo vale más que cinco intentos más.
