# Quest Log Plus

## v1.4.8

- The marker settings are now **Completed quest border** and **Tracked quest border** and only show or hide the borders. The yellow turn-in ? and the green title on finished quests always show.

## v1.4.7

- **New settings:** *Completed quest marker* (green bar, yellow ? and green title) and *Tracked quest marker* (thin bar on the right), each on its own, both on by default.
- **Settings are grouped:** Quest list, Tooltips, Details & map, and Window & keys, in two columns, with *Check / uncheck all* at the top.

## v1.4.6

- **More compact reward row:** the icons and the gold now follow their label on the same line ("Choose one: [icons]  You will also receive: [icon] 1 [gold]"). Both parts share one line when they fit and wrap onto the next line when they don't.

## v1.4.5

- **Fixed:** gold rewards showed as a plain copper number (like "4000"). They now show as gold, silver and copper amounts with the coin icons ("40" with a silver coin). The details panel shows gold again too; it was missing there.

## v1.4.4

- **Gold rewards in the list:** the reward icon row now shows the gold a quest gives, with coin icons, after the item icons. Quests that only give gold show it too.
- **Check / uncheck all** at the top of the settings turns every setting on or off at once. *Quest log key opens Quest Log Plus* is left as it is, so L keeps working.

## v1.4.3

- **Fixed:** after a flight path the quest log key could open the default quest log again. Quest Log Plus now checks that the key really opens it (on binding updates, after landing, on loading screens, and every few seconds) and binds it again if the game reset it. The key binding is now a priority binding.

## v1.4.2

- **Compact list:** rows are only as tall as what they show. With XP, status text, objective progress and reward icons off, every quest is a single line.
- **New setting: Show XP rewards** (on by default). With it off, a timed quest's countdown takes the XP spot.
- **New setting: Status text** ("Ready to turn in" / "Failed", on by default). The icons and coloured bars stay either way.
- **New setting: Select the quest on the map** (on by default). With the map shown, picking a quest in the log selects it on the map, the quest the map highlights and the quest arrow points to.

## v1.4.1

- **Timed quests** show their time left under the +XP text, counting down, and red in the last minute. The tooltip shows it too.
- **M opens the map attached to the log** while the log is open, even with Show Map off. Hide Map (or closing the map) puts it back to normal; the Show Map setting stays as it was.
- **Failed quests** are the red mirror of completed ones: red bar on the left, red ✕, *Failed* with a hint to abandon and retake it, and they sort to the bottom of their zone.

## v1.4.0

First public release.

- **New addon icon** in the style of the other [Soeta's] addons: an open quest book with the yellow turn-in "?" on a starry night sky with a gold rim. The CurseForge logo (`Media/Logo.png`) matches.
- The addon now ships with its license (MIT) and this changelog.

## v1.3.6

- The map's own quest list no longer shows up next to the attached map on the first open after a reload.

## v1.3.5

- **New settings:** *Objective text in quest tooltips* and *Objective progress in the quest list*, both on by default.

## v1.3.4

- The quest tooltip shows the quest's objective text under *Quest Objectives*, above the progress lines, and the turn-in hint for quests that are ready.

## v1.3.3

- With the full-size map setting, the map now attaches to the log on the first open after a reload too, instead of opening full-size and opaque.

## v1.3.2

- The map opacity setting is kept while you move (the game's map fader no longer sets it back to full).

## v1.3.1

- Fixed the addon not loading at all in v1.3.0.
- Quest Log Plus now carries the **[Soeta's]** tag in the AddOns list, the settings window and chat.

## v1.3.0

- **Search box** for quest names, objectives and zones.
- **Filter button:** Has quest items, Ready to turn in and Tracked. Active filters turn the button green and show as chips you can click away.
- **Off buttons** next to the details panel's and the map's close buttons; clicking the open quest again hides the details panel.
- **Map opacity** slider in settings.

## v1.2.x

- The map is attached to the log's right side, scaled to the log's height, and moves with it.
- Tracked quests get a thin bar on the right edge of their row.
- Completed quests show the yellow turn-in "?" and a green bar on the left.

## v1.1.0

- Rewards shown like the default quest log, with item tooltips.
- Optional reward icons in the quest list.
- Resizable log, a separate details panel, a settings window, and the log moves aside for game windows.
- Share / Abandon mode: zone "select all" boxes, and zones still collapse.

## v1.0.0

- Quest log with a map toggle, `+XP` on every quest, clear "ready to turn in" marking, and batch share / abandon modes.
