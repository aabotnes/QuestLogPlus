# Quest Log Plus

A quest log for **World of Warcraft: Forever** (interface 16001). It looks like the default log and adds:

- **Show Map / Hide Map** toggle: the world map opens docked beside the log and jumps to the zone of the quest you open.
- **`+1,250 xp`** on every quest, so you can see whether a quest is worth doing. The tooltip shows what % of a level that is.
- **Completed quests stand out:** green row, green bar, check mark, "Ready to turn in", and who to return to. Zone headers show "N ready", and finished quests sort to the top.
- **Share mode** and **Abandon mode:** tick quests (or a whole zone), then share or abandon them all at once. Abandon asks for confirmation first.
- Quest details page with objectives, rewards and description, plus Track / Share / Abandon buttons. Shift-click a quest in the list to track it.

## Install

Copy the `QuestLogPlus` folder to `World of Warcraft\_forever_\Interface\AddOns\` and `/reload`.

The quest log key (L by default) opens Quest Log Plus. You can also bind a separate key under Key Bindings → AddOns.

## Commands

| Command | Does |
|---|---|
| `/qlp` | Toggle the log |
| `/qlp map` | Map on/off |
| `/qlp key` | Give the quest log key back to the default log |
| `/qlp level` | Show/hide quest levels |
| `/qlp sort` | Completed quests first on/off |
| `/qlp panel` | Close the map's own quest panel on/off |
| `/qlp reset` | Reset window position |
