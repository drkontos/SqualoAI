# SqualoAI

A competitive AI for [OpenTTD](https://www.openttd.org) 15.0 or newer.

SqualoAI ("Shark AI") tries to make as much money as possible and uses every legal tool
the game offers against its competitors.

## Install

In OpenTTD open **Online Content**, search for **SqualoAI** and download it.
The required libraries (Pathfinder.Road 4, Pathfinder.Rail 1) are downloaded automatically.

## What it does

- **Buses** between towns, with drive-through stops that grow when buses queue
- **Trucks** from industry to industry, and goods/food/water to towns
- **Aircraft** between large, distant towns (its main source of money)
- **Freight trains**: simple single-track lines with one train each
- **Local authorities**: trees, statues, advertising, exclusive rights, building funding
  and bribes (each one can be disabled)
- **Mergers**: buys bankrupt competitors when offered, after 5 years and with spare cash only
- **Yearly report** in the AI debug window every January

The "Maximum number of ... routes" settings work as a difficulty level: lower the air
routes (or disable aircraft) for an easier opponent.

## Reporting bugs

Please open an [issue](../../issues) and include:

1. your OpenTTD version;
2. a screenshot of the **AI debug window** (Help menu → AI/Game Script debug, select
   SqualoAI's company) showing the red error and the lines just before it;
3. if possible, the last yearly report (the block starting with `##### RAPPORTO`);
4. if possible, a savegame from just before the problem.

Log messages are in Italian: that's fine, just send the screenshot.

## License

GNU General Public License v2. The `.nut` files are the complete source code.
