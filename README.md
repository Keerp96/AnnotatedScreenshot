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
- **Collapsible node tree** — the dock lists every node in the open scene.
  Each node expands into its **class categories** (e.g. *DirectionalLight3D*,
  *Light3D*, *Node3D*, *Node*) ordered the same way as the Inspector
  (most-derived class first), with **property groups** nested inside each
  category.
- **Granular selection** — tick any combination of individual properties, whole
  groups, whole categories, or entire nodes. Toggling a parent cascades to all
  its children automatically.
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
- **Redot-themed UI** — category headers are tinted orange and group headers
  red, matching the Redot engine Inspector colour scheme.

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
4. Expand nodes → categories → groups to browse properties.
   Check or uncheck any item; toggling a parent cascades to its children.
5. Optionally tick **Also export .txt file**.
6. Click **📷 Take Screenshot**.

The saved file path is shown in the status label at the bottom of the dock.
Screenshots are written to `<project>/screenshots/`.

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

MIT — see [LICENSE](LICENSE) for details.
