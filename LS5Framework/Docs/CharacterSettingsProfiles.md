# Character Settings Profiles

Character settings profiles separate physical controls, packaged character defaults, and user overrides.

- Input Map actions `ability_slot_01` through `ability_slot_16` are generic physical slots configured in Controls.
- A `CharacterSettingsProfile` lists the character's modular abilities and default slot assignments.
- User changes are saved to `user://character_profiles.cfg` and do not modify the character package.

## Character package setup

Create a `CharacterSettingsProfile` resource in the character package and set a stable `package_id` and `character_id`. Each ability listed in `ability_catalog` must use the same `ability_id` as its action node's `action_id`.

Each `default_loadout` entry supports:

- `ability_id`: Stable modular action identifier.
- `slot`: Generic Input Map action.
- `gesture`: `press`, `tap`, `hold`, or `release`.
- `hold_time`: Tap window or hold duration in seconds.
- `allow_shared`: Suppresses conflict warnings for intentional shared bindings.
- `modifier_ability_id`: Ability whose assigned slot acts as the hold modifier.
- `modifier_slot`: Fallback modifier slot.
- `modifier_bypasses_hold`: Activates a hold ability immediately while the modifier is held.

List the gestures supported by each ability in its `ability_catalog` definition. The settings menu only offers those activation modes.

Assign the profile to both the character's `CharacterDoc.settings_profile` and the player scene's `character_settings_profile`. The catalog uses the document profile for the menu, while the player scene uses it for runtime input resolution.

## Profile updates

User loadout changes are stored as per-ability overrides. New abilities and updated defaults from a newer character package continue to merge into an existing user profile. Increment `profile_version` when packaged defaults or settings definitions change so migrations can be added without changing the stable profile key.

Character-specific settings can use `default_settings`, `CharacterProfileManager.get_effective_settings()`, and `CharacterProfileManager.set_character_setting()`. These values share the same per-character persistence namespace as the loadout.

## Action routing

`default_routes` defines packaged transitions with stable action identifiers instead of scene paths. User changes and user-created routes are stored with the character profile, so editing a route never modifies or repackages the character.

Set `routes_authoritative` when a character's packaged route list fully replaces its scene-local routes. Leave it disabled for compatibility profiles that still depend on `AbilityRoute` resources or NodePath fallbacks.

Each route supports:

- `route_id`: Stable identifier for merging packaged defaults and user overrides.
- `display_name`: Name shown in the Action Routing menu.
- `source_action`: Action that owns the transition.
- `event`: `ability_triggered`, `input_pressed`, `input_held`, `input_released`, `manual`, `completed`, or `policy`.
- `input_ability`: Ability whose current loadout assignment supplies the input. If omitted, the source action's assignment is used.
- `input_action`: Optional fixed Input Map action for inputs outside the ability slots.
- `target_action`: Stable `action_id` of the routed action.
- `activation`: `execute`, `activate`, `toggle_on`, `neutral_air`, or `clear_active`.
- `required_state`: `any`, `grounded`, or `airborne`.
- `priority`: Evaluation order when more than one route matches.
- `enabled`: Allows packaged routes to be offered as optional behavior.
- `consume_input`: Stops normal action dispatch after a successful input route.
- `block_during_race_countdown`: Prevents the route during the race countdown.
- `allowed_source_actions` and `blocked_source_actions`: Optional source filters used by policies and specialized transitions.

`ability_triggered` evaluates the selected ability's configured gesture and hold window. Raw input events are useful for transitions such as Bounce input release to Stomp. Because `input_ability` resolves through the current loadout, those routes continue to work when the user moves the source ability to another generic slot.

Actions can publish modular lifecycle events with `emit_profile_route_event()`. Spindash publishes `completed` after a normal release. The Sonic and Tails profiles include a disabled `Spindash Completion: Toggle Roll` route that users can enable from Action Routing.

Packaged manual routes retain the identifiers expected by their actions. For example, Spindash requests `spindash_jump`, while Spin Kick requests `coyote_jump` or `no_coyote_jump`. Profiles with matching route IDs are authoritative; the scene-local `AbilityRoute` resources remain as compatibility fallbacks for characters without profile routing.
