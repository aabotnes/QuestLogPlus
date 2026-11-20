# Quest Log Plus

A quest log for **World of Warcraft: Forever** (interface 16001). It looks like the default log and adds:

- **`+1,250 xp`** on every quest, so you can see whether a quest is worth doing. The tooltip shows what % of a level that is.
- **Completed quests stand out:** green row, green bar, check mark, "Ready to turn in", and who to return to. Zone headers show "N ready", and finished quests sort to the top.
- **Rewards like the default log:** item buttons with icon, name and quality color. Hover one for the full item tooltip (stats, compare), shift-click to link it, ctrl-click to preview it.
- **Reward icons in the list** (on by default): small icons under each quest, with "Choose one:" / "You will receive:" above them.
- **Has quest items filter** (off by default): only show quests you hold quest items for (a usable quest item, or at least one item collected for an objective).
- **Share mode** and **Abandon mode:** tick quests, or tick a whole zone with its "select all" box (clicking the zone name works too), then share or abandon them all at once. Zones can still be expanded and collapsed with the +/− button. Abandon asks for confirmation first.
- **Map toggle:** the world map is attached to the log's right side, scaled to the log's height, like one window. Drag the log or the map's title bar to move them together; resize the log and the map follows.
- **Details panel** (on by default): quest details open in a separate panel on the log's right side, between the log and the map.
- **Moves aside for game windows:** when the character sheet, spellbook, a vendor and so on would cover the log, it moves to their right and comes back when they close.
- The log can be moved (drag it) and resized (bottom-right corner). Everything is remembered between sessions.

## Install

Copy the `QuestLogPlus` folder to `World of Warcraft\_forever_\Interface\AddOns\` and `/reload`.

The quest log key (L by default) opens Quest Log Plus. You can also bind a separate key under Key Bindings → AddOns.

## Settings

Click the gear in the log's top bar, type `/qlp config`, or open Options → AddOns → Quest Log Plus.

| Command | Does |
|---|---|
| `/qlp` | Toggle the log |
| `/qlp config` | Settings window |
| `/qlp map` | Map next to the log on/off |
| `/qlp popout` | Details in a separate panel on/off |
| `/qlp rewards` | Reward icons in the list on/off |
| `/qlp items` | Only quests with quest items on/off |
| `/qlp level` | Show quest levels on/off |
| `/qlp sort` | Completed quests first on/off |
| `/qlp windows` | Move aside for game windows on/off |
| `/qlp panel` | Close the map's own quest list on/off |
| `/qlp key` | Quest log key opens Quest Log Plus on/off |
| `/qlp reset` | Reset log, panel and map position/size |

## Leatrix Maps

If Leatrix Maps has "Enable movement" on, it puts the map back at its own saved spot whenever the map refreshes. Quest Log Plus docks it back to the log right after, but you may see the map flicker. Turning off Leatrix Maps' map movement avoids that.
