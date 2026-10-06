# Legacy Drift Speed Logic Backup

The active drift implementation was replaced by the arcade drift model in `drift_action.gd` and `SonicPlayer.gd`.

The previous speed and acceleration model used:

- `drift_forward_accel_boost` multiplied by `drift_forward_boost_t`.
- `drift_top_speed_offset` multiplied by `drift_forward_boost_t`.
- `drift_back_brake` multiplied by `drift_back_t`.
- `drift_turn_forward_scale` and `drift_turn_back_scale` selected from input angle bands.
- `drift_turn_curve` / `drift_turn_deg_per_sec` for turn rate.
- `drift_turn_max_curve` / `drift_turn_max_deg_per_sec` for turn caps.
- `drift_turn_back_max_scale` for extra turn cap while pulling backward.

`drift_action_legacy.gd` keeps the old action exports and state behavior. The older player-side movement logic is also present in `SonicPlayer.gd.flight_math_backup_20260605`.
