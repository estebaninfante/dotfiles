---
description: Captura una idea, proyecto o reflexión en Mental/Ideas/. Infiere tipo, área y etiquetas automáticamente.
---

El usuario te da una idea, proyecto, reflexión o pensamiento que quiere guardar sin perder el foco de lo que estaba haciendo.

## Tu trabajo

1. **Parsea el texto** del usuario (`$ARGUMENTS`). Puede ser una frase suelta, un párrafo, o varias ideas mezcladas.

2. **Infiera automáticamente:**
   - **`tipo`**: `proyecto` si es algo concreto que quiere construir/hacer (tiene acción clara). `idea` si es vago, un "esto sería genial", una reflexión.
   - **`area`**: una de las 7 áreas del vault (Financiera, Física, Trascendental, Recreativa, Mental, Social, Profesional). Si no encaja claro, deja `area: ""`.
   - **`etiquetas`**: 1-3 tags descriptivos del contenido (libres, no necesitan ser del vault).
   - **`prioridad`**: `alta` si suena urgente o muy importante para el usuario; `media` si es interesante pero no urgente; `baja` si es un "algún día".

3. **Crea la nota** en `Mental/Ideas/` usando la plantilla:
   - Nombre: slug del título (minúsculas, guiones, sin tildes ni caracteres raros)
   - Frontmatter: todos los campos de la plantilla + los inferidos
   - Cuerpo: el texto tal cual lo dio el usuario, más cualquier observación breve que ayude a recordar el contexto

4. **Si es un proyecto accionable** (tipo `proyecto` con acción clara): sugiere una o más tareas Tasks con sintaxis `- [ ] descripción 📅 YYYY-MM-DD #area`. No las crees automáticamente; solo sugiérelas.

5. **Confirma** al usuario: ruta de la nota creada y qué inferiste (tipo, área). Breve.

## Formato de la nota

Usa la plantilla en `Mental/Ideas/Plantillas/idea.md` como base. Rellena el frontmatter con la fecha de hoy y los campos inferidos. En el cuerpo, preserva el texto original del usuario.

## Si el usuario da varias ideas en un solo mensaje

Crea una nota por idea. Si están muy relacionadas, enlaza entre sí con `[[...]]` en el frontmatter `relacionadas`.

## Si el texto es ambiguo

Guarda lo que tengas. No pidas clarificación — el punto es no interrumpir. Si algo queda sin inferir, deja el campo vacío. El usuario puede ajustar después.
