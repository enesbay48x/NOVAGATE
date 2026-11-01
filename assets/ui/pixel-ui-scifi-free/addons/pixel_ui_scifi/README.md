# Pixel UI Sci-Fi

A sci-fi pixel-art GUI and HUD skin for Godot 4.3+: colour themes as ready-made `Theme`
resources, item and ability icons, segmented bar fills, hexagonal gauges, a cooldown sweep, HUD
reticles, a cursor and a bitmap font. Every image is
also a plain PNG, with its 9-slice margins listed for any other engine.

**The full pack:** **[Pixel UI Sci-Fi](https://heyheythere.itch.io/pixel-ui-scifi)** has six neon themes (cyan, amber,
green, magenta, red and steel), 56 item icons (planets, aliens, robots, satellites, chips,
radar, keycards, credits, crystals, cargo, and a full menu set), 64 ability icons in eight systems,
four HUD reticles and the pieces a game's
screens need: menu lines, save slots, item slots with counts, key caps, switches, steppers,
toasts, portraits and nameplates. Same files and names: install it over this one.

## Use it in Godot

1. Copy `addons/pixel_ui_scifi/` into your project.
2. Project Settings:
   - *Rendering > Textures > Default Texture Filter*: **Nearest**, or the pixels blur.
   - *GUI > Theme > Custom*: `res://addons/pixel_ui_scifi/themes/cyan.tres` (or any theme), so
     every Control uses it. Or set `theme` on one Control and its children follow.
3. Draw the UI at a whole-number scale. The art is 1x (the font is 8px tall), made for a UI about
   240 pixels high: set *Display > Window > Stretch > Mode* to `canvas_items` and either use a
   small viewport (for example 320x180 or 480x270), or keep yours and set
   `get_tree().root.content_scale_factor` to 2, 3 or 4, as `demo/demo.gd` does.

## Themes

Each `themes/<name>.tres` styles Button, OptionButton, CheckBox (check and radio), Label, Panel,
PanelContainer, LineEdit, HSlider, ProgressBar, TabContainer, PopupMenu, tooltips, scroll bars and
HSeparator. Set `theme_type_variation` for the extras:

| Variation | On | Looks like |
|---|---|---|
| `WindowPanel` | PanelContainer | a window with a title bar; its first line of content sits in the bar |
| `Title` | Label | the text for that title bar |
| `InsetPanel` | PanelContainer | a sunken slot, 24x24 around a 16px icon |
| `BracketPanel` | PanelContainer | corner brackets only, for HUD frames and targets |
| `RedBar`, `GreenBar`, `BlueBar`, `GoldBar` | ProgressBar | hull, stamina, shield and energy fills |
| `SkillSlot`, `ActiveSkillSlot` | PanelContainer | a 20x20 frame round a 16px ability icon; the active one lit |
| `CommonSlot`, `UncommonSlot`, `RareSlot`, `EpicSlot`, `LegendarySlot` | PanelContainer | a 24x24 item slot rimmed in its rarity's colour |
| `MenuItem` | Button | a line of a menu: its band and pointer show when hovered or pressed (`toggle_mode` keeps one picked) |
| `SaveSlot` | Button | a save or level slot for an icon and two lines, lit when picked |
| `ItemSlot`, `ItemSlotSelected` | PanelContainer | a 24x24 slot round a 16px item, and the picked one |
| `Count` | Label | white shadowed text for a slot's corner: a stack's count, a hotbar key |
| `KeyCap` | Label | a key on its cap, for prompts and key bindings |
| `Nameplate` | Label | text on a plate, for a speaker's or an item's name |
| `PortraitPanel` | PanelContainer | a frame for a face or a big icon |
| `ToastPanel` | PanelContainer | a notice: an icon and a line |
| `StepLeft`, `StepRight` | Button | the arrows of a `< value >` stepper (no text) |

CheckButton is drawn as a toggle switch, a CheckBox's height, so a settings list can mix them.
The rows from `MenuItem` down and the switch are the game pieces of the full kit (the free sampler's
theme has none); `demo/demo.gd`'s menus and play screens put them together.

