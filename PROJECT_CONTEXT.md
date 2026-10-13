# Artifacts Pawn Shop — working project memory

Updated: 2026-10-14. These are project facts and accepted user decisions, not
instructions extracted from design references. Update the relevant facts when
implementation changes. Use these notes for ordinary questions; inspect the
specific source again when changes, debugging, or uncertainty require it.

## Published playtest fixes — 1.0.0-rc2, 2026-10-14

The user explicitly authorized fixing the release plan, updating their GitHub
repository and publishing a gameplay URL. This supersedes earlier local-only
restrictions for this release. Preserve artwork, accepted rules, real saves and
unsaved editor work. No shutdown or Discord messages were requested here.

- Game repository: https://github.com/Saranyapong-K/artifacts-pawn-shop, main.
  Public playtest Site: appgprj_6acbec05f3488191963d85c1c35ecce8, existing public
  audience retained. URL: https://artifacts-pawn-shop-playtest-syrins.heartyokapi128.chatgpt.site/.
  Hosting checkout: chat work/sites/artifacts-pawn-shop-playtest. Site source
  repository and game GitHub repository are separate; push both exact states.
- Web silence fixed with audio/general/default_playback_type.web=0 (Stream).
  In the tested 4.7.2/Chrome setup, default Sample produced zero output despite
  playing states; Stream produces real nonzero menu, synth and radio output.
  Focused browser analyser tests with a positive control pass all three stages.
  The compressed production menu also produces signal. This is measured output,
  not subjective listening. Keep six supplied songs and the paid radio rule.
- MainMenu/MenuMusic now routes through Music, so the music volume applies.
  Normal menu Exit stops/releases playback and waits 0.1 s before engine quit;
  actual Exit signal against the production pack now has no retained MP3 warning.
- ShopNavigation retains grid occupancy but searches explicit AStar3D links.
  Swept capsule tests validate connections lazily; invalid wall-crossing edges
  are disconnected and cached until the next geometry rebuild. Temporary queued
  cells disable matching graph points and restore them after pathfinding.
  The original bed-route reproduction now passes with actual physical walking
  through the rear doorway. Existing arrival/failure checks remain.
- RatingStars is now an editable Control with ui/rating_stars.gd, drawing six
  stars directly. Filled gold/empty outlines need no OS font fallback. GameUI
  supplies cleaning.stars(); original position and N/6 line are unchanged.
- Buyer reference text shows listing, the exact Accept amount and profit/loss
  relative to recorded purchase cost. Counteroffers update it. Hidden budgets,
  50–60% openings, Offer/Accept semantics and rarity price limits are unchanged.
- Warmup requests resources ahead, draws batches of four, and warms the actual
  customer recolour shader/masked meshes with deterministic palette indices.
  This avoids compiling that shader only when the first visitor arrives.
- tools/configure_release.gd builds the selected-resource export list from
  game scripts/UI/scenes and catalog paths. Run it before future exports after
  adding resources. Both presets retain dynamic catalog models and exclude
  unused art; original source assets are not resized or overwritten.
- tools/package_web.mjs emits compressed hashed chunks (each <=8 MiB), a
  cache-busted loader, and release.json identifying the game commit. Chunks
  download in parallel and stream-decompress for Godot. Current engine+pack
  transfer is about 43 MB versus 107 MB raw. This preserves single-threaded Web
  compatibility without requiring shared-memory browser headers.
- Validation: integration 66, menus 98, physical release regression 12,
  artifact inspection 27, browser flow 16 checks pass. Compressed clean browser
  menu/New Game/stock/shop/pause and real mouse capture pass without runtime
  errors. Audio signal passes separately from playback-state checks. One new
  startup sample was ~4.7 s to menu and ~21.4 s for New Game preparation; it is
  still an initial loading wait, not a promise of instant loading or all-device
  performance. Original rent/economy rules retain prior Day 6 validation.
- Git excludes/untracks generated .godot caches while preserving local files.
  The user's open editor is never saved/reloaded/closed. Release validation and
  private profiles live in chat work/release-fixes-2026-10-14. README is updated
  to current Day 1 buyers, cleaning, sleep-only saves, radio and export workflow.

## Local release readiness testing — 2026-10-14

Report: [Release-readiness-2026-10-14.md](C:/Users/Syrins/Documents/Codex/2026-10-10/hee/outputs/Release-readiness-2026-10-14.md).
Evidence and isolated builds/profiles:
C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/release-readiness-2026-10-14.
The user authorized local export testing; no publishing, sharing or shutdown.
No gameplay source or UI layouts were changed during this testing pass.

