---
name: buscar-en-internet
description: "Buscar en internet y leer páginas antes de responder. Usala cuando no estés seguro, cuando el usuario explique algo que no entendés, o cuando el dato pueda haber cambiado (versiones, precios, noticias, lanzamientos, APIs, personas, eventos). Triggers: buscar, internet, web, noticias, última versión, precio, documentación actualizada, verificar, no estoy seguro, no entiendo."
---

# Buscar en internet

Antes de responder, buscá. Ante cualquier duda, el primer paso es la búsqueda, no la suposición.

## Herramientas

- `buscar_web` — busca en DuckDuckGo y devuelve título, URL y resumen.
  - `consulta`: qué buscar (obligatorio).
  - `limite`: cuántos resultados (1-10, por defecto 6).
- `leer_pagina` — abre una URL y devuelve su texto legible.
  - `url`: link http(s) (obligatorio).
  - `maxCaracteres`: tope de texto (por defecto 8000).

## Cómo proceder

1. Si el usuario te explica algo que no entendés, o no estás seguro, **buscá primero**.
2. Si el tema puede haber cambiado, **buscá primero**: versiones, precios, noticias,
   lanzamientos, APIs, personas, eventos, clima, documentación.
3. Con los resultados, abrí con `leer_pagina` la fuente que más prometa y leé lo necesario.
4. Respondé recién ahí. **Citá las URL** que usaste.
5. Si la búsqueda no aclara, decilo explícitamente. Nunca inventes datos ni fechas.
6. Preferí fuentes primarias: documentación oficial, repositorios, sitios oficiales.

## Cuándo NO hace falta

- Si la respuesta depende solo de archivos locales que ya leíste.
- Si es una operación sobre el repositorio (editar, mover, compilar) y no hay duda de contenido.
- Si el usuario te pide explícitamente no buscar.

## Formato de la respuesta

- Empezá por la respuesta, después el detalle.
- Cuando uses datos de la web, agregá las fuentes al final, en una línea:
  `Fuentes: <url1> · <url2>`.
- Si hay conflicto entre fuentes, mencionalo y quedate con la más reciente o autoritativa.
