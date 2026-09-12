---
name: zentro-ui
description: >
  UI/UX conventions for Zentro. Load when building, editing, or reviewing any
  React/Next.js UI component, page, or layout. Covers design tokens, component
  patterns (shadcn/ui), spacing, colors, dark mode rules, and common layouts.
  Auto-triggers on *.tsx files with JSX. Also triggers on "build UI", "create
  component", "design", "style", "layout", "UX", "UI".
---

# Zentro UI System

Canonical reference for building UI in Zentro. Follow these patterns for
consistency. Deviations are allowed — this is your app — but default to these.

## 1. Design Tokens

**Palette** (from `app/globals.css`):

| Token | Dark Mode | Usage |
|---|---|---|
| `--background` | `#111114` | Page background |
| `--foreground` | `#DEDED9` | Primary text |
| `--card` | `#16161A` | Card/panel backgrounds |
| `--muted` | `#202026` | Subtle backgrounds, inputs |
| `--muted-foreground` | `#96958F` | Secondary text |
| `--border` | `#232329` | Borders, dividers |
| `--accent` | `#26262C` | Hover states, selected bg |
| `--destructive` | `#DC2626` | Errors, delete actions |
| `--success` | `#16A34A` | Success states |
| `--warning` | `#A16207` | Warning states |

**Typography**: Geist (sans), Geist Mono (mono). `--radius: 0.25rem`.

**NEVER use**: Pure black (`#000`), pure white (`#FFF`), raw hex colors in
components (use tokens), saturated greens/reds on dark backgrounds (use
muted variants like `text-emerald-400` not `text-green-600`).

## 2. Component Conventions (shadcn/ui "New York")

All UI primitives live in `components/ui/`. Pattern:

```tsx
import { cn } from "@/lib/utils"

function Component({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div data-slot="component" className={cn("base-classes", className)} {...props} />
  )
}

export { Component }
```

Rules:
- **Named exports** — never `export default`
- **`cn()`** for class merging (clsx + tailwind-merge)
- **`data-slot`** attribute on every root element
- **`className` as last prop** — allows override
- **`React.ComponentProps<"element">`** for typing — not custom interfaces
- **cva** for variant-driven components (Button, Badge, etc.)
- **`asChild`** pattern via `@radix-ui/react-slot` for polymorphic rendering
- **Function declarations** — `function Foo()`, not `const Foo = () =>`
- **`'use client'`** only when needed (interactivity, hooks)

## 3. Layout Rules

### Sidebar
- Fixed `w-[400px] max-w-[92vw]`, absolute positioned
- Padding: `px-4 py-3` for content areas
- Scrollable content: `flex-1 overflow-y-auto overflow-x-hidden`
- **Fullscreen mode**: `w-full` with `mx-auto max-w-[1100px]` inner wrapper
  to constrain content on ultrawide screens — never let elements stretch edge-to-edge

### Cards (result cards, list items)
- **Full width** — never `mx-2` or horizontal margins that waste space
- `rounded-xl border border-border/60 bg-background/40`
- Internal padding: `px-3.5 py-4` (normal) / `p-4` (compact grid mode)
- Sections separated by `border-t border-border/30 my-3`
- More vertical breathing room: `my-1.5` between cards

### Buttons in cards
- Always `flex-1` to fill available space equally
- `justify-center` for even distribution
- Style: `rounded-lg border border-border/40 bg-muted/60`
- Disabled: `opacity-40 pointer-events-none cursor-not-allowed`
- Never hide buttons — show them disabled when data is missing

### Fullscreen Sidebar Layout
When sidebar is expanded (`expanded && activeTab === "discover"`):
- Flex row: left panel (scrollable) + right panel (BusinessDetailPanel, `w-[380px]`)
- Left panel inner content wrapped in `mx-auto max-w-[1100px]` to prevent edge-to-edge stretching
- Grid of cards: `grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4`
- Non-discover tabs also use `mx-auto max-w-[1100px]` wrapper for consistent centering

## 4. UX Patterns

### Tags/Chips
- **Container**: `flex w-full items-center gap-1.5 flex-wrap rounded-lg border border-border/30 px-2.5 py-2`
- **Individual tags**: `rounded-full text-[10px] font-medium text-muted-foreground` — NO background, NO border on individual tags
- **Overflow**: Click to expand/collapse. Show `+N más` / `▾ colapsar`
- Never let tags overflow their container

### Dropdowns/Selects
- Trigger: `w-full flex items-center justify-between h-9 px-3 rounded-lg border border-border/40 bg-muted/40`
- Menu: `w-full rounded-lg border border-border bg-card shadow-lg py-1`
- Open upward (`bottom-full`) when near bottom of container
- Chevron rotation on open: `transition-transform`

