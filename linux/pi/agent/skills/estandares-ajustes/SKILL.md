---
name: estandares-ajustes
description: >
  Organizar las opciones de un menú de ajustes según el estándar de las
  interfaces de escritorio, no según el gusto de quien programa. Usala SIEMPRE
  que armes, revises u ordenes un menú de configuración, una pantalla de ajustes,
  un panel de preferencias o las opciones dentro de una sección (Accesibilidad,
  Pantallas, Sonido, etc.). También cuando el usuario diga "está organizado como
  se te da la gana", "no sigue el estándar", "así no van las opciones" o pida
  copiar la estructura de macOS, GNOME o Windows. Triggers: ajustes, settings,
  preferencias, menú, sidebar, categoría, submenú, orden de opciones, HIG.
---

# Estándares de ajustes

Un menú de configuración no se inventa: **se mapea**. Las personas ya vieron
miles de menús de ajustes y esperan que las cosas estén donde siempre están. Tu
trabajo es ubicar cada función en la categoría y el orden que la plataforma ya
estableció, no en el que te parece más cómodo a vos.

Esta skill es para **dónde va cada cosa**. Para cuánto espacio, cuántos botones o
cómo se ve, usá también `interfaz`.

## 1. Fuentes del estándar (en orden de prioridad)

1. La plataforma del sistema: **Apple HIG**, **GNOME HIG**, **Microsoft Fluent**.
2. El idioma del resto de la app y del sistema operativo.
3. La convención del área concreta (accesibilidad, pantallas, sonido, red).

Si hay que inventar una categoría nueva, es señal de que la función no está bien
mapeada. Primero buscá en qué categoría estándar cae.

## 2. Esqueleto

```
Ventana / app
└── Sidebar de categorías de primer nivel
    └── Página de la categoría (lista de subcategorías o grupos)
        └── Página de detalle de una subcategoría
            └── Grupos de filas
```

- **Sidebar**: categorías de primer nivel. Nunca una grilla de tarjetas que
  repita lo mismo que ya está en la sidebar.
- **Página de categoría**: cabecera con icono, título y una frase de qué es;
  después las subcategorías como filas (icono, título, descripción, chevron).
- **Página de detalle**: mismas cabecera y filas, pero de las opciones concretas.
- La categoría activa en la sidebar se marca con **fondo/contraste**, no con una
  barrita vertical de acento pegada al borde.

## 3. Taxonomía estándar de primer nivel

Usá estos nombres y este orden (el que no aplique, se omite):

`General / Sistema · Apariencia · Pantallas · Sonido · Notificaciones · Red ·
Bluetooth · Energía · Privacidad y seguridad · Accesibilidad · Usuarios · Acerca de`

No crees "Extras", "Avanzado" ni "Varios" en el primer nivel: eso es una señal
de que no supiste mapear las funciones.

## 4. Subcategorías estándar de Accesibilidad

Orden de referencia (Apple/GNOME):

1. **Visión** — tamaño de texto, zoom, contraste, color, cursor, lupa.
2. **Audición** — subtítulos, alertas visuales, mono audio.
3. **Voz** — dictado, voz del sistema, palabras clave, comandos de voz.
4. **Movimiento / Interacción** — pointer, teclado, gestos, control por cabeza.

## 5. Orden dentro de una página de detalle

Cada página agrupa en este orden, de arriba abajo:

1. **Estado / resumen**: qué está configurado y si funciona.
2. **Acción principal**: una sola (calibrar, entrenar, probar).
3. **Opciones frecuentes**: interruptores, selectores y ajustes de uso diario.
4. **Opciones avanzadas**: se pliegan o viven en un subgrupo separado.
5. **Privacidad / datos**: qué se guarda y dónde, si aplica.

Cada grupo: 3 a 7 filas. Más de eso, partilo por función, no por tipo de control.

## 6. Qué va en cada control

- **Interruptor (on/off)**: opciones que se prenden y apagan en el momento.
- **Selector**: elegir una de pocas opciones cerradas.
- **Deslizador**: magnitud continua (velocidad, tamaño, sensibilidad).
- **Fila con chevron**: abre otro nivel; nunca se usa para una acción.
- **Botón**: acción puntual. Uno primario por página; el resto, secundario.
- **Diálogo**: solo para lo destructivo o irreversible.
- Los controles son los del sistema. No inventes controles nuevos.

## 7. Reglas duras

- Una opción, un solo lugar. Prohibido repetir la misma entrada en la sidebar y
  en el contenido.
- Etiquetas de fila: sustantivo corto ("Visión", "Palabras clave"). La
  descripción debajo, en una frase.
- Orden de la fila = orden de importancia percibida. Lo más usado primero.
- "General" muestra estado y accesos; no repite la lista de la sidebar.
- No uses emojis. Iconos del set del sistema o SVG de línea.
- No uses píldoras/badges de estado: el estado es texto con un punto, o una fila.
- No agregues "Avanzado" en el primer nivel; si hace falta, va dentro de la
  categoría que corresponde.
- Si el sistema ya tiene una palabra para esa opción, usá esa palabra.

## 8. Checklist antes de entregar

1. ¿Cada función está en una categoría estándar, con el nombre estándar?
2. ¿El orden de la sidebar sigue la taxonomía de la sección 3?
3. ¿Accesibilidad sigue el orden Visión → Audición → Voz → Movimiento?
4. ¿La página muestra estado, luego acción principal, luego opciones, y al final
   lo avanzado?
5. ¿Hay alguna opción repetida entre la sidebar y el contenido?
6. ¿Cada fila tiene icono, título y descripción, y solo lleva chevron si abre
   otro nivel?
7. ¿Se eliminaron barras decorativas, píldoras y emojis?
8. ¿Un agente nuevo entendería dónde agregar una opción sin preguntarte?
