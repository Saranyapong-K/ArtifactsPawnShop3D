# Editable menu scene trees

Your project is at `C:/Users/Syrins/Documents/artifacts-pawn-shop`.

In Godot's FileSystem dock, open `ui/stock_menu.tscn`, `ui/shop_menu.tscn` and `ui/bargain_menu.tscn` to edit the new reference layouts. These use the supplied `assets/UIs` artwork. The PDF's red notes and arrows are omitted; its blue arrows become hide animations.

Stock uses a parchment book with a fixed heading and scrolling artifact rows. Only the price box being edited shows a value. Click to edit, Enter to save, and Escape to cancel without changing the saved price. Invalid entries become 1 G; a valid 0 G still keeps an item off sale. Changing rows or closing the stock book cancels the active draft. Rarity outlines use brown, green, blue and purple; SSR names use several colours, with gold rarity and yellow size text. Longer names wrap, with cost on a separate line.

Uninspected artifacts display Normal even when they have a hidden status. Buy and use the magnifying glass or curse detector buttons to record a finding for that artifact. Tool ownership alone reveals nothing. Inspection is available during bargaining and in stock. Findings survive sleep saves and scene reloads. Stolen gold requires both magnifier inspection and the daily newspaper's theft report.

Shop uses the supplied Alibaboon desktop wallpaper, a fixed wallet/search header, and scrolling equipment/furniture cards. Search filters both sections. Buy actions use the existing economy prices and real records, rather than the illustrative furniture names/prices in the PDF. Furniture cards use the supplied furniture icon. The window's X and minimize buttons close the shop; its maximize button toggles its size. The existing Close, Stock, rent, Wait and Sleep actions remain available.

Bargain uses the one-page book and textured Offer / Accept / Reject buttons. The round toggle button and Tab slide the book down and the bargain flag up. A round button stays at the bottom to restore both. The customer remains visible above the book, and the action buttons are clear of the control hint.

Settings now follows the open-book reference: Gameplay and Sound share the two visible pages, with a separate Key Mapping page. The clock-colour dropdown offers White, Cream, Gold, Brown, Black and a custom colour picker. Esc returns from Key Mapping to Settings, then closes the book and restores gameplay. Existing saved settings are preserved; sensitivity is displayed as a percentage of its supported range.

The scenes are already connected to the game. The main menu is `main_menu.tscn`. Gameplay loads the Settings scene, `ui/game_ui.tscn` (Stock / Shop / Game Over), and `ui/bargain_interface.tscn` (Bargain / Dialogue / Price / Receipt / Day Summary).

## Editing artwork and layout

- Panel background: assign a texture to `PanelArtwork`. For a skin covering the entire panel border, set the parent PanelContainer's **Theme Overrides → Styles → Panel** to a **StyleBoxTexture**, assign your image, and keep the content margins so controls stay inside it.
- Settings book: edit `BookArtwork` to replace the existing book image. `BookFrame` preserves its aspect ratio, and the Gameplay / Sound controls use editable anchors over the pages. The shared settings font, slider and checkbox styles are in `ui/settings/book_theme.tres`. The backdrop blur is the material on `BackdropBlur`.
- Full result-screen background: assign a texture to `BackgroundArtwork` in the receipt, price-editor or day-summary scene.
- Button artwork: select a named Button and use **Theme Overrides → Styles** with StyleBoxTexture resources for Normal, Hover, Pressed, Disabled and Focus. On bargain / result buttons, turn **Flat** off to show the Normal style.
- Stock / bargain book: edit `BookArtwork` or `PanelArtwork`. The background is independent of the interactive controls. Stock's `Heading` and `Wallet` sit outside `Scroll`, so they stay fixed.
- Shop wallpaper: edit `BrowserArtwork` in `shop_menu.tscn`. The cards are under `Scroll/Catalog/Equipment` and `Scroll/Catalog/Furniture`. The card icons and sample text are saved in the scene and visible in the editor.
- Shared colours, fonts and button artwork: edit `ui/autumn_theme.tres`. Shop has its own `ui/shop_theme.tres` for its orange scrollbar. Settings retains `ui/settings/book_theme.tres`.
- Icons: assign textures to `ItemIcon` in `shop_item_card.tscn`. Shop cards are separate instances, so you can use **Editable Children** to assign a different icon to each item.
- Fonts, colours, spacing and sizes: edit the controls in the Inspector. Settings and Bargain no longer build their layouts or reset their font sizes in scripts.

Keep the named controls when changing the layout; their names connect them to gameplay. Labels showing prices, wallet, inspection results and dialogue receive live game data, so sample text is replaced while playing. The sample stock row is only an editor preview and is replaced by your actual inventory at runtime.

Day Summary and the Sell-price Editor inherit the receipt layout. You can override their artwork separately; shared changes to the base receipt layout also reach them.