A window: PanelContainer (`WindowPanel`) > VBoxContainer > Label (`Title`) first, then the content.
The variation names are the same as in Pixel UI, so a project can switch between the two kits by
switching its theme.

## Gauges and cooldowns

A gauge is a TextureProgressBar: *Fill Mode* **Bottom to Top**, *Under* `themes/<name>/gauge.png`
(the hexagonal frame and its dark well, 32x28), *Progress* `bars/gauge_red.png` (or `_blue`,
`_gold`, 22x20) with *Progress Offset* (5, 4), and *Over* `bars/gauge_glass.png`.

A cooldown is a TextureProgressBar over an ability icon: *Fill Mode* **Clockwise**, *Progress*
`bars/cooldown.png`, its value the share of the cooldown left. `demo/demo.gd`'s `gauge()` and
`_action_bar()` build both.

## Icons

The icons are white with a dark outline, so they take any colour. A Button tints its `icon` with
the theme's colours by itself. Anywhere else, set `self_modulate`, for example to the theme's
`icon_normal_color` of `Button`, as `demo/demo.gd`'s `tint` does. `icons/_sheet_<theme>.png`
has them all already tinted, on one 8-column sheet per theme.

`icons/abilities/<system>_<ability>.png` are coloured, framed chips, not tinted: every ability
(beam, burst, barrier, repair, boost, drone, mine, scan) in every system (laser, plasma, ion, cryo,
nano, cyber, gravity, psi), and `icons/abilities/_sheet.png` has them all, a system to a row.

## Other engines

Every part is a PNG in `themes/<name>/`. `themes/slices.json` lists each one's 9-slice borders
(left, top, right, bottom, in pixels; the same in every theme):

| Parts | Borders |
|---|---|
| `button_*`, `focus`, `panel`, `line_edit` | 4, 4, 4, 4 |
| `window` | 6, 12, 4, 4 (the title bar is the top 11 rows) |
| `bracket` | 5, 5, 5, 5 |
| `panel_inset`, `tooltip`, `progress_bg` | 3, 3, 3, 3 |
| `slider`, `slider_fill` | 3, 1, 3, 1 |
| `progress_fill`, `bars/bar_*` | 2, 3, 2, 2, with the middle **tiled** horizontally, not stretched, so it draws segments |
| `tab_selected` | 4, 4, 4, 1 |
| `tab_unselected`, `tab_hover` | 4, 5, 4, 2 |
| `scroll*`, `menu_hover` | 2, 2, 2, 2 |
| `slot_selected`, `skill_slot*`, `slot_<rarity>` | 3, 3, 3, 3 |
| `key` | 4, 3, 4, 4 |
| `nameplate` | 4, 3, 4, 3 |
| `portrait` | 6, 6, 6, 6 |
| `toast` | 5, 4, 4, 4 |

The rest are drawn as they are: `checkbox_*` and `radio_*` (9x9), `switch_*` (19x9), `grabber*`
(5x9), `arrow` (the option button's, 7x4), `pointer` and `step_*` (4x7), and `gauge` (32x28).

## Files

- `themes/<name>.tres` and `themes/<name>/*.png`: the Theme and its parts.
- `icons/*.png`: 16x16, white, outlined, on a transparent background; `icons/abilities/*.png`:
  16x16, coloured.
- `bars/bar_*.png`: the bar fills; `bars/gauge_*.png` and `bars/cooldown.png`: the gauge's fills and
  glass, and a cooldown's shadow.
- `hud/reticle_*.png`: 16x16 crosshairs, white like the icons.
- `cursor.png` and `cursor_2x/3x/4x.png`: a mouse pointer, hotspot at the top-left pixel. The OS
  draws cursors unscaled, so pick the copy that matches your UI scale for *Display > Mouse Cursor >
  Custom Image*.
- `font/pixel_ui_scifi_font.fnt`: a proportional BMFont with all printable ASCII, 8px glyphs on a
  10px line. Keep it at size 8 and scale the UI instead.
