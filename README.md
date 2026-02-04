<h1 align="center">BuffReminders</h1>
<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/logo.png?raw=true" width="180" />
</p>
<p align="center">
  <a href="https://github.com/zerbiniandrea/BuffReminders"><img src="https://shields.io/badge/github-gray?logo=github&style=for-the-badge&logoColor=white" /></a>
  <a href="https://discord.gg/qGHQr2DP7F"><img src="https://shields.io/badge/discord-5865F2?logo=discord&style=for-the-badge&logoColor=white" /></a>
</p>
<p align="center">A lightweight World of Warcraft addon that tracks missing buffs with a clean icon display.</p>
<p align="center">From the author of <a href="https://wago.io/iWkZ4Eq-i">Raid Buffs Tracker</a>, one of the most popular raid buffs tracking WeakAuras.</p>

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/buffs.png?raw=true" />
</p>

## Features

- Visual buff tracking - Shows buff icons with count overlay (e.g., "17/20" = 17 buffed out of 20)
- Auto-hide - Icons disappear when everyone has the buff
- Draggable frame - Position anywhere on screen, with configurable grow direction
- Split categories - Optionally separate buff categories into independent, movable frames
- Class reminder - Shows "BUFF!" under your class's buff icon when party members are missing it
- Expiration warning - Glow effect when buffs are about to expire, with 5 styles to choose from
- Smart filtering - Show only in group, hide buffs without provider, show only your class buff, count only benefiting classes
- Customizable - Adjust icon size, spacing, and text size

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/buffs-split-groups.png?raw=true" />
</p>

## Configuration

To open the options panel, type `/br`

### Buff Selection

Choose which buffs to track. Buffs are organized by type: raid-wide buffs, presence buffs (at least one person needs it), targeted buffs (buffs you cast on others), and self buffs.

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/settings-buffs.png?raw=true" />
</p>

### Options

Configure when and how the addon displays. Control visibility (group only, instance only, ready check only), adjust icon size and spacing, set expiration warning thresholds, and choose from 5 glow styles.

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/settings-options.png?raw=true" />
</p>

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/glows.png?raw=true" />
</p>

### Custom Buffs

Track any buff by spell ID. Useful for consumables, world buffs, or any buff not included by default. Custom buffs check if you have the buff on yourself.

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/settings-custombuffs.png?raw=true" />
</p>

## Limitations

- **Combat lockout** - Due to WoW API restrictions, buff tracking only updates out of combat.
- **Mythic+ disabled** - Blizzard restricts aura/buff API access during active Mythic+ keystones (all buff data is marked as "secret"). The addon automatically hides in M+ and works normally in regular dungeons, raids, and open world.
- **PvP disabled** - Similar API restrictions apply in arenas and battlegrounds. The addon automatically hides in instanced PvP content.
- **Buff counting restrictions** - Both buff counts and buff providers (who can cast buffs) are tracked only for group members who are alive, connected, visible (not phased), and allied. This means:
  - Dead, offline, or phased players are excluded from totals
  - Raid buff providers (e.g., mages for Arcane Intellect) are only detected if they meet these conditions
  - In open world, opposing faction players are not counted (works normally in dungeons and raids where all group members are allied)
- **No spec-level filtering** - The addon will not constantly inspect each player's spec, as this would be too resource-intensive. This means it can't exclude buffs that don't benefit certain specs, like Intellect for Feral Druids.

## Support

If you encounter issues or have suggestions, feel free to reach out on Discord (.zerby) or open an issue on [GitHub](https://github.com/zerbiniandrea/BuffReminders/issues).