Use F6 on Settings, `ui/bargain_interface.tscn` or `ui/game_ui.tscn` to preview their controllers. Use F5 to test the full game and menu actions. The individual layout scenes are also visible in the 2D editor. `game_ui.tscn` provides the modal and tint; its Menu Size property sets the maximum size while preserving the layout's aspect ratio. Stop and restart an already running Play session to load the new scenes.

## Scene files

| Menu | Open in Godot |
|---|---|
| Main menu | `res://main_menu.tscn` |
| Settings / pause | `res://ui/settings_menu.tscn` |
| Stock | `res://ui/stock_menu.tscn` |
| Online shop | `res://ui/shop_menu.tscn` |
| Bargain | `res://ui/bargain_menu.tscn` |
| Dialogue | `res://ui/dialogue_menu.tscn` |
| Sell-price editor | `res://ui/price_editor_menu.tscn` |
| Purchase / sale receipt | `res://ui/receipt_menu.tscn` |
| Day summary | `res://ui/day_summary_menu.tscn` |
| Game over | `res://ui/game_over_menu.tscn` |
| Credits | `res://ui/credits_menu.tscn` |
| Reusable stock row | `res://ui/stock_row.tscn` |
| Reusable shop card | `res://ui/shop_item_card.tscn` |
| Stock / Shop controller | `res://ui/game_ui.tscn` |
| Bargain / results controller | `res://ui/bargain_interface.tscn` |

## Scene trees

These trees are read from the saved scenes, including their inherited controls.

### Main menu

```text
MainMenu (Control)
├── FarLandscape (TextureRect)
├── TownAndLake (TextureRect)
├── ShopForeground (TextureRect)
├── SceneTint (ColorRect)
├── Margins (MarginContainer)
│   └── MenuContent (VBoxContainer)
│       ├── Title (Label)
│       ├── Tagline (Label)
│       ├── TitleSpacing (Control)
│       ├── NewGameButton (Button)
│       ├── ContinueButton (Button)
│       ├── OptionsButton (Button)
│       ├── CreditsButton (Button)
│       ├── ExitButton (Button)
│       ├── SaveHint (Label)
│       └── FooterSpacer (Control)
├── CreditsMenu (Control)
└── SettingsMenu (CanvasLayer)
```

### Settings / pause

```text
SettingsMenu (CanvasLayer)
└── Screen (Control)
    ├── BackdropBlur (ColorRect)
    ├── BookFrame (AspectRatioContainer)
    │   └── Book (Control)
    │       ├── BookArtwork (TextureRect)
    │       ├── SettingsPages (Control)
    │       │   ├── GameplayPage (Control)
    │       │   │   ├── GameplayHeading (Label)
    │       │   │   ├── SensitivityRow (HBoxContainer)
    │       │   │   │   ├── SensitivityLabel (Label)
    │       │   │   │   └── SensitivityValue (Label)
    │       │   │   ├── SensitivitySlider (HSlider)
    │       │   │   ├── FullscreenRow (HBoxContainer)
    │       │   │   │   ├── FullscreenRowLabel (Label)
    │       │   │   │   └── FullscreenToggle (CheckBox)
    │       │   │   ├── ClockColorRow (HBoxContainer)
    │       │   │   │   ├── ClockColorLabel (Label)
    │       │   │   │   └── ClockColorSelector (OptionButton)
    │       │   │   ├── KeyMappingButton (Button)
    │       │   │   └── Actions (HBoxContainer)
    │       │   │       ├── MainMenuButton (Button)
    │       │   │       └── QuitButton (Button)
    │       │   └── SoundPage (Control)
    │       │       ├── SoundHeading (Label)
    │       │       ├── MasterRow (HBoxContainer)
    │       │       │   ├── MasterLabel (Label)
    │       │       │   └── MasterValue (Label)
    │       │       ├── MasterSlider (HSlider)
    │       │       ├── MusicRow (HBoxContainer)
    │       │       │   ├── MusicLabel (Label)
    │       │       │   └── MusicValue (Label)
    │       │       ├── MusicSlider (HSlider)
    │       │       ├── SfxRow (HBoxContainer)
    │       │       │   ├── SfxLabel (Label)
    │       │       │   └── SfxValue (Label)
    │       │       ├── SfxSlider (HSlider)
    │       │       ├── MuteRow (HBoxContainer)
    │       │       │   ├── MuteRowLabel (Label)
    │       │       │   └── MuteToggle (CheckBox)
    │       │       └── RadioNameRow (HBoxContainer)
    │       │           ├── RadioNameRowLabel (Label)
    │       │           └── RadioNameToggle (CheckBox)
    │       └── KeyMappingPage (Control)
    │           ├── MovementHeading (Label)
    │           ├── ShopActionsHeading (Label)
    │           ├── MovementKeys (VBoxContainer)
    │           │   ├── MoveForwardRow (HBoxContainer)
    │           │   │   ├── MoveForwardLabel (Label)
    │           │   │   └── MoveForwardKey (Button)
    │           │   ├── MoveBackRow (HBoxContainer)
    │           │   │   ├── MoveBackLabel (Label)
    │           │   │   └── MoveBackKey (Button)
    │           │   ├── MoveLeftRow (HBoxContainer)
    │           │   │   ├── MoveLeftLabel (Label)
    │           │   │   └── MoveLeftKey (Button)
    │           │   ├── MoveRightRow (HBoxContainer)
    │           │   │   ├── MoveRightLabel (Label)
    │           │   │   └── MoveRightKey (Button)
    │           │   ├── SprintRow (HBoxContainer)
    │           │   │   ├── SprintLabel (Label)
    │           │   │   └── SprintKey (Button)
    │           │   └── CrouchRow (HBoxContainer)
    │           │       ├── CrouchLabel (Label)
    │           │       └── CrouchKey (Button)
    │           ├── ShopKeys (VBoxContainer)
    │           │   ├── InteractRow (HBoxContainer)
    │           │   │   ├── InteractLabel (Label)
    │           │   │   └── InteractKey (Button)
    │           │   ├── InventoryRow (HBoxContainer)
    │           │   │   ├── InventoryLabel (Label)
    │           │   │   └── InventoryKey (Button)
    │           │   ├── ShopRow (HBoxContainer)
    │           │   │   ├── ShopLabel (Label)
    │           │   │   └── ShopKey (Button)
    │           │   ├── RotateItemRow (HBoxContainer)
    │           │   │   ├── RotateItemLabel (Label)
    │           │   │   └── RotateItemKey (Button)
    │           │   └── ToggleHudRow (HBoxContainer)
    │           │       ├── ToggleHudLabel (Label)
    │           │       └── ToggleHudKey (Button)
    │           ├── BindingHint (Label)
    │           ├── BackSettingsButton (Button)
    │           └── ResetKeysButton (Button)
    ├── ResumeButton (Button)
    ├── Heading (Label)
    └── ClockColorPicker (ColorPickerButton)
```