- Fresh production Windows/Web releases were exported independently of the
  user's editor. Separate QA variants added an autoload only to an isolated
  project copy. Never distribute windows/*-QA*.exe or the web-probe build.
- Actual Windows release engine: normal-speed Day 1 completed 15 transactions,
  seven sales and real held-E rubbish cleaning; first resale at 96 seconds.
  This used automated input/assisted aiming, not an uncoached human playtest.
  Customers continued beyond three. Its initial bed-route failure was a test
  navigator hitting a wall; a physical route through the door passed.
- Separate earned-money run at 8x except physical walking reached Day 6,
  60 transactions/27 sales, cleaning and three real-ray thief catches. No
  injected wallet/stock. Actual rent button paid 800 G on Day 5 (1271 -> 471 G),
  next due Day 10. End wallet 586 G, five artifacts. Physical bed E and summary
  advanced each night. Purchased stock used automatic counter display; all
  manual furniture/grid arrangements were not re-tested in this release pass.
- Fresh native Continue and a separate same-process menu/Continue round trip
  restored that exact Day 6 checkpoint: 586 G, stock 5, bag 1/4, due rent 0,
  next rent Day 10. Both targeted native reload runs exited 0.
- Browser 16 targeted flow/input/save/radio-state checks passed, zero captured
  script/runtime errors. Actual left/right drag and wheel manipulate the
  artifact while player/camera remain stationary. Page refresh/Continue restores
  a Day 2 checkpoint. Browser bedtime was prepared; radio test supplied 500 G
  then bought the 200 G radio. These fixtures are not a full browser economy run.
- CONFIRMED unresolved Web audio: focused Chrome output samples were zero
  after a click in the clean production menu and in QA gameplay/radio tests,
  despite running AudioWorklet, unmuted Master and advancing playback states.
  A separate oscillator positive control produced signal. Native production
  menu music through WASAPI produced peak 0.445/RMS 0.055, so the song data
  is valid. Exact web/backend cause remains unresolved. Audio was measured,
  not listened to; playing-state tests alone must not imply audible playback.
- CONFIRMED unresolved navigation: approach_route to the bed can cut through
  Shop/Wall/StaticBody3D near X/Z (3.18,-1.99). Physical doorway-guided walking
  passes. Free grid points alone do not prove a collision-free connection;
  validate swept segments/doorway connections. Customer front entry passed;
  broader effects on robot/backroom routes remain a risk, not a reproduced
  general customer spawn failure or an impassable bed.
- CONFIRMED unresolved browser rating: RatingStars draws missing-character
  boxes. Its autumn theme font lacks U+2605/U+2606; native uses platform font
  fallback. Ship a symbol font or star icons; preserve heading/rating positions.
- CONFIRMED low-priority menu exit warning: normal Exit signal against the
  production pack exits 0 but retains AudioStreamMP3/playback and first menu
  song. Frame-limited standalone release exit repeats it. Ownership/cleanup
  cause is not isolated; no demonstrated save loss.
- Web payload is about 110 MB raw. One menu load was 5.2 s and New Game
  preparation 23 s with another native test active. Isolated warmed frame
  intervals were ~16.7 ms (near 60 FPS). These localhost samples do not prove
  internet download speed, crowded-game performance or other-device support.
- Verdict: controlled Windows demo is usable; current Web release needs audio
  and font fixes. Still need uncoached first-trade/manual-display feedback and
  listening to the mix before calling the game finished. Preserve low buyer
  openings; clarify Accept's amount versus Offer rather than retuning rules.
- All 110 tracked source/config hashes and real save.json/settings.cfg hashes
  matched pre-test values. Existing editor PID 16916 stayed running untouched.
  Historical test counts below are prior coverage, not re-run in this pass.

## Artifact mouse inspection — user correction, 2026-10-14

- The user clarified that inspecting means moving/rotating the closer offered
  artifact with the mouse. Player walking and camera look during bargaining
  were an assistant misunderstanding and have been removed.
- During HAGGLING, Tab hides the book and brings the artifact 1.25 m in front
  of the fixed BargainCam. Player controls remain disabled and the cursor stays
  visible. Left-drag rotates the model on two axes, right-drag moves it across
  the view, and the mouse wheel moves it closer/farther (0.85–2.0 m).
- scripts/bargain_artifact.gd handles unhandled mouse events while inspecting.
  GUI buttons receive their clicks first, so the reveal arrow still works.
  Movement is clamped to keep the model in view. Gentle initial rotation stops
  after manual input; the chosen orientation stays still when released.
- Showing the book restores the original position, orientation and distance;
  price and transaction state are preserved. Inspection is a temporary visual
  transform and never changes inventory placement, grid footprint or item size.
- DayManager.is_inspecting_artifact drives the existing GameUI footer text:
  Drag: rotate · Right-drag: move · Scroll: zoom · Tab: bargain · ESC Pause.
  The bargain key follows remapping. Original UI scene artwork/layouts remain.
- Resizing preserves the manipulated model. Pause blocks dragging; receipts,
  departure and closing disable inspection. Normal movement resumes only after
  leaving bargaining. Equipment inspection still uses its existing buttons.
- Native scene/input/physics inspection checks: 27 passed, including actual
  drags, scroll, stationary player/camera, release, resize, pause, arrow clicks,
  damage inspection, purchase/price save and closing. Menu suite: 98 passed;
  native integration suite: 66 passed after the corrected artifact controls.
  Evidence: C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/artifact-drag-inspection-2026-10-14.
  tests/bargain_movement_test.gd now routes to bargain_inspection_test.gd; the
  old walking expectations are superseded. Real save/settings and the running
  user editor/playtest are preserved; existing playtests need restarting to
  load this corrected implementation.

## Submission fixes, music and bargain hint — 2026-10-14

Current report: [Submission-fixes-2026-10-14.md](C:/Users/Syrins/Documents/Codex/2026-10-10/hee/outputs/Submission-fixes-2026-10-14.md).
Backup, isolated profiles, logs and captures:
C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/submission-fixes-2026-10-14.
These facts supersede older radio, buyer slider and offered-model facts below.

- Supplied Cleaning/Dust.glb is connected in CleaningWorld. Raw bounds are
  0.824 x 0.290 x 0.592 m; runtime uniform fitting limits footprint to 0.48 m
  and height to 0.17 m. Dust remains per furniture/shelf, not per artifact.
- Holding any cleaning tool displays only "Press Q to drop"; Q releases it.
  Existing eight-second manual cleaning, cancellation/resumption, dirt/bag
  capacities and Roomba rules are preserved.
- Thief speed derives from player sprint_speed x 1.08: default 7.02 versus
  6.5 m/s. Approaching + Interact remains the catch mechanic. Yellow warning
  eyes use the Window mesh's transformed AABB center and pane face; they retain
  their original yellow appearance instead of floating outside the building.
- Main/World now instances world.tscn, inheriting the supplied World.glb.
  world_runtime.gd creates exact Earth/road/fence mesh collisions plus a thin
  continuous perimeter beside the fences and road. There is no box across the
  road. Invisible shallow ramps bridge raised curbs and the shop approach so
  the player can walk both ways without jumping. Source model art is untouched.
  Actual capsule walks across/back and both side-gap stops passed; a real police
  customer still walks through the front door to the cashier.
- Offered artifacts use bargain_artifact.gd, separate from saved placement.
  Maximum dimension is 0.55 m; flat models tilt toward the viewer. Normal
  bargain-camera-relative position is (-0.62, 0.28, -2.0); hiding the panel now
  centers it at (0, 0, -1.25) relative to BargainCam for mouse manipulation,
  with the stationary player and controls described above. Showing restores its original
  presentation position/rotation using a 0.35-second transition.
- The native black TogglePanelButton tooltip was removed. Screen/ToggleHint
  uses the existing Alice/autumn font, cream text and brown outline beside
  the arrow, reading "Tab · Hide panel" / "Tab · Show panel". It follows the
  current toggle_hud key binding and appears only during the bargain panel.
- Buyer openings are 50–60% of the listing. Hidden budgets stay within listing
  +/-10% and the legal rarity cap, including cleanliness modifiers. 90% of
  initial budget draws are at least the listing. A single Offer at the default
  listing usually succeeds; Accept accepts the buyer's lower opening amount.
  Buyer slider maximum is min(legal cap, ceil(listing x 1.10)), minimum 1 G.
- Catalog IP17 uses assets/Relics/Iphone.glb, footprint 1x2, fixed Rare only.
  DayQueue filters fixed-rarity entries when generating sellers. Existing Rare
  unlock remains Day 3; IP17 cannot appear as Common/Uncommon on Day 1/2.
- Main/Marks/InternetSpot is editable at (7.2, 1.35, -1.6). The floating/slowly
  rotating ui/Internet.glb instance opens the existing computer-shop website
  through the interaction ray and "Press E to browse" (current key name).
- AssetWarmup autoload shows editable ui/loading_screen.tscn before New Game,
  Continue and next-day preparation. It caches resources and draws customer
  and starting Common/Uncommon models once in a small SubViewport. Remaining
  fixed-rarity models warm before Day 2. Flexible catalog models are eligible
  for Common already, so those are all warmed on Day 1. Repeated launch/sleep
  clicks are guarded; Escape/Tab cannot open menus and pause an active load.
  This is local preparation; browser stalls/FPS were not measured or exported.
- Six supplied Song/*.mp3 files populate MainMenu.menu_music and
  Day_manager.radio_songs Inspector arrays: 2 AM, In Dreamland, little break,
  On The Top, SweetSyrups, Taiyaki. Filename ticker remains. New games have
  the clock free but real songs unlock by buying the 200 G radio, per the
  latest user request. Existing saved radio ownership is preserved on load;
  the old automatic free-radio grant was removed. Empty-stock purchases still
  retain 50 G working capital. Owned radio starts songs, advances tracks and
  provides Play/Pause/Stop in Shop Management. Stop leaves the synth ambience.
  The existing funky synth loops play in gameplay even without radio, on SFX
  bus; songs use Music bus and duck the synth. No audio was auditioned.
- Confirmed during testing: leaving gameplay while CustomerFlow.take_next was
  awaiting an arrival could repeatedly call get_tree() after tree exit. It now
  uses a captured SceneTree and exits on invalidation; DayManager invalidates
  awaited arrivals/epochs and expires its timer on exit. Menu return/Continue
  subsequently passed without the error loop or shutdown leak warning.
- Native scripted submission checks: 38 passed; actual bed E -> summary ->
  sleep -> Day 2 at 10:30 -> saved Continue restored wallet, IP17 stock,
  mop uses, bag load and radio ownership in a prepared private scenario.
  Other current results: integration 66, debug 53, menus 98, gameplay 179,
  cleaning 273, GPU placement 281, final UI 9; night suite passed. Sound used
  Dummy driver. These are code/actual-scene checks, not human play or a fresh
  full economy/rent playthrough. Real save.json/settings.cfg SHA256 matched
  the pre-pass files; user editor PID 2880 was neither saved nor closed.

## Implemented audit fixes and new models — 2026-10-13

Current implementation report: [Fix-validation-2026-10-13.md](C:/Users/Syrins/Documents/Codex/2026-10-10/hee/outputs/Fix-validation-2026-10-13.md).
Backup, isolated profiles, logs and rendered captures:
C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/fix-pass-2026-10-13.
The audit below is a historical pre-fix snapshot, not the current bug list.

- The user authorized fixing/adjusting the Astra report and adding the supplied
  Roomba, Goblin, GoblinPolice and Book models. Everything stays local; no new
  export, deployment, messaging or shutdown. Never save/reload the user's
  running editor on their behalf; retain the existing unsaved editor state.
- B1: authored StockMenu/PayRentButton now pays through GameUI when rent is due,
  shows the actual due amount and checks affordability. Payment advances the
  existing rent schedule. It is not under hidden computer-shop Actions.
- B2: Basic clock/radio were originally granted free in this pass. The user's
  2026-10-14 song request supersedes radio: new games now buy it for 200 G.
  Equipment/furniture UI uses GameState.can_buy_upgrade: when resale inventory
  is empty, discretionary spending must retain at least 50 G working capital.
  Artifact trading and the paid 20 G broom follow existing purchase rules.
- B3: proximity_door disables only leaf collision during opening/closing and
  restores its original layer/mask once fully closed. Walls, authored door
  clips and player capsule are retained. Closed-door approaches pass both
  directions on both doors without the old sideways push.
- B4: Customer.walk_to reports arrival/failure; failed routes cannot create a
  serving customer. Actual walks sweep for new obstacles and replan when the
  shared navigation revision changes. Persistent failure releases the visitor
  safely instead of starting remote bargaining. Arbitrary future layouts still
  need physical testing. New furniture does not become a walk-through box.
- B5: CustomerFlow owns real arrival delays; T advances that countdown and
  corresponding game time, with no duplicate wait for an existing queue.
- B6: dialogue cancellation uses generation tokens; closing invalidates awaited
  introductions and clears actors safely. Next-day conversations recover.
  Closing also completes the already-paid price/receipt transition before night.
- B7/B8: computer-shop X/minimize close correctly; game-over return fits
  960x540, 1152x648 and 1920x1080. Original artwork stays in place.
- B9: inspected stolen findings persist as inspections.stolen_found across
  newspaper changes and save/load. Discovery supports all categories through
  magnifier inspection plus a newspaper report; unknown items still display
  Normal. Owning equipment alone does not reveal status.
- B10/B11/B12: one cached player interaction ray owns prompts and activation;
  without a duster, dust does not hide artifact/book interaction. Prompts and
  control hints use GameSettings key names. Missing station visual metadata is
  checked before access. Existing cleaning free-look/cancel/resume is retained.
- Roomba costs 2,500 G, lives in owned_items.roomba and spawns after purchase or
  restore. scripts/roomba.gd navigates/patrols, pauses with menus, and cleans
  rubbish, spills and dust in 20 simulation seconds per fresh spot. Dust is
  cleaned from a reachable floor position beside the furniture. Robot cleaning
  does not dirty the player's mop or fill the manual trash bag.
  Shared record.progress stores work in eight-second manual units: robot rate
  is 8/20, so partial work survives tool switching and sleep saves. Manual work
  on the same spot takes priority. Ownership/progress save; exact robot pose
  and current route are transient and restart from its home.
- CleaningWorld exports roomba_model with assets/Cleaning/Roomba.glb assigned;
  Main/RoombaSpot overrides fallback CleaningWorld/ToolSpots/RoombaSpot. The
  supplied animation imports as RoomBa and is looped. ArtifactVisual bounds
  now account for skeleton poses and inverse binds; the offset Roomba rig is
  visibly fitted rather than normalized around an empty raw mesh origin.
- Latest user correction: regular Goblin is ONLY a demon-event character;
  ONLY GoblinPolice may buy/sell as a goblin customer. The ordinary Goblin
  customer wrapper was removed. The user supplied updated GoblinPolice.glb
  with an Idle animation later in this pass; it is now connected for bargaining.
- Day_manager.tscn customer_scenes has four editable entries: NPC1, NPC2, NPC3
  and GoblinPolice. Girls fit 1.65 m, male 1.85 m, both event goblins 0.9 m.
  Goblin walk_animation is imported Running (raw Running_loop loses its suffix
  during import). GoblinPoliceCustomer exports idle_animation = Idle. Customer
  uses the configured idle while waiting/bargaining and as fallback for missing
  talk/reaction clips; Running resumes on departure. Regular demon Goblin still
  has no idle clip and uses its bind pose while standing.
  Half-height customers use a small counter step while serving and return to
  floor height before leaving. Small-customer bargain framing adjusts only
  temporarily; it restores the original authored camera afterwards.
- DayManager/NightEvents use Goblin.glb for demons and GoblinPolice.glb for
  police. Both fit 0.9 m; thieves retain the accepted temporary human model.
  Police visually visit alongside existing confiscation/fine rules and are not
  catchable. Demon/thief approaching-key interactions are retained.
- Main/ShopManagementBook uses assets/Relics/Book.glb; its support-derived
  position is currently (3.1, 0.839853, 0.572808), safely inside the countertop.
  It opens the existing management book. RatingStars sits beside the heading;
  CleanlinessRating retains its line and displays Cleanliness: N/6 plus bonus.
  Original UI textures, authored shop transforms and player scene are retained.
  Offered models are framed above the bargain book, left of the customer,
  instead of hidden behind the panel or covering their face.
- Day 1 visitor three is a buyer if priced/displayed/non-held stock exists;
  otherwise the seller path remains. First two visitors remain Common artifact
  and paid broom; the one Uncommon seller appears later if visitor three buys.
  Later buyer selection stays random at 50% with eligible stock. Arrival pacing,
  capacities, patience and legal prices are unchanged.
- First guidance briefly explains buying, pricing and displaying. Opening radio
  popup cannot overwrite it; Day 1 newspaper is delayed to noon. Warm lights/fog
  are gentler; neutral ambient and sky reflections keep materials readable.
  Existing footsteps are connected and a soft cleaning completion cue added.
  Sound was not auditioned in dummy-audio tests. Final music remains a user
  Inspector array; current fallback audio and filename ticker are retained.
- Eight furniture cards and Roomba show rendered supplied-model thumbnails;
  four original equipment icons remain. Native ImageTexture .res resources
  avoid reimporting through the user's open editor. All 13 cards have editable
  inherited overrides so standalone ShopMenu retains details after saves.
- Integrated GPU run: New Game -> purchase/price/display -> broom -> real
  ray/held-key rubbish cleaning -> sale -> closing/night -> sleep/Day 2 ->
  trading -> Day 5 rent button -> sleep/Day 6 -> Continue. No injected money or
  stock; normal speed until first sale, then 8x. First resale was 107.627 seconds
  from launch (39 G from a 25 G buy). Rent 800 G was paid via UI; Day 6 restored
  3,920 G, two artifacts and next rent day 10. Cleaning save persistence was
  checked separately. One scripted strategy with assisted positioning is not
  evidence of human difficulty/feel.
- Current regression results: integration 66, debug GPU 53, menu 98, cleaning
  273, gameplay 177, GPU placement 277, GPU outlines 783 checks; night suite
  passed. Final logs/captures are in fix-pass-2026-10-13. Real save/settings
  hashes are checked separately; passing suites do not certify every layout,
  human onboarding, natural intruder difficulty, or how audio feels.

## Full local audit — 2026-10-13, historical pre-fix findings

Report: [QA-full-review-2026-10-13.md](C:/Users/Syrins/Documents/Codex/2026-10-10/hee/outputs/QA-full-review-2026-10-13.md).
Evidence: C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/full-audit-2026-10-13.

- Method: actual GPU game with scripted controls, button signals and assisted
  positioning; visually reviewed captures. One normal-speed Day 1 (~10 min),
  then isolated Day 2–6 continuation at 8x simulation. Not a human playthrough.
  Sound was muted/dummy, so sound feedback is code/assets review, not listening.
  Cleaning was successfully exercised separately with real rays; the normal
  session's attempted broom pickup was out of reach (harness error, not a bug).
- Day 1 observed: 16 visitors, 8 purchases including broom, 3 sales, 223 G cash,
  4 unsold artifacts, 105 G realized sales profit. First sale ~5:06 after launch;
  wallet fell to 11 G beforehand. Old three-customer cap was not reproduced.
  Day 1 Common/broom/one-Uncommon opening and buyers work.
- Extended trading reached 1,786 G at end Day 5. Missing payment UI required an
  explicitly labeled handler bypass; it deducted 800 G, next rent day became
  10, and Day 6 Continue restored 986 G and stock. This is not a successful
  UI-only rent playthrough. Natural catches/travel/difficulty were not assessed.
- B1/P1: no accessible connected rent action. Prepared 1,000 G scenario still
  failed on day 7 for unpaid rent. game_ui, shop_menu, game_state.
- B2/P1: New Game -> buy radio for 200 G leaves zero money and zero stock, with
  no income/refund recovery. Cleaning gives offer bonuses, not cash. A same-cost
  shelf has the same source-level risk. Finish basic starting time/music access
  and prevent discretionary purchases from stranding the trading loop.
- B3/P1: moving-door collision pushes player into frame from one approach side
  on both doors. Reproduced after later scene saves; already-open doors pass.
- B4/P1-P2: blocked real navigation grid still returns serving NPC 7.58 m from
  counter. A real NPC on a precomputed route walks through a newly added solid
  box. Frequency in arbitrary furniture layouts remains unmeasured.
- B5/P2: T/physical-arrival countdown desynchronization remains confirmed.
- B6/P2: close during intro, let actor leave/free, sleep, advance next customer's
  dialogue -> freed-object type error in day_manager._intro_active. Old ui.say
  awaits survive cancellation. Reproduced at normal speed with prepared time;
  extended run later recovered, so no permanent softlock was established.
- B7/P2: computer-shop X/minimize have no pressed connections; maximize works.
- B8/P2: game-over MainMenuButton partly below 1152x648 viewport (bottom ~662).
- B9/P2: identified stolen status depends on today's newspaper flag and reverts
  to Normal next morning; inspection flag itself persists.
- B10/P2: dusty counter plus artifact can show overlapping Dust/Hold E and
  artifact/Pick up prompts. Independent rays disagree about Area3D targeting.
- B11/P2: remap Interact to F, but tool prompts/control strip still display E.
- B12/P3: wash/dumpster prompts call get_meta("visual", null) without that key,
  causing repeated runtime errors. Actual washing/disposal still work.
- Confirmed passes: free-look held-E cleaning, release/distance cancellation,
  saved/resumed progress, mop fourth-use/real toilet wash, full bag disposal,
  actual counter placement; real-NPC FIFO/capacity/overflow/patience/browse-leave/
  closing; live bargaining, aligned action buttons and visible hide control.
  Isolated sleep/Continue retained tested money/inventory/cleaning/rent state.
- Rerun suites: debug 53, menu 92, GPU placement 277, night tests passed. Debug
  test leaks objects/a resource at exit; inherited GameOverMenu-child warnings
  remain. Do not equate these counts to bug-free gameplay. Dynamic doors, rent
  wiring and dialogue lifetime were missing from that coverage.
- Economy model only: 300 seeds per configuration, 5,400 runs total. At 12
  opportunities/day and 3 stars, end-Day-5 median cash was 574 G for 1.5x listing
  plus accepting opening offers, 1,401 G for default 1.75x plus one counteroffer,
  4,889 G for legal-cap pricing plus one counteroffer. Able to cover 800 G:
  23%, 74%, 94%. Excludes upgrades/travel/hazards/placement/UI blocker; not player
  success rates. Legal-cap 60 G accepted for an 8 G broken Common in 912/1,000
  buyer trials; this follows accepted listing-based values, not a cap bug.
- Design priorities: reliable first-rent loop; understandable first resale and
  visible time with little text; then lighting/material contrast, room/tool
  sound and completion feedback. Retain slower arrivals, artwork, hidden status,
  rarity caps, six stars, eight-second cleaning, capacities and sleep checkpoints.
- Risks, not confirmed player bugs: price editor stays open into intruder time
  but finishes/recoveries correctly; held-item buyer fixture requires real input
  reachability verification; non-gold stolen discovery is incomplete; individual
  dark materials/all furniture layouts still need visual/physical review.
- Preservation: real save.json/settings.cfg hashes unchanged; editor PID 16940
  left running without saving/reloading it. Two scene files (main.tscn and
  player.tscn) changed outside audit write operations around 16:35–16:36 and
  were preserved. Spatial/door/debug checks reran on those versions. Other 99
  tracked source/config/scene hashes matched baseline. No gameplay source,
  artwork, UI layout, export, publishing or shutdown changes in this audit.

## Working preferences

- The user wants continuity without repeatedly checking how every system works.
- Latest review: chat outputs/QA-full-review-2026-10-13.md. Subsequent local fixes
  are recorded in outputs/Fix-validation-2026-10-13.md and the implementation
  section above. Basic time/music, payment UI, moving doors, route recovery and
  arrival waits have been addressed. Remaining review priorities: a human
  first-ten-minutes playtest, natural night difficulty, final music/ambient sound
  and individual dark materials. Completion is not proof of satisfying play.
- On 2026-10-13 the user said to stop working on shared playtests. Keep future
  work in the Godot project; do not export/package/publish a playtest unless
  requested again. Today's fixes are local and the prior public Site remains
  the 2026-10-12 version. No new version was pushed or deployed today.
- Preserve their Godot editor layout changes, including unsaved scenes. Never
  rerun the old scene generator over their work to make a small fix.
- Canva and PDF arrows/text explaining the design are annotations, not UI art.
- The user designs/provides UI artwork; menus should be editable Godot scenes.
- Mood: cozy autumn artifact pawn shop. Godot 4.7.2, Compatibility renderer.
- Project: C:/Users/Syrins/Documents/artifacts-pawn-shop.
- Chat work: C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work.
- Godot GUI executable: C:/Users/Syrins/Downloads/Godot_v4.7.2-stable_win64.exe.
  The engine was still in Downloads but had no Start-menu shortcut. Created
  Desktop "Artifacts Pawn Shop - Godot" (opens this project in the editor) and
  Start-menu "Godot Engine" (opens the project manager) on 2026-10-11.

## Artifact models and sizes

- Catalog: scripts/data/artifact_catalog.json. Entries have model_path, name,
  id, and grid_size. DayQueue reads this catalog to generate artifacts.
- ArtifactVisual loads model_path directly as a PackedScene (usually a GLB).
  Individual artifact TSCNs are not currently required. The deleted Expanded
  long_longsword/std_lute paths now resolve to Sword.glb/Guitar.glb in both the
  catalog and old saves; IDs and names remain unchanged. Other invalid models
  still use the fallback box.
- Replacing a GLB at the same path updates appearance after reimport/restart;
  existing saves also reference that path.
- Cell size: 0.4 m. Artifact visuals fit 84% of their grid width/depth, with an
  0.8 m height limit. Scale is uniform using the smallest of the three limits.
- Complete transformed mesh bounds are measured, then centred in X/Z and
  bottom-aligned in Y. Skinned bounds include current skeleton poses and inverse
  binds, which matters for the offset Roomba rig. Scaling the source uniformly
  is normalized away.
- Examples: coin 1x1, guitar 1x2, original sword and surfboard 1x3, crystal ball
  2x2. These are footprints, not fixed mesh dimensions.
- World interaction box uses 92% of grid width/depth and measured visual height.
- Furniture placement preview uses height limit 2 m and footprint margin 1.0.
- Each artifact stores its footprint in the save. Catalog grid changes affect
  new artifacts; existing saved footprints do not automatically migrate.
- ArtifactVisual and relic_item implement rendering/sizing/interaction;
  placement_manager handles the grid. It now anchors to real surface patch
  edges, searches nearby legal positions, checks footprint support/occupancy
  and vertical clearance, and avoids shelf uprights/boards. Runtime interaction
  shape is named InteractionCollision. Remaining artifact appearance issues
  need individual visual review rather than assuming all source textures exist.
- All artifact visuals now receive world rarity outlines automatically through
  ArtifactVisual.create: Common white, Uncommon green, Rare blue, SR gold,
  SSR a full rainbow slowly cycling approximately every 25 seconds.
- Outline width is 3 screen pixels (ArtifactVisual.OUTLINE_WIDTH_PIXELS).
  The shader works in the current Compatibility/OpenGL renderer. A stencil
  mask (reference 1, reserved for artifact silhouettes) prevents internal
  edges and stops glass interiors being filled with the rarity colour.
- A cached separate shell mesh has smoothed normals so flat imported models
  have continuous outlines. Source meshes, materials, textures, normalization,
  and collisions stay unchanged. The shell casts no shadows.
- Furniture and placement previews explicitly disable rarity outlines; previews
  keep the existing cyan/red validity colours. Existing saved artifacts recreate
  their outlines from saved rarity. Replacing GLBs needs no outline setup.

## Economy, bargaining, and customers

- Rarity ranges: Common 10–50, Uncommon 51–300, Rare 301–1000,
  SR 1000–3000, SSR 3000–20000 G. Maximum listing price = tier maximum x 1.2.
- Starting money: 200 G. Day 1 opens with seller references 25, 20, 100 G:
  a Common artifact, a Common broom fixed at 20 G, then one Uncommon seller.
  A guaranteed third-visitor buyer may precede that Uncommon seller if stock is
  eligible. Every additional Day 1 seller offers Common only.
- Customer generation continues after the opening queue: independently random
  walk-ins, customer model, and clothing colours. No old three-visitor cap.
- Physical crowd: scenes/customer_flow.tscn / scripts/customer_flow.gd.
  Up to six visitors; three waiting slots. Arrivals every 28–45 real seconds
  during opening hours. Later visitors browse 1–3 places, pause 2.5–5 seconds,
  then 25% leave and the rest join a FIFO line (full lines send visitors out).
  Later queued visitors lose patience after 95–150 seconds; the first two
  deals remain protected. Queue repositions as each person reaches the counter.
  AStarGrid2D shop_navigation samples real collisions at 0.5 m; routes avoid
  existing furniture and waiting people when computed. Walks now report failure,
  sweep/replan around new obstacles and validate counter arrival before serving.
  Failed arrivals leave safely; arbitrary future layouts still need physical QA.
  Bargaining leaves the world/clock/crowd running;
  stock/settings still pause. Eight-direction paths avoid blocked corners;
  visitors accelerate/decelerate, consume waypoints continuously and turn
  smoothly. Doors recognize visitors as well as the player.
  Main QueueSpot*/BrowseSpot* Marker3Ds override defaults. Without overrides,
  QueueSpots in customer_flow.tscn are offsets from CashierSpot; BrowseSpots
  are editable scene coordinates. DayManager.crowd_enabled=false retains the
  legacy flow for deterministic economy fixtures only; real gameplay uses it.
