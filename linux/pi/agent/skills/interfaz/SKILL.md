---
name: interfaz
description: Reglas para diseñar y revisar interfaces (web, escritorio o CLI) con foco en jerarquía, espaciado y minimalismo; si el repo tiene docs/ui/PATRONES.md, lleva a ese contrato (patrones, galería, bocetos). Usar SIEMPRE que se cree o modifique una pantalla, vista, componente, menú o formulario; cuando haya que decidir qué botones mostrar, cuánto espacio usar o cómo ordenar la información; y cuando el usuario pida "minimalista", "menos botones", "que se entienda en 3 segundos", "respetá los espacios" o "no tener que traducir tanto".
---

# Interfaz

Tu trabajo no es agregar elementos hasta cubrir todas las funciones. Es lograr
que la persona entienda en 3 segundos qué hacer. Cada elemento que agregás le
quita atención a los demás. Ante la duda, quitá.

## 0. Primero: ¿el repo tiene su contrato de UI?

Buscá `docs/ui/PATRONES.md` en el proyecto (o en la app dentro del monorepo,
p. ej. `erp/docs/ui/PATRONES.md`). **Si existe, manda sobre todo este archivo**:

1. Leelo completo y abrí su galería viva (`/es/patrones`, código en
   `app/[locale]/patrones/`).
2. No diseñes: elegí el patrón de su tabla "Si te piden… → patrón" y nombralo
   en tu plan.
3. Pantalla nueva o cambio grande de layout → **boceto** en
   `app/[locale]/boceto/<slug>/` + `pnpm boceto <slug>`; entregá enlace y
   capturas y esperá aprobación antes de construir.
4. Construí solo con las piezas de los kits que lista. Si el lint de UI falla,
   arreglá el código; nunca subas `eslint-suppressions.json`.
5. Cerrá con su línea: **Patrón: … · Oculté/simplifiqué: … · Piezas nuevas: …**

Las secciones de abajo aplican solo donde ese archivo no dice nada, o en repos
que no lo tienen. En un repo sin contrato, antes de maquetar abrí las dos
pantallas existentes más parecidas a lo que te piden y copiá su estructura,
componentes y espaciado: parecerse al vecino gana sobre cualquier regla de acá.

## 1. Antes de escribir código

Respondé en tu razonamiento, no en la respuesta:

- ¿Cuál es la **única** tarea principal de esta pantalla?
- ¿Cuál es la **acción primaria**? (debe ser una sola)
- ¿Qué es secundario y qué puede esconderse hasta que se necesite?

Si no podés nombrar la acción primaria, no empieces a maquetar.

## 2. Jerarquía de acciones (anti-botones)

- Máximo **1 botón primario** (relleno, color de acento) por vista o por sección.
- Máximo **1-2 secundarios** (borde o estilo sutil) junto al primario.
- Todo lo demás va como enlace de texto, icono con tooltip, o dentro de un menú
  "más acciones" (`⋯`).
- Acciones destructivas (eliminar, descartar): nunca primarias; piden
  confirmación o permiten deshacer.
- Acciones por fila de tabla/lista: máximo 2 visibles; el resto en un menú de
  overflow.
- Prohibido repetir la misma acción en varios lugares de la misma vista.
- Si dos botones hacen casi lo mismo, fusionálos o eliminá uno.
- "Un botón por cada función que existe" **no** es un criterio para mostrarlo.

## 3. Espaciado (sistema, no intuición)

- Usá **solo** una escala base de 4/8: `4, 8, 12, 16, 24, 32, 48, 64`.
- Definí la escala una vez (variables CSS / tokens / config de Tailwind) y usala
  siempre. Nada de valores arbitrarios (5px, 13px, 18px, 22px).
- Regla de proximidad: lo relacionado va junto, lo no relacionado va separado.
  El espacio **entre** grupos debe ser claramente mayor que el espacio **dentro**
  de un grupo (ej. 8-12px dentro, 24-32px entre grupos).
- Padding de contenedores/tarjetas: 16-24px. Márgenes de página: 16px en móvil,
  24-48px en escritorio.
- El mismo tipo de elemento usa siempre el mismo espacio.
- Preferí `gap` en flex/grid antes que márgenes sueltos en cada hijo.
- No pegues elementos a los bordes del contenedor. Nada sin padding.
- Dejá espacio vacío a propósito: el espacio en blanco es diseño, no desperdicio.

## 4. Densidad y saturación

- Límite orientativo por vista: 1 título, 1 acción primaria, 1 bloque principal
  de contenido. Si hay más de ~5-7 elementos interactivos visibles a la vez,
  revisá qué puede esconderse.
- Divulgación progresiva: detalles avanzados, filtros poco usados y ajustes van
  en paneles colapsables, modales, drawers o pestañas.
- No uses bordes, sombras y fondos de color al mismo tiempo para separar lo
  mismo. Elegí uno (preferiblemente espacio).
- No anides tarjetas dentro de tarjetas dentro de tarjetas.
- Máximo 2 pesos tipográficos y 3-4 tamaños de texto por pantalla.
- Máximo 1 color de acento + neutros + colores semánticos (error/éxito/aviso);
  los semánticos solo con significado semántico.
- Iconos: solo si aclaran. No pongas un icono decorativo en cada botón.
- No agregues textos de ayuda, badges, contadores ni etiquetas "por si acaso".

## 5. Reglas de UX obligatorias

- Alineación: todo se alinea a una cuadrícula o a un borde común. Sin elementos
  "flotando" a ojo.
- Tamaño táctil mínimo: 44x44 px (móvil), 32-40 px de alto en escritorio.
- Contraste de texto: mínimo 4.5:1 (WCAG AA).
- Etiquetas de botón: verbo + objeto claro ("Guardar cambios", no "OK" ni
  "Enviar").
- Formularios: una columna, etiquetas visibles encima del campo (no solo
  placeholder), errores junto al campo, solo los campos estrictamente necesarios.
- Estados: toda vista y componente interactivo define **loading, vacío, error y
  éxito**. Los estados vacíos explican qué hacer ahora.
- Feedback inmediato tras cada acción (toast, cambio de estado, etc.).
- Orden visual = orden de importancia = orden de lectura (arriba-izquierda
  primero).
- Responsive: diseñá primero para móvil; no tires botones en fila si no caben,
  apílalos o reducí acciones.

## 6. Trabajar sobre código existente

- Respetá los componentes, tokens y estilos que ya existen. No inventes nuevos
  si hay uno equivalente.
- No agregues funciones, botones o secciones que no se pidieron.
- Si te piden "añadir X", integrá X sin multiplicar los elementos alrededor.
- Cambios mínimos: no rediseñes lo que no te pidieron tocar.

## 7. Checklist de verificación (antes de entregar)

Revisá cada punto y corregí lo que falle:

1. ¿Hay exactamente una acción primaria clara por vista/sección?
2. ¿Todo el espaciado usa la escala definida, sin números arbitrarios?
3. ¿Puedo quitar algún botón, icono o texto sin perder la función principal?
4. ¿Hay acciones duplicadas o casi iguales?
5. ¿Lo agrupado está junto y los grupos están claramente separados?
6. ¿Funciona en 360 px de ancho sin desbordes ni botones apretados?
7. ¿Están definidos los estados de carga, vacío y error?
8. ¿Se ve ordenado al entrecerrar los ojos (jerarquía visible sin leer)?

## 8. Al entregar

Indicá en una o dos líneas qué decidiste **ocultar o simplificar** y por qué.
