# Annotated Screenshot

A Redot / Godot 4.x editor plugin that captures the active viewport and appends
a labelled property panel beneath it, producing a single annotated PNG you can
drop straight into bug reports, design documents, or playtesting notes.

---

## Features

- **One-click capture** — a single button in the editor dock saves the screenshot
  to `res://screenshots/annotated_<timestamp>.png`.
- **Three capture modes** — automatically uses whichever editor screen you have
  open: **2D**, **3D**, or **Game** view.
- **Annotation panel** — a multi-column grid of property cards is composited
  directly below the captured image; no external tools needed.
- **Scene-mirroring node tree** — the dock displays every node in the open scene
  in its true hierarchy (nested just like the scene tree). Expand/collapse state
  mirrors the scene editor automatically.
- **Organized property display** — each node's properties are grouped into a
  collapsible **Properties** container (purple header, closed by default) containing:
  - **Class categories** (e.g. *DirectionalLight3D*, *Light3D*, *Node3D*, *Node*)
    ordered the same way as the Inspector (most-derived class first).
  - **Property groups** (e.g. *Light*, *Shadow*, *Transform*) nested inside each
    category.
  - Both categories and groups are tree headers with checkboxes that cascade to
    their children.
- **Smart selection** — tick any combination of individual properties, whole
  groups, whole categories, or entire nodes. Toggling a parent cascades to all
  descendants automatically. Left-click selects/deselects; right-click collapses/expands.
- **Bulk controls** — two toolbar buttons for convenience:
  - **☐ Deselect All / ☑ Select All** — toggle all checkboxes at once.
  - **⊟ Collapse All / ⊞ Expand All** — fold/unfold all nodes at once.
- **Persistent state** — refreshing the node tree preserves both the checked state
  and collapse state of every item. Smart fold-state handling: if you collapsed a
  node in the **scene tree** since the last dock refresh, the dock will follow that
  change; otherwise, any customizations you made by right-clicking in the dock
  (without scene-tree changes) are preserved. New/removed nodes adapt automatically.
- **Resource sub-properties** — properties whose value is a `Resource`
  (e.g. a `WorldEnvironment`'s *Environment* resource) expand into their own
  nested property tree, letting you annotate resource fields without leaving the
  dock.
- **Smart formatting**
  - Enum properties show the option *name* instead of a raw integer.
  - Flag properties show a comma-separated list of active flag names.
  - Property names are converted from `snake_case` to *Title Case*, and the
    group prefix is stripped (e.g. `light_color` in group *Light* displays as
    *Color*).
- **Optional .txt export** — tick *Also export .txt file* to save a plain-text
  companion file alongside the PNG, useful for diffing or searching.
- **Redot-themed UI** — Properties container is purple; category headers are
  orange and group headers red, matching the Redot engine Inspector colour scheme.

---

## Installation

### From the Asset Library
1. Open the Redot / Godot editor and go to **AssetLib**.
2. Search for **Annotated Screenshot** and click **Download**.
3. Accept the default install path and click **Install**.
4. Open **Project → Project Settings → Plugins** and enable
   *Annotated Screenshot*.

### Manual / from source
1. Copy the `addons/annotated_screenshot/` folder into your project's
   `addons/` directory.
2. Open **Project → Project Settings → Plugins** and enable
   *Annotated Screenshot*.

---

## Usage

1. Open a scene.
2. Find the **AnnotatedScreenshot** dock (right panel by default).
3. Click **↺ Refresh Nodes** if the scene tree is not yet populated.
4. Browse the scene tree (matches the scene editor's hierarchy and expand/collapse state).
5. Expand a node and its **Properties** container to reveal categories and groups.
   - **Left-click** on a checkbox to select/deselect. Selecting a parent cascades to all children.
   - **Right-click** on a node/category/group to collapse/expand it (toggle without changing selection state).
6. Use the toolbar buttons for bulk operations:
   - **☐ Deselect All** (or **☑ Select All**) — toggle all checkboxes.
   - **⊟ Collapse All** (or **⊞ Expand All**) — fold/unfold all items.
7. Optionally tick **Also export .txt file**.
8. Click **📷 Take Screenshot**.

The saved file path is shown in the status label at the bottom of the dock.
Screenshots are written to `<project>/screenshots/`. Your selection and folder state are preserved across refreshes.

---

## Compatibility

| Engine | Version |
|--------|---------|
| Redot  | 4.3 +   |
| Godot  | 4.3 +   |

GDScript only — no compiled extensions required.

---

## Project structure

```
addons/
└── annotated_screenshot/
    ├── plugin.cfg       # Plugin metadata
    ├── ann_scr.gd       # EditorPlugin entry point
    ├── dock.gd          # Editor dock UI (Tree + controls)
    └── annotator.gd     # Viewport capture & panel rendering
```

---

## License

MIT