- Buyers can visit starting Day 1. Each arrival has a 50% buyer chance when
  stock is priced above zero, actually placed, and not held; otherwise a seller
  arrives. The first two actual Day 1 visitors are reserved for sellers so
  the broom is always the second visitor. Visitor three buys when priced,
  displayed, non-held stock exists; subsequent buyers remain random.
  Buyers do not consume entries in the opening seller queue. Closing: 20:30.
- Bargain slider scene max 200 is a preview value. On opening a seller bargain,
  runtime maximum = available wallet; zero wallet allows zero as minimum.
- On opening a buyer bargain, runtime max = min(legal cap, ceil(listing x 1.10)), min 1.
  Counteroffer updates change labels; the slider max is set when opening.
- Equipment: magnifier 359, curse detector 1000, Roomba 2500 G. Clock starts
  owned for new games; radio songs unlock through a 200 G purchase. Loaded
  ownership is preserved. Replacement clock costs 350 G. Empty-stock upgrades
  must retain 50 G.
- Furniture: display shelf 200, open shelf 250, glass counter 350, weapon rack
  500, glass cabinet 650, tall vitrine 750, combination cabinet 900, pedestal
  1200 G. User authorized choosing prices; Canva prices were illustrative.

## Inspection and stock

- Underlying status defaults to displayed “Normal” until inspected. Owning a
  tool alone must never reveal it.