### Stock

```text
StockMenu (Control)
├── BookArtwork (TextureRect)
├── Heading (Label)
├── Wallet (Label)
├── Scroll (ScrollContainer)
│   └── Rows (VBoxContainer)
│       └── EditorSampleArtifactRow (HBoxContainer)
├── EmptyStock (Label)
└── Actions (HBoxContainer)
    ├── CloseButton (Button)
    ├── SwitchMenuButton (Button)
    ├── RentButton (Button)
    ├── WaitButton (Button)
    └── SleepButton (Button)
```

### Online shop

```text
ShopMenu (Control)
├── BrowserArtwork (TextureRect)
├── Wallet (Label)
├── SearchField (LineEdit)
├── Scroll (ScrollContainer)
│   └── Catalog (VBoxContainer)
│       ├── EquipmentHeading (Label)
│       ├── Equipment (GridContainer)
│       │   ├── Magnifier (Panel)
│       │   ├── CurseDetector (Panel)
│       │   ├── Clock (Panel)
│       │   └── Radio (Panel)
│       ├── FurnitureHeading (Label)
│       └── Furniture (GridContainer)
│           ├── DisplayShelf (Panel)
│           ├── OpenShelf (Panel)
│           ├── GlassCounter (Panel)
│           ├── WeaponRack (Panel)
│           ├── GlassCabinet (Panel)
│           ├── TallVitrine (Panel)
│           ├── CombinationCabinet (Panel)
│           └── Pedestal (Panel)
├── EmptySearch (Label)
├── Actions (HBoxContainer)
│   ├── CloseButton (Button)
│   ├── SwitchMenuButton (Button)
│   ├── RentButton (Button)
│   ├── WaitButton (Button)
│   └── SleepButton (Button)
├── WindowCloseButton (Button)
├── MinimizeButton (Button)
└── MaximizeButton (Button)
```

### Bargain

```text
BargainMenu (Control)
└── BargainPanel (Control)
    ├── PanelArtwork (TextureRect)
    └── BargainContent (Control)
        ├── AskingPrice (Label)
        ├── ReferencePrice (Label)
        ├── OfferControls (HBoxContainer)
        │   ├── Minus100Button (Button)
        │   ├── Minus10Button (Button)
        │   ├── OfferPrice (Label)
        │   ├── Plus10Button (Button)
        │   └── Plus100Button (Button)
        ├── OfferSlider (HSlider)
        ├── OfferButton (Button)
        ├── AcceptButton (Button)
        ├── RejectButton (Button)
        ├── InspectDamageButton (Button)
        └── InspectCurseButton (Button)
```

