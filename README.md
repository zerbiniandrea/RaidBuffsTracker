<h1 align="center">BuffReminders</h1>
<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/logo.png?raw=true" width="180" />
</p>
<p align="center">
  <a href="https://discord.com/users/285458497020362762"><img src="https://shields.io/badge/discord-5865F2?logo=discord&style=for-the-badge&logoColor=white" /></a>
  <a href="https://github.com/zerbiniandrea/BuffReminders"><img src="https://shields.io/badge/github-gray?logo=github&style=for-the-badge&logoColor=white" /></a>
</p>
<p align="center">A lightweight World of Warcraft addon that tracks missing raid buffs with a clean icon display.</p>
<p align="center">From the author of <a href="https://wago.io/iWkZ4Eq-i">Raid Buffs Tracker</a>, one of the most popular raid buffs tracking WeakAuras.</p>

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/buffs.png?raw=true" />
</p>

## Features

- Visual buff tracking - Shows buff icons with count overlay (e.g., "17/20" = 17 buffed out of 20)
- Auto-hide - Icons disappear when everyone has the buff
- Draggable frame - Position anywhere on screen, with configurable grow direction
- Class reminder - Shows "BUFF!" under your class's buff icon when party members are missing it
- Expiration warning - Glow effect when buffs are about to expire, with 5 styles to choose from
- Smart filtering - Show only in group, hide buffs without provider, show only your class buff
- Class benefit filtering - Only show buffs that benefit your class (BETA)
- Customizable - Adjust icon size, spacing, and text size

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/glows.png?raw=true" />
</p>

## Configuration

To open the options panel, type `/br`

<p align="center">
  <img src="https://github.com/zerbiniandrea/BuffReminders/blob/main/images/settings.png?raw=true" />
</p>

## Limitations

- **Combat lockout** - Due to WoW API restrictions, buff tracking only updates out of combat.
- **Mythic+ disabled** - Blizzard restricts aura/buff API access during active Mythic+ keystones (all buff data is marked as "secret"). The addon automatically hides in M+ and works normally in regular dungeons, raids, and open world.
- **No spec-level filtering** - The addon will not constantly inspect each player's spec, as this would be too resource-intensive. This means it can't exclude buffs that don't benefit certain specs, like Intellect for Feral Druids.

## Support

If you encounter issues or have suggestions, feel free to reach out on [Discord](https://discord.com/users/285458497020362762) or open an issue on [GitHub](https://github.com/zerbiniandrea/BuffReminders/issues).