- Per-artifact inspections dictionary persists magnifier/curse_detector findings
  through purchase and save/load; old saves default to no findings.
- Magnifier reveals damage. Curse detector reveals curses. Stolen discovery
  requires magnifier inspection and the delivered newspaper report, for all
  artifact categories. Discovered status persists as stolen_found and does not
  revert before tomorrow's report. Unknown status stays Normal.
- Shop-stock names have rarity-coloured outlines; SSR name letters multicolour.
  World model outlines now follow the supplied rarity.jpg reference. Stock text
  styling is retained; it has its own palette for readability on parchment.
- Price boxes appear blank until clicked. Enter commits. Escape cancels and
  keeps the saved old price. Invalid input saves 1 G. Zero means off sale.
- Only one row edits at once; switching rows/pages cancels the previous draft.
  Wallet refresh keeps active rows/drafts. Escape reaches the editor before
  opening/closing the pause book.

## UI scenes and controllers

- game_ui.tscn / scripts/game_ui.gd: wrapper, wallet, stock/shop actions,
  purchases, search, screen tint, modal layout. Stock/shop are Control scenes.
- stock_menu.tscn + stock_row.tscn / scripts/stock_row.gd: fixed heading/footer,
  scrolling artifact rows, inspection, inline price editing.
- shop_menu.tscn + shop_item_card.tscn: browser wallpaper, fixed wallet/search,
  scrolling equipment/furniture cards. Four original equipment icons remain;
  Roomba and eight furniture cards use rendered supplied-model previews.
