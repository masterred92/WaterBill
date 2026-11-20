# Changelog

## 1.0.0 (Nov 20, 2026)

First release, part of the Frost Suite.

- LIST / DRINK / EAT for conjured water and food in your bags, only for items whose vendor price is 0.
- Live auction-house check (`IsSellItemValid`), PriceLog prices through the Kenny hub ("before AH cut").
- Live deposit at the AH for your picked duration (or 2 h, labelled "for a N h post"); no deposit = "deposit unknown", no LIST.
- LIST only when price × count after the AH cut beats the deposit. The cut is assumed from player sources, not game data:
  5% at a faction house, 15% at the neutral (goblin) house, 15% when the house can't be told apart (said in the box).
  LIST in CoinGold.
- Shown at the auction house, mailbox or `/frost water`; never in combat. Item tooltip line. `/frost water debug`.
