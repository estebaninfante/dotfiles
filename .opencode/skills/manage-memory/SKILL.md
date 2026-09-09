---
name: manage-memory
description: Gestiona la memoria persistente del agente (MEMORY.md). Lee al inicio, actualiza al final. Analiza patrones, crea skills, auto-mejora. Trigger: "memory", "memoria", "recordar", "aprendizaje", "patrón".
---

# Manage Memory — Memoria persistente del agente

Este skill gestiona el ciclo de memoria del agente dotfiles.

## Al INICIO de cada sesión

1. Lee `~/dotfiles/MEMORY.md`
2. Carga el contexto de sesiones anteriores
3. Usa esa memoria para tomar mejores decisiones

## Al FINAL de cada sesión

Actualiza `~/dotfiles/MEMORY.md` con estos pasos:

### 1. Resumen de sesión
Añade en "Historial de sesiones":
```
- [FECHA]: [QUÉ SE HIZO] — [QUÉ FUNCIONÓ] — [QUÉ NO FUNCIONÓ]
```

### 2. Patrones detectados
Si algo se repitió 3+ veces:
```
- [PATRÓN]: [DESCRIPCIÓN] — [FRECUENCIA] — [SOLUCIÓN/ACCIÓN]
```

### 3. Errores comunes
Si hubo error y se resolvió:
```
- [ERROR]: [CAUSA] → [SOLUCIÓN]
```

### 4. Auto-mejora
Si detectaste oportunidad de mejora:
- ¿Nueva skill? → Crea en `.opencode/skills/<nombre>/SKILL.md`
- ¿Nuevo script? → Crea en `linux/bin/`
- ¿Nuevo subagente? → Crea en `.opencode/agent/<nombre>.md`
- ¿Config mejorable? → Actualiza `opencode.json` o `agent/dotfiles.md`

### 5. Limpieza
Mantén solo las últimas 5 sesiones. Borra las más antiguas.

## Análisis de patrones (cada 5 sesiones)

Cuando MEMORY.md tenga 5+ entradas en "Historial de sesiones":
1. Lee todas las entradas
2. Identifica patrones repetidos
3. Para cada patrón con 3+ menciones:
   - Crea skill si es procedural
   - Crea script si es bash repetitivo
   - Actualiza AGENTS.md si es regla
4. Documenta las skills creadas en "Skills creadas"
5. Limpia el historial a las 5 más recientes

## Formato de MEMORY.md

```markdown
# MEMORY.md — Memoria persistente del agente dotfiles

## Patrones detectados
- [PATRÓN]: [DESCRIPCIÓN] — [FRECUENCIA] — [ACCIÓN]

## Errores comunes y soluciones
- [ERROR]: [CAUSA] → [SOLUCIÓN]

## Configuraciones frecuentes
- [CONFIG]: [CUÁNDO SE MODIFICA] — [PARÁMETROS TÍPICOS]

## Skills creadas
- [SKILL]: [QUÉ HACE] — [CUÁNDO SE USA]

## Pendientes de mejora
- [MEJORA]: [POR QUÉ] — [PRIORIDAD]

## Historial de sesiones (últimas 5)
- [FECHA]: [RESUMEN]
```