- Each of the 13 shop cards has saved child overrides AND an editable instance
  path, so names/prices/icons survive Godot saving and work in standalone F6.
  The parent GameUI connects purchases/search in actual gameplay; standalone
  ShopMenu is primarily a visual scene preview.
- Buy artwork already includes “Buy”; native button text is blank. Owned uses
  a separate faded-orange style and “Owned”. Retain original disabled Buy
  style metadata so restarting purchases does not lose the artwork.
- bargain_menu.tscn / bargain_interface.tscn / scripts/bargain_ui.gd: Tab slides
  book down and upper-right flag up; circular reveal button remains visible.
- Purchase Complete receipt removed: listing a bought relic returns directly
  to play; the broom also exits without a receipt. Sale receipt remains.
  Offer/Accept/Reject share equal anchors/sizes/scale and a centered Accept.
  Book stays inside screen; reveal icon has zero artwork offsets and its
  animated position accounts for the full button height plus 12 px margin.
- MainMenu root Inspector exposes Menu music / Menu Music (AudioStream array),
  Music Placeholder and Music Scroll Speed. Drag WAV/OGG/MP3 files into the
  array. MenuMusic player uses Music bus and cycles tracks on finished. Bottom
  right clipped ticker scrolls the filename without extension; empty array
  displays Music coming soon. Browser playback retries after the first click.
