# Godot designs owned by the user

Read `docs/GODOT_BAUEN.md` before changing layout loading, ships, stations, or editor tools.

- `designs/ships/*.tscn` and `designs/places/*.tscn` are the user's editable source layouts. Runtime code loads them through `DesignLoader`. Always build on their current contents.
- Before editing, inspect `git status` and the diff. Preserve the user's uncommitted edits, scene changes, component settings, and saved layouts. Never reset, regenerate, delete, or replace authored designs merely to match procedural defaults or pass tests.
- Changes in Godot become project files when saved. If Godot is open, account for unsaved work before touching a design. Prefer code changes in `scripts/` and `addons/` for programming tasks.
- Code changes must continue loading authored terrain, cables, devices, inventories, and station room definitions. Retain compatibility with existing game saves. Loading a game save must preserve that saved world.
- If a schema migration is required, make it lossless, retain a backup, and validate every existing design. Ask before intentionally removing the user's content.
- Newly introduced ships and places need a usable Godot design and a runtime loading path. Keep the editor catalog current.
- Run `test_designs` and relevant gameplay tests after changing the design loader. Do not rewrite fixtures to hide failures.
- Share design files and code together through version control. Do not auto-push or discard local changes. Report outstanding local changes honestly.
