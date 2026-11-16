SqualoAI - a competitive AI for OpenTTD
=======================================
Author:  DrKontos
Version: 15
License: GNU GPL v2 (see license.txt)
Requires: OpenTTD 15.0 or newer
Libraries: Pathfinder.Road 4, Pathfinder.Rail 1 (downloaded automatically from the
           in-game online content when you install the AI from there)


WHAT IT DOES
------------
SqualoAI ("Shark AI") tries to make as much money as possible and uses every legal
tool the game gives it against its competitors.

- Buses between towns: picks large towns 20-110 tiles apart, builds the road (reusing
  existing roads when possible), drive-through stops in the town centres, a depot and
  buses. Stops grow up to 3 tiles in a row when buses queue.
- Trucks: freight from industry to industry (coal, wood, ore, ...) and goods, food and
  water from industries to towns that accept them. Full load at pick-up.
- Aircraft: passengers between large towns 100-450 tiles apart, using the best airport
  available in the current year. Airports are reused by several routes. No big planes on
  small airports.
- Freight trains: simple terminus-to-terminus single-track lines with ONE train per line
  (no signals, so no crashes). Started only after the road network is running.
- Fleet management: adds vehicles where cargo or passengers pile up, never adds vehicles
  to routes that lost money last year, removes vehicles from loss-making routes, sells
  old loss-making vehicles, closes routes when an industry closes, rebuilds broken roads
  when a vehicle reports it is lost.
- Local authorities (all optional): plants trees and builds statues to raise its rating,
  runs advertising campaigns, buys exclusive transport rights where competitors operate,
  funds new buildings, and bribes the local authority when its rating is too low.
- Money: borrows only to build, repays the loan when it has spare cash.
- Mergers: after 5 years in the game it accepts the offers to buy bankrupt competitors,
  paying only with spare cash. (OpenTTD does not let AIs start a hostile takeover.)
  Acquired vehicles keep running with their own orders but are not managed by the AI.


SETTINGS
--------
All settings can also be changed during a game.

Maximum number of bus lines / truck routes / air routes / rail lines
    Use these as a difficulty setting. Aircraft are by far the most profitable part:
    lowering "Maximum number of air routes" (or disabling aircraft) makes the AI much
    easier to beat.
Use trucks / aircraft / freight trains
    Enable or disable each transport type.
Buy bankrupt competitors
    Accept merger offers for companies going bankrupt (after 5 years, cash only).
Build statues / advertising / exclusive rights / fund buildings / bribe
    Enable or disable each local authority action. Disable exclusive rights and bribing
    for a fairer opponent.
Log level
    0 = errors only, 1 = normal, 2 = detailed. Log messages are in Italian.
    Every January the AI writes a short yearly report (money, best and loss-making routes,
    statues and exclusive rights) in the AI debug window.


KNOWN LIMITATIONS
-----------------
- Trains: one train per line, no signals, no double track. Rail lines cross roads with
  level crossings, where trains can destroy road vehicles (including its own).
- No ships.
- Bus and truck lines are never closed, only reduced to 2 vehicles when losing money.
- Log messages are in Italian.


FEEDBACK
--------
Bug reports: https://github.com/drkontos/SqualoAI/issues
Please include your OpenTTD version and a screenshot of the AI debug window
(red error messages and the yearly report). Source code: https://github.com/drkontos/SqualoAI