- Existing settings book, key mapping, main menu, dialogue, receipt, summary,
  credits, and game-over controls remain separate scenes.
- UIref.pdf: D:/Download/UIref.pdf. Rendered pages/previews are in chat work.

## Time, saves, events, and outstanding work

- T skips the quiet gap between customers by advancing CustomerFlow.spawn_in
  and corresponding game minutes together. CustomerFlow owns physical arrival
  deadlines; an existing queue does not wait for a second arrival timer.
  A physical customer already moving to the counter blocks gap-skipping; it
  is assigned before that walk. Closing cancels pending arrivals.
  After closing, waiting passes time toward 20:45, 21:00, or 23:00. Active
  interactions and night intruders block waiting. Opening stock/shop pauses
  the clock; waiting closes the panel and releases that pause first.
- The user's edited StockMenu no longer contains its former footer buttons;
  ShopMenu Actions are hidden. T makes waiting available without changing
  these layouts. GameUI tolerates an absent WaitButton and connects it if present.
- Sleep saves to user://save_v2.json; user checkpoint must remain untouched by
  tests. Loaded clock access is retained; saved radio ownership is respected.
- Rent 800 G on day 5, 900 G on day 6 if unpaid, then jail when sleeping into
  day 7. StockMenu/PayRentButton is the connected visible action when due; it
  shows actual amount/affordability and advances the next rent day to 10.
- Thief is caught by approaching and pressing the current Interact key. Thief
  retains an accepted temporary human model. Regular Goblin is demon-only;
  GoblinPolice is assigned for police and also has a trading customer scene.
  Both fit 0.9 m. Police goblin uses its newly supplied Idle clip in bargaining;
  regular demon Goblin currently has running clips only.
- Demons may steal magnifier/curse detector/clock/radio; irreplaceable cleaning
  tools are excluded. Sleep interaction is now the padded actual Mattress
  target Main/BedSleep; the old counter rest journal was removed.
- Game is still being polished, not considered finished/playable end-to-end.
- Remaining: human pacing/onboarding/night difficulty review, individual dark
  artifact materials, listening/balancing the supplied songs against ambience,
  user-directed UI polish and further outside world art. Basic clock access and
  paid radio song controls are implemented.
- Old rc1 ZIPs in chat outputs predate the recent UI/customer fixes. A fresh
  Windows/Web playtest was exported and published on 2026-10-12; details below.

## Shared playtest — 2026-10-12

- User asked to let friend Jay (Discord yj4101) play/test the game and UI, via
  a website link or game file, and explicitly authorized a Discord DM as an
  alternative. No Discord messaging tool/connected plugin was available;
  plugin discovery found no Discord integration. No DM was sent.
- Browser game: https://artifacts-pawn-shop-playtest-syrins.heartyokapi128.chatgpt.site
  Sites audience is public (anyone with URL) for the requested friend playtest.
  Preserve this audience on future updates. Site project_id:
  appgprj_6acbec05f3488191963d85c1c35ecce8
- Local Site checkout (separate from the Godot project):
  C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/sites/artifacts-pawn-shop-playtest
  Identity is in its .openai/hosting.json; reuse it instead of creating a new Site.
  Latest polish source commit: fa3c98efc011e91b99a4e37d752a5426c0fee2da
  Saved version: appgprj_6acbec05f3488191963d85c1c35ecce8~appgver_c52c8a2434b88191a250862887cba91d
  Successful deployment: appgdep_6acc4266a2548191919f33fad0661a4d
- Web export is single-threaded, Compatibility/WebGL2. The 45.5 MB game PCK
  is gzip-compressed to 13.8 MB; the 39.5 MB WASM engine to 10.2 MB. The narrow
  wasm-loader.js fetch wrapper decompresses only index.wasm/index.pck before
  Godot reads them. Both roundtrips and browser loading/UI were verified.
  After New Game, click the canvas to enable mouse look. Keyboard/mouse required.
- Windows package (embedded PCK; Godot/installer not required):
  C:/Users/Syrins/Documents/Codex/2026-10-10/hee/outputs/Artifacts-Pawn-Shop-Polished-Windows-2026-10-12.zip
  Extract then open Windows/ArtifactsPawnShop.exe. Includes short controls guide
  and Godot/Alice licenses. ZIP ~53.3 MB; executable ~154.7 MB.
  ZIP SHA256: AF1C6927DF74D9DB20236607E712E3325D5931EB06098E5CFEC03B7774E7C070
  EXE SHA256: 4A6B3094E81323CF30619A845DBE94CD59EDF0976B27D93907683BF7C8230FFF
- Checked native release startup without project/editor dependencies. A GPU
  harness loaded resources from the exported EXE/PCK and passed 27 checks for
  New Game, settings, current Shop Management/cards, cleaning, bargaining, and
  packaging. Screenshots inspected. Local browser checked main menu, New Game,
  stock, computer shop, and pause with zero runtime/network errors. OS pointer capture
  remains a manual browser playtest check. ZIP's executable hash matches the
  checked EXE. Native Sites status confirms the public deployment succeeded.
- Sites helper Windows detail: add C:/Program Files/Git/bin to PATH for bash;
  set TAR_OPTIONS=--force-local so GNU tar accepts C:/ archive paths. Credentials
  remain in session memory/stdin only; obtain a fresh source write credential
  through Sites when updating later. No credentials are saved in the checkout.

## Cleaning and six-star rating — playable prototype

