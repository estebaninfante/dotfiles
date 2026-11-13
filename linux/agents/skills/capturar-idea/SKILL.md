---
name: capturar-idea
description: Convertir una inspiración externa (link de X, video, captura, "vi esto y quiero hacerlo acá") en una idea nombrada, con veredicto, preguntas de alcance y Definition of Done antes de tocar código. Usar cuando el usuario pegue un enlace o una imagen con la intención de implementar algo, o diga "quiero hacer X", "me gusta esto", "vi esto", "quisiera que el harness haga Y".
---

# Capturar idea → proyecto

El usuario es disperso: soltar la idea es fácil, sostenerla no. Este flujo existe
para que **nada se pierda** y para que ningún proyecto arranque sin borde.

Regla base: **primero se captura, después se opina, después se define, y recién
al final se escribe código.** Si se saltea un paso, se pierde el proyecto.

## 1. Leer la fuente (sin adivinar)

- Si es un link: `web_fetch`. Si es una captura, mirarla.
- Si la fuente no da el contenido (video, hilo cortado, login), decirlo en una
  línea y pedir solo la parte que falta: *"del video no puedo ver nada; contame
  en una frase qué muestra"*.
- **Nunca inventar** el contenido de un video o de un hilo que no se leyó.

## 2. Capturar ya, con nombre

```bash
machine idea --title "Dos o tres palabras" "<qué es + link + por qué me importa>"
```

- El nombre va **corto y decible**: "Interacción intra-turno", "Estándar de apps".
  El texto largo va en el cuerpo, nunca en el nombre.
- Si ya existe algo parecido (`machine idea` para listar), no duplicar: ampliar.

## 3. Veredicto en cinco líneas

Sin vueltas, con estructura fija:

1. **Qué propone** (una frase, en criollo).
2. **Qué costaría acá** (horas o sesiones, con el alcance mínimo).
3. **Qué pieza existente se parece** (para no construir de cero).
4. **Si encaja en el harness o va aparte.**
5. **Recomendación**: hacerlo, hacerlo chico, guardarlo o descartarlo.

## 4. Preguntas de alcance (máximo 3)

Solo las que cambian el trabajo. Típicas:

- ¿Esto es para *vos* o para que lo use otra persona?
- ¿Qué es lo mínimo que ya te sirve? (la versión que se puede cerrar)
- ¿Cómo verificamos que quedó andando, en una frase?

## 5. Definition of Done y aprobación

- Escribir la DoD en [protocolo-proyectos.md](../../protocolo-proyectos.md):
  objetivo medible, alcance **SÍ**, alcance **NO**, criterio de terminado.
- **Esperar el "sí" explícito.** Silencio no es aprobación.

## 6. Promover y seguir

Con la DoD aprobada:

```bash
machine promote <idea> --to <nombre-de-carpeta> --dod /tmp/dod.md
```

Queda como proyecto `active` con la DoD guardada. De ahí en adelante manda el
[protocolo de proyectos](../../delegacion-claude.md): un hito por sesión, cierre
con **Cerrado / Pendiente / Siguiente paso**.

## Límites

- **Máximo 3 ideas en definición a la vez.** Si hay 4, frenar y preguntar cuál se
  pausa: es el patrón de dispersión, no un detalle.
- Una idea sin nombre corto no entra: el nombre es lo que permite hablar de ella.
- No se toca código en el paso 1-5. Ni "probar rapidito".
