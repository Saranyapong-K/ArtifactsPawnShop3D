# Artifacts Pawn Shop

A cozy autumn pawn shop game made with Godot 4.7.2, using the Compatibility renderer. Trading is the main activity; cleaning is the second core activity.

[Play in your browser](https://artifacts-pawn-shop-playtest-syrins.heartyokapi128.chatgpt.site/). Use a current desktop browser and click inside the game to enable sound and mouse capture. Loading prepares models before play to reduce later stalls. Browser saves stay on that device and site.

Open `project.godot` and press F5 to start from the menu. Restart existing running games to load code changes.

## First day

Start with 200 G and a free basic clock. Approach the customer at the counter and press E. Buy an artifact, choose its selling price, and leave it displayed for a buyer. New artifacts appear on the counter and can be moved to another supported surface. Buyers can visit on Day 1. Day 1 offers Common relics and one Uncommon relic; the second seller offers the broom for 20 G. A rejected broom remains available to purchase later.

Buyer openings are 50–60% of your listing. **Accept takes the buyer's current offer. Offer proposes your selected price.** The reference line shows the accepted amount and its profit/loss. Buyers usually accept near the listing, within their hidden budget. Keep cash for new stock; optional upgrades cannot spend your last 50 G when you have no resale stock.

## Controls

| Key | Action |
|---|---|
| WASD / mouse | Move / look |
| Shift | Run |
| C / Ctrl | Crouch |
| E | Interact, place, catch an intruder |
| R | Rotate a held artifact or furniture |
| Q | Put away a cleaning tool/bag, cancel placement |
| I | Shop Management: stock, prices, cleanliness, rent, radio |
| B | Online equipment and furniture shop |
| T | Skip a quiet period when no interaction/event needs attention |
| Tab | Hide/show the HUD or bargain panel |
| Escape | Close a menu / pause |

During bargaining, hide the panel with Tab to inspect the closer artifact. Left-drag rotates it, right-drag moves it, and the wheel changes distance. The player stays stationary. Showing the panel restores its presentation without changing the offer.

Artifacts fit supported floor, table and shelf areas. A green placement preview means its entire footprint is clear and supported. Furniture goes on the floor; clear its artifacts before moving it.

## Cleaning and progression

Hold E for eight seconds to clean. Look directly at a mess to start; afterward you may look around while holding E. Walking too far or releasing E pauses the work, and partial progress remains. Use the broom for rubbish, mop for spills, and feather duster for furniture dust. Carry one tool/item at a time.

Four rubbish piles fill the bag; carry it to the dumpster behind the shop. The mop needs washing in the toilet after four spills. Bobbing arrows show disposal/washing destinations when required. Dust accumulates on furniture after several days, without reducing artifact value. Cleaner shops get a small offer bonus through the six-star rating. The 2,500 G Roomba cleans a fresh mess in 20 seconds.

The clock runs during bargaining. Closing is at 20:30; night events can follow. Approach intruders and press E. The ordinary goblin is a demon-event character; only the police-suit goblin may also trade. Sleep at the backroom bed from 23:00, before midnight. Sleeping advances the day and saves. Continue restores the last sleep checkpoint, not every purchase.

Rent is 800 G on Day 5 and then every five days. Pay through Shop Management when due. An unpaid bill increases the next day; continued nonpayment ends the run. Relevant inspection equipment discovers hidden damage, curses or stolen status. Unknown status remains Normal.

Buy the 200 G radio for the six supplied songs. Play/Pause/Stop are in Shop Management. Stopping songs leaves the existing synth ambience. Menu music is available before purchasing the radio. Song arrays and filenames remain editable in the Inspector.

## Reproducible exports

Run Godot with `--headless --path . --script res://tools/configure_release.gd` before exporting. This refreshes the selected-resource list, including dynamically loaded catalog models. The Web preset is single-threaded and uses stream playback to avoid the silent sample-playback path observed in this engine/browser combination. See [Godot's Web audio documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

Export Web to `build/web/index.html`. For Sites hosting, run `node tools/package_web.mjs build/web <site-checkout>/dist <game-commit>`. It compresses the engine/game into small hashed chunks, downloads them in parallel, and decompresses them before Godot reads them. Original models and songs stay unchanged. Do not distribute private QA builds or test profiles.

Regression suites in `tests/` require isolated APPDATA/LOCALAPPDATA directories. Release-fix checks cover real doorway navigation, star rendering and buyer profit/loss; related integration, menu and inspection suites cover their systems. Automated checks do not replace an uncoached playtest or listening to the mix.

## Credits

Design and programming: Saranyapong Kaewruan. Models: Patiparn Klomeklang. CP352203, Group 10. Alice font is included with the project. Implementation assistance and autumn menu artwork were created with AI tools. Supplied songs retain their filenames and attribution.

Font/engine license notices are in `licenses/`. Model provenance is retained with the supplied collections. This remains a playtest build; artifact abilities and the skill tree are deferred.