- Accepted decisions: cleaner shops get better offers; messy start followed by
  occasional new mess; rejected broom remains available to buy later.
- The cleaning PDF's white arrows describe tool movement, not drawn world art.
  User confirmed eight seconds per mess, four rubbish piles per bag, and a
  dumpster waypoint that remains visible through walls.
- scripts/cleaning_state.gd holds persistent mess and per-mess progress, mop
  dirt/washing progress, bag contents, dust ages, broom availability, and spawn
  schedule. GameState owns and saves it in version 2;
  Random per-mess Y rotation persists; older records derive a stable angle
  from their ID. Earlier saves get defaults without losing their economy/stock. Saves remain
  sleep-only. Hands are transient and never restore holding a cleaning tool.
- scripts/cleaning_manager.gd / scenes/cleaning_world.tscn handle world targets,
  tool models, markers, carrying, prompts, and initial/daily dirt. DayManager
  creates the scene under Main after stock/furniture restoration.
- Initially 3 rubbish + 2 spills + counter dust (six messes, three stars).
  Rating = clamp(6 - ceil(mess count / 2), 0, 6); all-clean = six stars.
  Twelve-mess cap. Floor mess appears every 80–140 game minutes while the shop
  is open, on an unoccupied marker. Paused clocks/closing stop its progression.
- Current gentle tuning: 1% offer bonus per star, maximum 6%. Rating is sampled
  on arrival: normal seller asks/floors fall, buyer offers/budgets rise, rounded
  to whole G. Buyer prices retain rarity caps. Opening broom is exempt and
  always asks 20 G. Existing negotiations do not change halfway through.
- Broom cleans rubbish; mop cleans spills; feather duster cleans shelf dust.
  Current Interact key (default E) picks up a tool and starts held-key cleaning.
  Aim at the mess to start within 2.2 m. After starting, hold E and freely look
  around. Release E, move beyond 2.2 m, pause, or press Q to stop; each mess
  retains its own unfinished progress, including through sleep saves. Partial
  cleaning consumes no mop use or bag capacity. Wrong tools leave dirt intact.
  Active cleaning blocks T waiting. Tools move from the camera to the active
  spot: broom/mop rotate back and forth, feather duster sweeps sideways. They
  return to the camera when paused or finished.
  Mop works on four spills, then blocks further spill cleaning until washed
  while held at MopWashSpot. Washing also uses an eight-second hold and resumes
  unfinished washing. Mop head is brown after the second use, dark after the
  fourth, and clean after washing; optional used/dirty model slots override tint.
- Each finished rubbish pile adds one quarter to the trash bag at TrashBagSpot.
  Four piles fill it and block more sweeping. Put away the broom, carry the bag
  with E, then E at DumpsterSpot empties it and releases the player's hands.
  Partly filled bags may also be emptied. Bag models grow with capacity; the
  bag size indicates fill. Q returns a carried bag to its home without emptying.
  A bobbing dumpster arrow appears when the bag is full or being carried;
  another points to the toilet when the mop has four uses. No distance text.
  They draw in the viewport above world geometry, so walls cannot hide them;
  offscreen/behind-camera targets get an arrow clamped inside the screen.
- Mop and feather duster start owned. Their world homes are MopSpot (toilet)
  and DusterSpot (bedroom table), snapped to real support surfaces. All supplied
  cleaning GLBs and Trashbag.fbx are connected in cleaning_world.tscn. Bag home
  falls back beside BroomSpot when TrashBagSpot is absent. Drink liquid material
  SpilledDrink varies water/coffee/juice; the current mop head material is mop
  (Wood/Broze handles stay unchanged). Dirty attempt says Too dirty! Wash the
  mop inside the toilet with a short camera shake. Full bag feedback says
  Take the trash out first. qaure.pdf supplies the cleaning motion/fill reference.
- Broom's special ArtifactData.tool_id is "broom". Purchasing it records a paid
  transaction and permanent equipment ownership, not resale inventory. It
  still appears as a Common artifact during the second visitor's presentation.
  BroomSpot permits a 20 G fallback purchase after the offer, including later
  days. Duplicate purchases are rejected. No automatic free broom grant.
- Shared hands limit: one cleaning tool OR one artifact/furniture. Tool models
  follow player camera with movement bob and mouse sway; Holding text is hidden.
  A trash bag uses the same hands limit. Q first pauses active cleaning;
  otherwise it returns a tool/bag home or cancels artifact/furniture placement.
- Dust is per furniture/shelf, not per artifact. Counter and bought furniture
  collect dust three days after discovery/last dusting; moving furniture carries
  its dust with it. No artifact value/status penalties. Existing imported shelves
  need a node/marker in cleaning_surfaces if their mesh is merged with the shop.
- Markers in Main named RubbishSpot* or SpillSpot*, or placed in groups
  rubbish_spots/spill_spots, override the temporary floor points. Stable marker
  names identify occupancy/saves. Tool marker names: BroomSpot, MopSpot,
  DusterSpot, MopWashSpot, TrashBagSpot, DumpsterSpot. User aliases TrashSpot*,
  TrashDrink*, MopCleanerSpot2/MopCleanerSpot and Dumbster spot are recognized.
  User markers take precedence over fallback children. Additional shelf surface
  nodes: cleaning_surfaces. Actual Toilet and Dumpster meshes supply padded
  interaction bounds; no duplicate placeholder art is added to those meshes.
- Root CleaningWorld exports three rubbish model slots and spill/dust/broom/
  mop/feather-duster PackedScenes, optional used/dirty mop variants, trash-bag
  model array (four fill stages, or one scaled model), and dumpster model.
  Current base mop head material is mop; MopHead materials are also recognized.
  Missing models use explicitly temporary shapes.
  Broom presentation also uses the exported broom model when provided.
- CleaningVisual normalizes offset GLB/FBX origins, caps floor mess width at
  0.75 m and tool height at 1.2 m; bag fits 0.65 m tall / 0.52 m wide then grows
  with load. Materials are duplicated/cached by source, state and held depth.
  Keep that cache: freeing replaced imported overrides each frame caused GLES
  null-material errors. Held depth is enabled only while attached to the camera.
- ui/cleaning_hud.tscn is an editable scene with HoldingLabel, Prompt,
  CleaningProgress/ProgressLabel/ProgressBar, and DumpsterIndicator with arrow
  and distance. scripts/cleaning_hud.gd updates the eight-second white rounded
  bar and waypoints; cleaning_manager owns the instance. Layer 6, mouse ignored.
  HoldingLabel, ProgressLabel and distance are retained but hidden. Only the
  white rounded bar shows while cleaning. cleaning_target now creates a world
  Label3D with artifact font size 32/pixel_size 0.0026, above the tool/mess.
  Broom, Feather duster, Mop (N/4), Trash bag (N/4) appear above E; full states
  explain disposal/washing. Wash/mess uses Hold E. Legacy HUD Prompt stays blank.
  InteractionCollision is addressed by name rather than fragile child indices.
  Tab toggles the bottom control hint along with InfoPanel; a visible bargain
  book retains its own Tab hide animation. Day-start toast is simply Day N.
- Stock menu heading is "Shop Management"; original node/file names stay stable.
  RatingStars is beside the heading. CleanlinessRating is a separate editable
  Label above the stock scroll area; its N/6 value retains the original line.
  The supplied Book.glb is the physical counter interaction model. Roomba is
  a 2500 G automatic upgrade with 20-second shared-progress cleaning; see the
  implementation section. User supplies final art and mesh/marker positions.