### Dialogue

```text
DialogueMenu (VBoxContainer)
├── TopSpacer (Control)
├── Center (CenterContainer)
│   └── DialoguePanel (PanelContainer)
│       ├── PanelArtwork (TextureRect)
│       └── DialogueContent (HBoxContainer)
│           ├── DialogueText (Label)
│           └── ContinueIndicator (TextureRect)
└── BottomSpacing (Control)
```

### Sell-price editor

```text
PriceEditorMenu (ColorRect)
├── BackgroundArtwork (TextureRect)
└── Center (CenterContainer)
    └── ResultContent (VBoxContainer)
        ├── ResultHeading (Label)
        ├── ResultValue (Label)
        ├── ResultDetails (Label)
        ├── NextButton (Button)
        ├── PriceRow (HBoxContainer)
        │   ├── SellPriceLabel (Label)
        │   └── SellPriceInput (SpinBox)
        └── SavePriceButton (Button)
```

### Purchase / sale receipt

```text
ReceiptMenu (ColorRect)
├── BackgroundArtwork (TextureRect)
└── Center (CenterContainer)
    └── ResultContent (VBoxContainer)
        ├── ResultHeading (Label)
        ├── ResultValue (Label)
        ├── ResultDetails (Label)
        ├── NextButton (Button)
        ├── PriceRow (HBoxContainer)
        │   ├── SellPriceLabel (Label)
        │   └── SellPriceInput (SpinBox)
        └── SavePriceButton (Button)
```

### Day summary

```text
DaySummaryMenu (ColorRect)
├── BackgroundArtwork (TextureRect)
└── Center (CenterContainer)
    └── ResultContent (VBoxContainer)
        ├── ResultHeading (Label)
        ├── ResultValue (Label)
        ├── ResultDetails (Label)
        ├── NextButton (Button)
        ├── PriceRow (HBoxContainer)
        │   ├── SellPriceLabel (Label)
        │   └── SellPriceInput (SpinBox)
        └── SavePriceButton (Button)
```

### Game over

```text
GameOverMenu (VBoxContainer)
├── Heading (Label)
├── Reason (Label)
├── CheckpointHint (Label)
└── MainMenuButton (Button)
```

### Credits

```text
CreditsMenu (Control)
├── Dimmer (ColorRect)
└── Center (CenterContainer)
    └── Panel (PanelContainer)
        ├── PanelArtwork (TextureRect)
        └── Content (VBoxContainer)
            ├── Heading (Label)
            ├── TeamCredits (Label)
            ├── ThankYou (Label)
            └── CloseButton (Button)
```

### Reusable stock row

```text
StockRow (HBoxContainer)
├── Details (VBoxContainer)
│   ├── ArtifactName (RichTextLabel)
│   ├── Cost (Label)
│   └── StatusRow (HBoxContainer)
│       ├── Inspection (RichTextLabel)
│       ├── InspectDamageButton (Button)
│       └── InspectCurseButton (Button)
└── PriceColumn (VBoxContainer)
    ├── PricePrompt (Label)
    ├── PriceStack (Control)
    │   ├── EditPriceButton (Button)
    │   └── ListingPrice (SpinBox)
    └── SavePriceButton (Button)
```

### Reusable shop card

```text
ShopItemCard (Panel)
├── ItemIcon (TextureRect)
├── ItemName (Label)
├── Description (Label)
├── Price (Label)
└── BuyButton (Button)
```

### Stock / Shop controller

```text
GameUI (CanvasLayer)
└── Screen (Control)
    ├── Toast (Label)
    ├── ControlHint (Label)
    ├── ScreenTint (ColorRect)
    └── Modal (Control)
        ├── GameOverBackdrop (TextureRect)
        └── Pages (Control)
            ├── StockMenu (Control)
            ├── ShopMenu (Control)
            └── GameOverMenu (VBoxContainer)
```

### Bargain / results controller

```text
BargainInterface (CanvasLayer)
└── Screen (Control)
    ├── BargainMenu (Control)
    ├── DialogueMenu (VBoxContainer)
    ├── ReceiptMenu (ColorRect)
    ├── DaySummaryMenu (ColorRect)
    ├── PriceEditorMenu (ColorRect)
    ├── BargainFlag (TextureRect)
    └── TogglePanelButton (Button)
        └── ArrowArtwork (TextureRect)
```

## Verification

124 gameplay checks and 42 menu checks passed, covering ongoing customers, buy/sell transactions, inspection persistence, price entry/cancel/validation, search, purchases, and hide/reveal controls. Rendered and visually inspected with the project's actual Compatibility renderer and GT 1030 at 1152 × 648, plus a 960 × 540 preview. No generated artwork was needed.
