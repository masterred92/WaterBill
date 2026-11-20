# Water Bill

Should your conjured water and food go on the auction house, or down your throat? A Frost Suite box for **WoW: Forever**
(Interface 16001). Version 1.0.0. Part of Kenny's Frost Suite, and it works alone.

It shows up when you open the **auction house** or a **mailbox**, or when you type `/frost water`, and never in combat.
One line per item in your bags:

| Line | Means |
| --- | --- |
| `LIST Conjured Crystal Water x35: ~14s before AH cut, deposit 10s 50c for a 2 h post` | after the AH cut (assumed: 5% faction, 15% neutral), your last price scan says it's worth more than the deposit |
| `DRINK` / `EAT` + why | bound, the auction house won't take it, or it isn't worth the deposit |
| `deposit unknown` | the game hasn't given a deposit (it only does at the open auction house), so there's no LIST verdict |
| `no price scan` | PriceLog has no price for it yet; there's no guess |
| `vendor price 2s` | the item sells to a vendor (Mote of Unstable Magic does), so there's no LIST / DRINK verdict |

How it decides:

- **LIST / DRINK only when the vendor price is 0.** All conjured water and food have a vendor price of 0 in the game's data.
- **Whether the AH takes it** is asked live from the game for the real bag slot (`C_AuctionHouse.IsSellItemValid`). Bound = DRINK.
- **Prices** come from your own **PriceLog** scans through the shared Kenny hub, the same way GoldPerSpot reads them. Every
  price is labelled **before AH cut**. The LIST decision takes the auction house cut off first: price × count × (1 − cut)
  must beat the deposit. **The cut rates are assumptions from player sources, not game data**: the game has no API or UI
  text for the rate. Water Bill uses 5% at a faction house and 15% at the neutral (goblin) house in Booty Bay, Gadgetzan
  or Everlook, the same rates as NeutralFlip and Forever guides. The house comes from your map, using map IDs confirmed in
  the game's data (build 70862): Stranglethorn Vale, Tanaris and Winterspring are neutral, and the other zones and cities are
  faction. Zone names are only used on an English client. Anything else, for example a map Water Bill doesn't know on a
  non-English client, gets the worse 15% and the box says `house unknown: 15% cut assumed`.
- **The deposit** is read live from the game while the auction house is open, for the duration you picked in Blizzard's sell
  frame when that's readable. Otherwise it uses the first option, which is **2 hours** on Forever (the choices are 2 / 8 / 24 h).
  Each line says which, e.g. `for a 2 h post`. Without a deposit from the game the line says `deposit unknown` and gives no
  LIST verdict. The deposit is never hard-coded.
- Item tooltips get a small `Water Bill: ~40c each before AH cut` line.

It never lists, sells, casts or moves anything; you do the listing.

Items: Conjured Water through Conjured Crystal Water, Mountain Spring Water (231778), Conjured Muffin through Conjured
Cinnamon Roll, and Mote of Unstable Magic. The IDs come from the game's Item tables, build
1.60.1.70862.

## Commands

The Frost Suite has no per-addon slash commands, only `/frost <sub>`. That keeps the risk of clashing with other addons low.

- `/frost water`: show or hide the box (out of combat)
- `/frost water debug`: every stack with its vendor price, bound flag, AH answer, price, deposit and verdict
- `/frost lock | unlock | scale 0.8-1.4 | reset | debug`: the shared dock

## Checks

`tests/run.sh <wow-ui-source>`, `tools/check_suite_lib.sh <frost-suite-lib folder>`, `tools/verify_media.sh`.

MIT licence. Uses the game's own textures only.