## Updated shop geometry and doors — 2026-10-12 polish

- Saved the user's previously unnamed/unsaved inherited shop as
  assets/Scene/shop_updated.tscn, preserving their authored counter/wall shapes.
  Main references this scene. Its Shop transform is
  (0.4142778,-0.048514843,-2.0666895), including the user's latest adjustment.
- Attached scripts/shop_runtime.gd derives horizontal mesh support patches and
  fills missing static collisions (including the user's Celing spelling).
  It supplies entrance ground beyond the front threshold for visitor routes.
- Front Door_001 and back Door get independent proximity_door controllers.
  Both reuse original DoorFront_Open/DoorBack_Open clips from the old shop.tscn;
  the old scene is retained as the animation source. Within 1.65 m they open
  for player, visitors, or intruders; they close after 0.8 s clear. Day/night
  scripted front-door requests use the same controller. Mesh art is unchanged.
- Door AnimatableBody sync_to_physics=false plus physics-mode animation fixes
  the collision remaining at the closed position while the visual swings open.
  The later closed-door sideways push was fixed by disabling leaf collision
  while it swings and restoring its original layer/mask when fully closed.
  Actual approaches to both doors now pass from both sides, without changing
  walls, artwork or the player capsule. Static open-door checks alone do not
  replace passage-while-opening coverage.
- NPC1 recolours Body/Cape/Hair surfaces; NPC2 Head/Tail share a hair colour;
  NPC3 shirt/hair use palette masks, preserving skin and lower-body clothes.
  customer_appearance accepts optional hair_index for deterministic previews;
  otherwise picks from six natural hair colours independently of clothing.
- Black crown/fish metal was caused by missing reflections, not missing albedo:
  the crown's gold material is metallic 1. Main WorldEnvironment now has a
  soft ProceduralSky and Reflected Light Source = Sky (enum 2). The audit fix
  pass also reduced excessive warm light/fog and added neutral ambient contrast.
  GPU captures confirm visible gold; other dark materials need individual review.

## Current fix validation — 2026-10-13

- integration_fix_test.gd: 66 GPU checks, zero failures. Covers real rent/shop
  controls, capital guard, all three game-over sizes, support for the supplied
  book, NPC heights/running clip, moving doors both ways, stolen findings for
  gold and non-gold, rebound F prompts, single-target dust/artifact interaction,
  dynamic/failed routes, physical T skip, robot purchase/navigation/work/save,
  police/demons, interrupted closing dialogue, unobscured police-goblin framing
  and actual imported Idle looping during bargaining/Running on departure.
- Existing suites: debug 53, menu 98, cleaning 273, gameplay 177, placement 277,
  outlines 783; night tests passed. Fixture expectations now reflect starting
  clock/radio, thirteen cards and event/customer heights. No blanket scene
  regeneration. Debug/integration helpers flush dummy audio before quitting.
- Full-play-loop JSONL/log show the actual Day 1 to Day 6 integrated UI loop,
  800 G rent payment through the authored button and matching Continue state.
  One normal-speed first resale at 1:48 is a scripted measurement; remaining
  days ran at 8x with assisted positioning. Audio was not listened to.
- Evidence and preservation manifest: chat work/fix-pass-2026-10-13. Real
  profile files remain unchanged; the existing user editor is left running.
  Existing UI image files were retained; added previews are separate assets.

## Earlier debug validation — 2026-10-13, before audit fixes

- debug_regression_test: 53 GPU checks passed, including held-E looking away,
  distance cancellation/resume, every tool label/capacity/full hint, real door
  passage, equal bargain buttons, visible hide icon at three window sizes,
  live bargain clock, hair/cape/tail palettes, smooth diagonal movement,
  slower arrivals, reflections and Inspector music filename/volume/ticker.
- Cleaning 273, menu scenes 92, prior polish 53 GPU, gameplay 177 checks pass.
  Counts in the mixed visitor test vary with generated transactions.
- GPU previews in chat outputs/previews/Debug-2026-10-13-* show new prompts,
  readable gold crown, aligned buttons, full reveal icon, customer palettes and
  menu ticker. Test saves/settings use isolated APPDATA profiles.
- Main/BedSleep follows Mattress; E at night uses the existing sleep/save logic.
  Actual player rays to bed/toilet/bin and the back doorway were verified.

## Latest polish validation — 2026-10-12

- GPU polish_test: 53 checks, zero failures. Includes imported cleaning models,
  actual markers/stations, FIFO queue, browsing/closing, doors, support patches,
  dirty mop feedback, resumed washing, bobbing arrows, Tab hiding and bed target.
- Cleaning: 273; gameplay: 180; menu scenes: 92; GPU placement: 277 checks pass.
  Night-event regression passes with cleaning tools protected from demon theft.
  Existing inherited GameOverMenu-child warnings are unrelated.
- Offscreen GPU captures show real broom/mop/bag, clean progress-only UI, actual
  backroom bed and open door, and three queued visitors plus one browsing.
- Exported Windows embedded pack: 27 checks passed, including latest shop,
  cleaning FBX, doors, crowd, menus, bargaining and bed. Actual release starts
  independently of editor/project. Browser main menu/New Game/stock/shop/pause
  pass with zero runtime or network errors. Browser pointer lock needs manual
  click/playtest; the headless check does not request it.

## Historical validation before this fix pass

- Latest menu_scene_test.gd: 92 checks passed, including all standalone shop
  cards, save/reload retention, in-game card details, controls and purchases.
- Day 1 gameplay checks exercise buying, pricing, same-day selling, continuous
  mixed visitors, exactly one Uncommon seller, and skipping the customer gap
  through T while the stock book is open. Latest gameplay_test.gd: 180 checks
  passed. Latest economy_test.gd: 2686 checks passed. Menu tests remain 92
  passing checks, using the current shop shortcut instead of deleted footer UI.
- Cleaning test: 273 checks passed headless; 276 checks passed on GPU with
  actual held-E input, pointer lock, and a real physics ray.
  Covers four-use mop, wrong tools, bounded mess, saved dirty state, old-save
  migration, broom fallback, dust age, legal offer bonuses, shared hands,
  interrupted/resumed eight-second cleaning and washing, saved bag capacity,
  carry-to-empty disposal, and through-wall/offscreen dumpster arrows.
  Actual main GPU previews show the white half-filled bar, rotating tool,
  carried full bag, wall-visible waypoint, and dirty/washed mop. Current gameplay
  (181) and menu (92) checks also passed after the cleaning changes; no script
  errors. Existing inherited GameOverMenu-child warnings remain unrelated.
- Standalone shop GPU screenshot and empty error log verified 2026-10-11.
- Tests that write settings/saves require isolated APPDATA/LOCALAPPDATA.
- GPU capture helpers run hidden/offscreen. Never terminate the user's editor.
- Artifact outline test: 783 checks passed across 39 catalog models x 5 rarities,
  including saved rarity, original assets, unchanged bounds, and furniture/ghost
  exclusions. GPU checks confirm each tier visibly draws an outline and SSR
  visibly changes colour over time. Outline gallery render has no errors.
- Actual-shop GPU capture also passed with a placed SSR crown. Existing
  GameOverMenu inherited-child warnings are unrelated to outlines. Existing
  dark metal/lighting appearance remains part of the artifact polish backlog.
