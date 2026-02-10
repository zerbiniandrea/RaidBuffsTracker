# Contributing to BuffReminders

## Development Environment Setup

You need three tools to run `make`:

| Tool | Purpose |
|------|---------|
| [luacheck](https://github.com/mpeterv/luacheck) | Linter |
| [StyLua](https://github.com/JohnnyMorganz/StyLua) | Formatter |
| [lua-language-server](https://github.com/LuaLS/lua-language-server) | Type checker |

```bash
make          # Run all three: typecheck, lint, format
make check    # Same but format is check-only (no writes)
```

Run `make` before committing.

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/) with [gitmoji](https://gitmoji.dev/). A body and footer are usually not needed, but add them if the change warrants extra context.

```
type: <gitmoji> short description
```

Pick the commit type (`feat`, `fix`, `refactor`, `perf`, `docs`, `chore`, ...) and pair it with the matching gitmoji from the official list — not a random emoji.

### Examples

```
feat: ✨ add consumable display mode preview to options panel
fix: 🐛 refresh spells and overlays on spec swap and talent changes
refactor: ♻️ decouple sub-icon display from click-to-cast setting
refactor: 🔥 remove tooltips from buff icons and sub-icons
chore: 🔧 add 12.0.1 interface version to TOC
```

## Code Patterns

### Basics

- Lua 5.1 (WoW scripting environment)
- 120 column width, 4-space indentation (enforced by StyLua)
- Use `pcall()` for WoW API calls that can fail

### Shared Namespace

All modules share the `BR` namespace. Each file exports at the end and consumes via local aliases at the top:

```lua
-- Exporting (end of file)
BR.MyModule = { DoThing = DoThing }

-- Consuming (top of a later file)
local DoThing = BR.MyModule.DoThing
```

### Event-Driven Config

Settings go through the Config API, which fires refresh callbacks automatically. Modules subscribe to the events they care about — options and display never call each other directly. This keeps the codebase decoupled: you can change how a setting is applied without touching the UI that sets it, and vice versa.

```lua
-- Options sets a value (triggers the appropriate callback automatically)
BR.Config.Set("categorySettings.main.iconSize", val)

-- Display subscribes to changes
BR.CallbackRegistry:RegisterCallback("VisualsRefresh", UpdateVisuals)
```

### Cache Computed Values

When a value is read frequently (e.g. every frame update or for each group member), cache it in a local and invalidate on the relevant callback rather than re-reading from the DB every time:

```lua
local cachedIconSize
BR.CallbackRegistry:RegisterCallback("VisualsRefresh", function()
    cachedIconSize = BR.Config.Get("categorySettings.main.iconSize", 64)
end)
```

### State / Display Separation

State computes what buffs are missing (pure data, no UI). Display renders frames based on state (no state mutation). State never imports display.

### Declarative UI Components

Components use factory functions with `get`/`enabled`/`onChange` callbacks. When a change affects other components' enabled state, call `Components.RefreshAll()` in `onChange`. Never use imperative `UpdateXxxEnabled()` patterns.

```lua
Components.Slider(parent, {
    label = "Icon Size",
    min = 32, max = 128, step = 1,
    get = function() return BR.Config.Get("categorySettings.main.iconSize", 64) end,
    enabled = function() return someCondition() end,
    onChange = function(val) BR.Config.Set("categorySettings.main.iconSize", val) end,
})
```

### SavedVariables Compatibility

`BuffRemindersDB` persists user settings across sessions. Every change must be backwards-compatible with data that's already out in the wild — a bad migration crashes the addon for real users on login.

**Rules:**
- Never rename or remove a DB key without a migration
- Always add nil-safe fallbacks when reading nested values (`or defaults.x`)
- Set removed fields to `nil` to clean up stale data

**Migrations** run in `ADDON_LOADED`, after `DeepCopyDefault(defaults, BuffRemindersDB)` has filled in any missing keys with their defaults. A migration should check for the old shape, transform it into the new shape, and nil out the old key:

```lua
-- Example: renaming "showCount" → "countDisplay" (string enum)
if type(db.showCount) == "boolean" then
    db.countDisplay = db.showCount and "fraction" or "none"
    db.showCount = nil
end
```

Always check for `nil` before indexing into nested tables — a user's DB may predate the field entirely.
