# [Soeta's] Quest Log Plus

A quest log for **World of Warcraft: Forever** (interface 16001). It looks like the default log and adds:

- **`+1,250 xp`** on every quest (setting, off by default), so you can see whether a quest is worth doing. The tooltip shows what % of a level that is.
- **Tracked quests** can get a thin blue border on the right edge of the row (setting) (shift-click a quest to track or untrack it).
- **Completed quests stand out:** the yellow turn-in "?" and a green title, plus an optional green border, "Ready to turn in", and who to return to. Zone headers show "N ready", and finished quests sort to the top.
- **Rewards like the default log:** item buttons with icon, name and quality color. Hover one for the full item tooltip (stats, compare), shift-click to link it, ctrl-click to preview it.
- **Reward icons in the list** (on by default): small icons under each quest, with "Choose one:" / "You will receive:" above them.
- **Search and filters:** the search box matches quest names, objectives and zones. The Filter button can show only quests with quest items (a usable quest item, or at least one item collected for an objective), quests ready to turn in, or tracked quests. Active filters turn the button green ("Filter (1)") and show as chips under the search box; click a chip to remove it. Filters are remembered; the search is not.
- **Share mode** and **Abandon mode:** tick quests, or tick a whole zone with its "select all" box (clicking the zone name works too), then share or abandon them all at once. Zones can still be expanded and collapsed with the +/− button. Abandon asks for confirmation first.
- **Map toggle:** the world map is attached to the log's right side, scaled to the log's height, like one window. Drag the log or the map's title bar to move them together; resize the log and the map follows. Map opacity is in settings. The map's **Off** button (next to its close button) turns the map off; the close button only closes it this time.
- **Details panel** (on by default): quest details open in a separate panel on the log's right side, between the log and the map. Click the open quest again, or the panel's close button, to hide it; the panel's **Off** button turns the panel off so details open inside the log.
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
| `/qlp items` | Filter: has quest items on/off |
| `/qlp level` | Show quest levels on/off |
| `/qlp sort` | Completed quests first on/off |
| `/qlp windows` | Move aside for game windows on/off |
| `/qlp panel` | Close the map's own quest list on/off |
| `/qlp key` | Quest log key opens Quest Log Plus on/off |
| `/qlp reset` | Reset log, panel and map position/size |

## Leatrix Maps

If Leatrix Maps has "Enable movement" on, it puts the map back at its own saved spot whenever the map refreshes. Quest Log Plus docks it back to the log right after, but you may see the map flicker. Quest Log Plus lines up Leatrix Maps' visible border (title bar, map and coordinates bar) with the log, and dragging the map moves the log with it.
