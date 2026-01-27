# BuffReminders

[![](https://shields.io/badge/discord-5865F2?logo=discord&style=for-the-badge&logoColor=white)](https://discord.com/users/285458497020362762) [![](https://shields.io/badge/github-gray?logo=github&style=for-the-badge&logoColor=white)](https://github.com/zerbiniandrea/BuffReminders)

A lightweight World of Warcraft addon that tracks missing buffs with a clean icon display.

From the author of [Raid Buffs Tracker](https://wago.io/iWkZ4Eq-i), one of the most popular raid buffs tracking WeakAuras.

![BuffDisplay](https://github.com/zerbiniandrea/BuffReminders/blob/main/images/buffs.png?raw=true)

## Features

*   Visual buff tracking - Shows buff icons with count overlay (e.g., "17/20" = 17 buffed out of 20)
*   Auto-hide - Icons disappear when everyone has the buff
*   Draggable frame - Position anywhere on screen, with configurable grow direction
*   Split categories - Optionally separate buff categories into independent, movable frames
*   Class reminder - Shows "BUFF!" under your class's buff icon when party members are missing it
*   Expiration warning - Glow effect when buffs are about to expire, with 5 styles to choose from
*   Smart filtering - Show only in group, hide buffs without provider, show only your class buff, count only benefiting classes
*   Customizable - Adjust icon size, spacing, and text size

![Split Categories](https://github.com/zerbiniandrea/BuffReminders/blob/main/images/buffs-split-groups.png?raw=true)

## Configuration

To open the options panel, type `/br`

### Buff Selection

Choose which buffs to track. Buffs are organized by type: raid-wide buffs, presence buffs (at least one person needs it), personal buffs (buffs you cast on others), and self buffs.

![BuffReminders Settings - Buffs](https://github.com/zerbiniandrea/BuffReminders/blob/main/images/settings-buffs.png?raw=true)

### Options

Configure when and how the addon displays. Control visibility (group only, instance only, ready check only), adjust icon size and spacing, set expiration warning thresholds, and choose from 5 glow styles.

![BuffReminders Settings - Options](https://github.com/zerbiniandrea/BuffReminders/blob/main/images/settings-options.png?raw=true)

![Glow Styles](https://github.com/zerbiniandrea/BuffReminders/blob/main/images/glows.png?raw=true)

### Custom Buffs

Track any buff by spell ID. Useful for consumables, world buffs, or any buff not included by default. Custom buffs check if you have the buff on yourself.

![BuffReminders Settings - Custom Buffs](https://github.com/zerbiniandrea/BuffReminders/blob/main/images/settings-custombuffs.png?raw=true)

## Limitations

*   **Combat lockout** - Due to WoW API restrictions, buff tracking only updates out of combat.
*   **Mythic+ disabled** - Blizzard restricts aura/buff API access during active Mythic+ keystones (all buff data is marked as "secret"). The addon automatically hides in M+ and works normally in regular dungeons, raids, and open world.
*   **No spec-level filtering** - The addon will not constantly inspect each player's spec, as this would be too resource-intensive. This means it can't exclude buffs that don't benefit certain specs, like Intellect for Feral Druids.

## Support

If you encounter issues or have suggestions, feel free to reach out on [Discord](https://discord.com/users/285458497020362762) or open an issue on [GitHub](https://github.com/zerbiniandrea/BuffReminders/issues).
