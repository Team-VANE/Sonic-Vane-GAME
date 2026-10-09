# LS5Framework


## ------------------------------

## MOVEMENT ---------------------

## ------------------------------


## Player movement input vector:

Player movement input is handled in `Scripts/Player/SonicPlayer.gd`.

The raw movement vector is built in `_read_input()`. The method reads the signed action axes for `move_left` / `move_right` and `move_back` / `move_forward` through `SettingsManager.get_signed_action_axis()`, then stores the result as `_move_input`.

`_move_input.x` is left/right input and `_move_input.y` is back/forward input. Keyboard and gamepad are read separately. Keyboard uses no deadzone, while gamepad input uses the configured stick deadzone through the settings manager. The stronger of the keyboard vector and gamepad vector wins for that frame. If the result is longer than `1.0`, it is normalized so diagonal input is not stronger than straight input. Tiny values below `0.001` are cleared to `Vector2.ZERO`.

Movement input can be cleared before it reaches movement code when input should not control the player. This happens when the local player is not the network authority, the game is paused, UI input is blocked, spring movement is locked, automation locks movement, a race countdown is active, or if the player's controls are influenced by any other object or system. Hurt state does not clear input, but scales it by `hurt_input_influence`.

The 2D `_move_input` is converted into the 3D `_move_direction` in `_compute_move_direction()`:

```gdscript
var dir := forward * _move_input.y + right * _move_input.x
```

`forward` and `right` come from `_control_forward` and `_control_right`, which are updated earlier by `_update_control_basis()`. This means the input vector itself stays simple and device-relative, while the control basis decides what "forward" and "right" mean in world space.

## Loop and inverted surface input:

Loop and inverted-surface input is handled by changing the control basis before `_move_input` is converted to `_move_direction`.

During movement, the player compares the current surface normal against `Vector3.UP`. The angle is `0` degrees on flat floor, about `90` degrees on a wall or loop side, and about `180` degrees on a ceiling. If the angle reaches `loop_input_steep_angle_deg`, `_loop_sticky` becomes active and the surface is treated as loop-like. Once active, it stays active until the angle drops below `loop_input_steep_angle_deg - 15.0`. This hysteresis prevents control mode flicker around the threshold.

When attached to a loop-like surface, the movement code calls:

```gdscript
_update_control_basis(physics_up, is_attached, is_loop_surface, lateral)
_compute_move_direction()
```

`physics_up` is the character's current up direction, usually based on the surface the player is attached to. `_update_control_basis()` takes the camera's world-up forward/right frame and rotates it into the character-up frame with `PlayerMath.basis_from_to(Vector3.UP, character_up)`. After that, both axes are projected onto the plane perpendicular to `character_up`.

That projection is what makes input work while inverted. Pressing forward still means `_move_input.y > 0`, but the forward axis has been remapped onto the player's current tangent plane. On the side of a loop, forward/right are tangent to the wall. On the ceiling, the frame is rotated so controls stay relative to the character's inverted up direction instead of raw world-up.

After the basis is updated, `_compute_move_direction()` combines the same 2D input with the remapped 3D axes. The input vector is not flipped directly. The effective movement changes because `_control_forward` and `_control_right` are rotated from world-up controls into the character's current up frame.

`_loop_control_active` is set when the player is attached and the surface is classified as loop-like. It is used as a behavior flag elsewhere, such as state flags and turn behavior, but the main input-vector calculation remains:

```gdscript
_move_direction = (_control_forward * _move_input.y + _control_right * _move_input.x).normalized()
```

## In plain English:

The player does not use a separate "upside-down control scheme" when running on a wall or ceiling. The same stick or keyboard direction is kept, but the game changes the surface that direction is measured against.

On normal ground, pressing forward means "move forward across the floor." When the character runs onto a loop wall, the game starts treating the wall as the floor for movement input. Pressing forward then means "move forward across this wall." When the character reaches the ceiling, the ceiling becomes the movement surface, so pressing forward means "move forward across the ceiling."

This transition is based on the character's current up direction. On flat ground, the character's up direction points toward world up. On a wall, the character's up direction points away from the wall. On a ceiling, the character's up direction points downward compared to the world. The camera-relative controls are rotated into that changing character frame so the input follows the surface instead of staying locked to the world's floor.

The input itself is not reversed at the moment the character becomes inverted. For example, holding forward remains forward input the whole time. What changes is the meaning of forward because the character's "floor" has rotated. This is why a loop can feel continuous instead of suddenly swapping controls at the top.

Entry angle affects how the transition feels:

- Entering a loop straight on usually feels the cleanest. The character's forward direction and the loop surface are already lined up, so holding forward continues to carry the player around the curve.
- Entering from a diagonal angle can make forward input aim diagonally across the wall or ceiling. The control basis is still camera-relative, then projected onto the surface, so the final direction depends on both the camera angle and the angle where the character attached to the surface.
- Entering sideways can make left/right input feel more important, because the surface tangent does not line up with the camera's forward direction. The game still projects controls onto the wall or ceiling, but the resulting movement direction may not match the visual centerline of the loop.
- Entering near the loop threshold can feel different from entering a fully vertical or inverted section. Loop mode turns on when the surface angle reaches `loop_input_steep_angle_deg`, then stays on until the surface gets about `15` degrees flatter than that. This small buffer prevents rapid switching when the player is near the cutoff.

In short: the player keeps pressing the same direction, while the game rotates the meaning of that direction to match the surface the character is standing on. A straight entry makes that rotation feel natural. A diagonal or sideways entry can make the same input produce a more angled path across the wall or ceiling.

## ------------------------------