# Changelog

## 1.0.1 (Nov 20, 2026)

- Layout fixes (FrostSuite-1.0 r4, shared by the suite): a status too long to sit beside the title moves to its own line instead of running into it, and box heights fit their text.
- One short line per item: verdict first, then the item, count and figures. A long item name is shortened with `…` so the price and deposit stay visible, e.g. `LIST Crystal Water x40 ~32s 0c · 10s50c/2h`.
- `DEPOSIT?` and `ASK` verdict words when the game gives no deposit or can't say whether the auction house takes the item.
- Shorter auction-house status, e.g. `AH · faction 5% assumed`.
- Works at any level and for any class (it reads items, not spells). Very large figures (huge gold or counts) are cut with `…` instead of running past the box.

## 1.0.0 (Nov 20, 2026)

First release, part of the Frost Suite.

- LIST / DRINK / EAT for conjured water and food in your bags, only for items whose vendor price is 0.
- Live auction-house check (`IsSellItemValid`), PriceLog prices through the Kenny hub ("before AH cut").
- Live deposit at the AH for your picked duration (or 2 h, labelled "for a N h post"); no deposit = "deposit unknown", no LIST.
- LIST only when price × count after the AH cut beats the deposit. The cut is assumed from player sources, not game data:
  5% at a faction house, 15% at the neutral (goblin) house, 15% when the house can't be told apart (said in the box). The house comes from map IDs confirmed in
  UiMap 70862, with zone names used only on English clients.
  LIST in CoinGold.
- Shown at the auction house, mailbox or `/frost water`; never in combat. Item tooltip line. `/frost water debug`.
