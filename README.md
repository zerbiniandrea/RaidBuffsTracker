<h1 align="center">BuffReminders</h1>
<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/logo.png?raw=true" width="180" />
</p>
<p align="center">
  <a href="https://github.com/zerbiniandrea/BuffReminders"><img src="https://shields.io/badge/github-gray?logo=github&style=for-the-badge&logoColor=white" /></a>
  <a href="https://discord.gg/qezQ2hXJJ7"><img src="https://shields.io/badge/discord-5865F2?logo=discord&style=for-the-badge&logoColor=white" /></a>
</p>
<p align="center">A lightweight World of Warcraft addon that tracks missing buffs with a clean icon display.</p>
<p align="center">From the author of <a href="https://wago.io/iWkZ4Eq-i">Raid Buffs Tracker</a>, one of the most popular raid buffs tracking WeakAuras.</p>

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/buffs.png?raw=true" />
</p>

## Features

- **Click to cast** - Click missing buff icons to cast the spell directly (out of combat, spells your character can cast)
- **M+ support** - Detects missing buffs via action bar glow even when Blizzard's buff API is restricted
- Class reminder when your buff is missing
- Visual buff tracking with count overlay (e.g., "17/20" = 17 buffed out of 20)
- Split into movable category frames
- Expiration glow warnings (5 styles)
- Custom buff tracking by spell ID (with in-combat glow detection)
- Highly configurable (filtering, sizing, visibility)

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

## Limitations

- **Combat/M+/PvP** - Blizzard restricts buff API access during combat, M+ keystones, and instanced PvP. Full group tracking is only available out of combat. In M+, the addon automatically detects when your own raid buff is missing by monitoring action bar spell glows (requires the spell to be on your action bars).
- **Buff counting restrictions** - Both buff counts and buff providers (who can cast buffs) are tracked only for group members who are alive, connected, visible (not phased), and allied. This means:
  - Dead, offline, or phased players are excluded from totals
  - Raid buff providers (e.g., mages for Arcane Intellect) are only detected if they meet these conditions
  - In open world, opposing faction players are not counted (works normally in dungeons and raids where all group members are allied)
- **No spec-level filtering** - The addon will not constantly inspect each player's spec, as this would be too resource-intensive. This means it can't exclude buffs that don't benefit certain specs, like Intellect for Feral Druids.

## Support

Got a bug to report, a feature idea, or just want to see what's coming next? Join the [Discord](https://discord.gg/qezQ2hXJJ7)!

## Credits

Huge thanks to [Time Spiral Tracker](https://www.curseforge.com/wow/addons/time-spiral-tracker) for the idea of using action bar spell glows to detect missing buffs.

Huge thanks to [plusmouse](https://plusmouse.com/) (author of [Platynator](https://www.curseforge.com/wow/addons/platynator), [Auctionator](https://www.curseforge.com/wow/addons/auctionator), and more) for the clean, well-organized code that helped me learn WoW addon development patterns.