### Status/Pills
- **Open/Closed**: Use muted colors — `text-emerald-400` (open), `text-red-400` (closed). Just dot + text, no heavy background.
- **Lead status**: Colored dot + label, `rounded-full` with background from `STATUS_COLOR`
- **Rating**: `bg-amber-500/10 rounded-full px-2 py-0.5` with Star icon

### Empty States
- Use `Empty` compound component from `components/ui/empty.tsx`
- Pattern: `Empty > EmptyHeader > EmptyMedia (icon) > EmptyTitle > EmptyDescription > EmptyContent`

### Forms
- Use `Field` compound component from `components/ui/field.tsx`
- Pattern: `Field > FieldLabel + FormControl + FieldDescription + FieldMessage`
- Validation: integrate with react-hook-form via `Form` component

## 5. Spacing System

| Context | Value |
|---|---|
| Card internal padding | `px-3.5 py-4` |
| Between card sections | `mt-3` to `mt-3.5` |
| Between cards | `my-1.5` |
| Button padding | `px-2.5 py-2` |
| Button gap | `gap-2` |
| Tag container padding | `px-2.5 py-2` |
| Section divider | `border-t border-border/30 my-3` |
| Grid cards (compact) | `p-4` |
| Grid gap | `gap-4` |

## 6. Dark Mode Color Rules

- **Status colors**: Always use 400-level for dark mode (`emerald-400`, `red-400`, `amber-400`) — 600+ is too saturated
- **Backgrounds**: Use token variables (`bg-muted`, `bg-card`, `bg-background`) — never raw hex
- **Borders**: Use `border-border/40` or `border-border/60` for subtlety
- **Hover states**: `hover:bg-muted/40` or `hover:bg-muted/60`
- **Shadows**: `shadow-sm` default, `shadow-md` on hover/selected
- **Disabled**: `opacity-40 pointer-events-none cursor-not-allowed`

## 7. Common Patterns

### Result Card — Full (sidebar / normal mode)
```
┌────────────────────────────────────────────┐
│ Name                            ★ 4.5 (11) │
│ 📍 Address                      ● Abierto  │
│                                            │
│ ┌─ Tags ─────────────────────────────────┐ │
│ │ Tag1 · Tag2 · +N más                  │ │
│ └────────────────────────────────────────┘ │
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│ [ flex-1 ] [ flex-1 ] [ flex-1 ]          │
│ ┌────────────────────────────────────────┐ │
│ │ ● Status                         ▼     │ │
│ └────────────────────────────────────────┘ │
└────────────────────────────────────────────┘
```

### Result Card — Compact (fullscreen grid)
```
┌──────────────────────────┐
│ Name              ★ 4.5  │
│ 📍 Address               │
│ [Tag1] [Tag2] +1         │
│ [Call] [Web] [Directions]│
│ ┌──────────────────────┐ │
│ │ ● Status         ▼   │ │
│ └──────────────────────┘ │
└──────────────────────────┘
```
- `p-4` padding, `text-sm` name, `text-xs` address
- Status dropdown always present (never hide in compact mode)

### Grid Layout (fullscreen discover)
- `grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4`
- 4 columns on ultrawide, responsive down to 1 on mobile
- Each card is a compact ResultCard

### List with Filters
```
┌──────────────────────────────┐
│ Header (title + count)       │
├──────────────────────────────┤
│ Filters row (chips/selects)  │
├──────────────────────────────┤
│ Scrollable list of cards     │
│ [Card] [Card] [Card]         │
│ Load more button (if needed) │
└──────────────────────────────┘
```

## 8. Performance Patterns

### Large Datasets (1000+ items)
- **Map markers**: Use `leaflet.markercluster` for clustering — never render 1000+ individual markers
- **Grid/list**: Use `react-virtuoso` for virtual scrolling — only render visible items
- **State**: Paginate server-side, never hold 100k items in React state
- **Server actions**: Use cursor-based pagination, never `pageSize` truncation

### Package Manager
- **Always use `pnpm`** — never npm or yarn

## 9. i18n

- All user-visible strings via `useTranslations("namespace")`
- Never hardcode Spanish/English strings
- Namespace per module: `businessSearch`, `crm`, etc.

## 10. What NOT to Do

- ❌ `mx-2` or horizontal margins on cards (wastes space)
- ❌ `inline-flex` on containers that should fill width
- ❌ Saturated colors on dark backgrounds (`text-green-600` → use `text-emerald-400`)
- ❌ Heavy backgrounds on status pills (dot + text is enough)
- ❌ Hover-only interactions for expandable content (use click)
- ❌ Hiding action buttons when data is missing (show disabled)
- ❌ Raw hex colors in Tailwind classes
- ❌ `export default` for components
- ❌ Custom interfaces when `React.ComponentProps` works
- ❌ Edge-to-edge content on ultrawide screens (use `max-w-[1100px] mx-auto` wrapper)
- ❌ Hiding status dropdown in compact cards (always show it)
- ❌ Using npm or yarn (always use pnpm)
