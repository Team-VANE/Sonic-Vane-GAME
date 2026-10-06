# 2.5D Automation Spline

`AutomationSpline2_5D.tscn` is the 2.5D movement preset. The original
`AutomationSpline.tscn` remains the guided-centering preset for automated or
mostly automated paths.

## Movement model

The 2.5D spline builds a ribbon frame at the player's current path progress:

- Tangent: forward and backward travel along the path.
- Plane normal: the forbidden sideways or depth axis.
- Plane up: the remaining axis inside the movement plane.

Only position and velocity along the plane normal are constrained. Gravity,
jumping, surface attachment, slope acceleration, rolling, and loop handling
remain in the player's normal physics. Existing turning-radius behavior may
rotate velocity temporarily, then the final depth constraint removes the
out-of-plane part before collision movement.

Entry and exit adherence use arc-length distance from the beginning and end of
the curve. The middle of the curve reaches full adherence. Closed curves remain
fully adhered because they have no natural entry or exit endpoint.

## Basic setup

1. Instantiate `AutomationSpline2_5D.tscn`.
2. Edit its `Path3D` curve through the center of the playable section.
3. Size `Area3D/CollisionShape3D` to cover the complete active section, or use
   separate entrance and exit areas.
4. Enable Curve3D up vectors only when the 2.5D ribbon itself changes
   orientation. Terrain loops inside a stable ribbon do not require the curve
   to follow their vertical profile.
5. Adjust Entry Blend Distance and Exit Blend Distance to leave enough terrain
   for a smooth handoff.

The default input mode maps left and right to backward and forward path travel.
Reverse Plane Input changes that direction without requiring the curve to be
redrawn. Camera Relative is useful when the path can be viewed from changing
sides.

With separate endpoint areas, Bidirectional Endpoint Areas lets either end
activate the section when entered from outside and release it when reached from
inside. Disable it to retain the base spline's directional entrance/exit
behavior.

Guided centering, tangent snap, grounded-only, and forced rotation fields from
the base automation spline are hidden on this preset. Their 2.5D equivalents
are the transition, position/velocity constraint, and Constrain Airborne
controls.

## Terrain loops

Keep the authored curve as a simple, non-self-intersecting ribbon through a
terrain loop. Terrain Traversal Adjustment reads the attached surface normal
and derives the travel tangent inside that ribbon. The tangent rotates around
the stable sideways axis through walls and ceilings without adding overlapping
curve branches. A player who jumps over the loop therefore continues to use
the ordinary ribbon frame.

Ribbon Surface Tangent is the intended traversal mode for loops. Project Path
On Surface retains the earlier path-projection behavior for terrain that only
needs mild slope cooperation. Preserve Ribbon Normal keeps loop traversal from
rotating the forbidden depth axis. Terrain Tangent Alignment Strength controls
how strongly grounded velocity is kept on the detected loop tangent.

Force Surface Adhesion is useful when loop contact changes sharply. Surface
adjustment stops as soon as the player detaches, including when the player jumps
over the loop.

## Offset or imperfect geometry

The authored curve supplies progression and the intended ribbon orientation;
it is not treated as an infallible collision centerline. Adaptive Centerline
permits a bounded plane-depth offset from the curve while the player remains
attached.

This handles loops and gimmicks whose collision entrance and exit are slightly
offset sideways:

- Capture Entry Depth Offset prevents activation from immediately snapping a
  player who enters on a parallel offset line. Captured Depth Transition fades
  that temporary offset to the authored centerline as endpoint adherence rises.
- Follow Unanchored Surface Depth restores player-measured adaptive movement
  for sections that require it. It is disabled by default so arbitrary entry
  depth cannot become a permanent or self-reinforcing centerline.
- Adaptive Centerline Enabled follows depth-profile and terrain-anchor changes.
- Adaptive Centerline Grounded Only holds the last valid offset during jumps,
  preventing airborne movement from dragging the plane.
- Adaptive Centerline Max Offset is the maximum geometry mismatch the object
  accepts. Increase it when an intentional gimmick offset is larger than the
  default.
- Adaptive Centerline Strength and Max Speed determine how quickly the ribbon
  follows the collision-driven offset.
- Adaptive Centerline Deadzone ignores small contact jitter.

Terrain Piece Anchors provide deterministic offsets for geometry made from
several collision pieces. Enable Terrain Piece Anchors on the spline and add
the metadata key `automation_25d_centerline_anchor` to a collision node or one
of its parents:

- `true` uses that Node3D's origin as the centerline-depth target.
- A Vector3 uses that local point as the target.
- A number supplies the plane offset directly.

Only attached slide collisions can select an anchor. When several pieces touch
at a seam, the target closest to the current offset wins. Airborne movement
holds the last valid offset, so a jump cannot select another loop piece through
proximity alone. Unmarked terrain uses the authored centerline unless Follow
Unanchored Surface Depth is enabled.

Surface Frame Uses Velocity is disabled by default. Enable it only when the
collision route's forward direction needs velocity-based refinement; using it
for ordinary sections can make unintended motion influence the frame.

## Depth offset splines

`AutomationSpline2_5DDepthProfile.tscn` provides an authored depth centerline
for gimmicks with deliberate sideways travel. Its curve affects only the main
2.5D spline's plane offset. It does not replace main-path progress, movement
tangent, surface traversal, or camera orientation.

Place the depth profile under its target `AutomationSpline2_5D`, or assign an
explicit Automation Spline Path. Draw the profile curve through the intended
terrain centerline. Multiple profiles may target one movement spline; Priority
selects the winner, with profile distance resolving equal priorities.

Activation modes are:

- Always While Target Active applies the profile whenever the parent 2.5D
  spline controls the player.
- Volume activates and releases through `Area3D`.
- Entry/Exit Areas activates at `Entrance` and releases at `Exit`.
  Bidirectional Endpoint Areas lets either endpoint toggle the profile.

Failsafe Exit Distance releases a body that strays too far from the depth
curve. This is useful when a player jumps over a loop after entering its
approach region. Preferred Offset Window preserves the current curve branch,
while Branch Switch Distance Tolerance and Tracking Recovery Distance control
when displaced players may recover to another part of the profile.
Speed Adaptive Tracking Window expands that preferred neighborhood using the
distance traveled since the previous profile sample, preventing high-speed
movement from falling outside a small fixed window and selecting another loop
branch.

Follow While Airborne is disabled by default. The last valid centerline offset
is therefore held during jumps. Enable it only when an airborne gimmick must
continue advancing through its authored depth profile.

Each profile can select a Centerline Response Mode:

- Inherit uses the target 2.5D spline's Adaptive Centerline Strength and
  Adaptive Centerline Max Speed.
- Override uses the profile's Centerline Strength and Centerline Max Speed.
- Immediate applies the sampled profile offset without centerline smoothing.

Override Centerline Offset Limit lets a profile replace the main spline's
Adaptive Centerline Max Offset. This is required when a loop deliberately
travels farther in depth than the main ribbon normally permits. A profile limit
of zero is unlimited. When the profile releases, an out-of-range current offset
returns through the normal release response instead of being clamped in one
frame.

Minimum Constraint Adherence supplies a floor for the main section's endpoint
blend while the profile is active. A value of `1.0` makes Strict Position Lock
take effect throughout the profile. Override Position Constraint provides
profile-local position strength, correction-speed, strict-lock, and deadzone
settings. These controls allow a loop to be rigid without making the rest of
the 2.5D spline rigid.

Immediate response with full minimum adherence is appropriate for a profile
that follows a physical loop closely. Follow While Airborne should also be
enabled so losing surface contact for one physics frame does not freeze the
profile offset halfway through the loop.

Depth profiles take precedence over terrain-piece anchors while active. Piece
anchors remain a lightweight fallback for discrete collision assemblies, and
unmarked terrain returns to the primary spline's authored centerline.

## Constraint tuning

Strict Position Lock and Strict Velocity Lock guarantee a flat movement plane
at full adherence. Their response strengths control the entry and exit blends.
The maximum position correction speed limits transition pull but does not limit
the strict core snap.

Post-Slide Constraint Pass reapplies enabled strict locks after
`move_and_slide()`. Collision response can otherwise introduce a final sideways
position or velocity after the normal constraint pass, which becomes visible
at very high speeds. The post-slide pass only runs at full adherence, so it
does not harden the endpoint transition blends.

Before the post-slide pass, the player requests a fresh path sample from the
active 2.5D spline. This prevents the strict pass from using the tangent and
plane normal sampled before a high-speed movement step.

## Path sampling

Cubic Path Sampling interpolates positions and authored frames between baked
curve samples. Speed Adaptive Tracking Window expands the preferred arc-length
neighborhood using the distance traveled since the previous sample. This keeps
high-speed motion on the current continuous branch without requiring an
excessively large fixed Preferred Offset Window.

Tracking Window Travel Multiplier controls the expansion margin. Maximum
Adaptive Tracking Window bounds it around curves with nearby or overlapping
branches; zero removes that bound. Smaller Curve3D Bake Interval values improve
closest-point accuracy at the cost of additional baked samples. Values around
`0.1` to `0.25` meters are suitable for tight, high-speed test routes.

Depth profiles have a separate Cubic Profile Sampling option. It resamples the
selected profile offset cubically after branch-safe closest-point tracking.

Disable Turning Slowdown prevents passive steering-angle deceleration during
the 2.5D section on both ground and air movement. Deliberate pullback or reverse
input can still brake the player. This is enabled by default for 2.5D splines.

Sideways Removal Speed Preservation is zero by default. Raising it converts
some removed depth speed back into in-plane speed. This can make guided sections
more forgiving, but zero is the predictable choice for physics-heavy loops and
turning-radius behavior.

Constrain Airborne keeps jumps inside the ribbon. Constrain Special Moves keeps
homing, jump dash, and similar external movement inside it. Disable the latter
for a gimmick that must temporarily leave the 2.5D plane.

Force Surface Adhesion is useful for loop sections with sharp contact changes.
It automatically releases when endpoint adherence reaches zero.

## Camera

The spline can register itself as a moving camera constraint. Its tracking point
uses the same adaptive centerline as movement, so small depth offsets do not
make the camera and player constraints disagree.

Available controls include camera side, gravity/player/path-frame up modes,
roll, player-facing aim, distance, vertical offset, fixed and velocity-based
lead, FOV, entry and exit smoothing, manual-control lock, and camera collision
override. Constraint priority controls overlaps, while Override Previous Camera
Constraints can make a section take exclusive control on activation.

Camera lead uses signed path speed only after Camera Lead Direction Speed is
exceeded. Recenter is the default idle mode, so standing still returns the
tracking point to the player instead of assuming the positive path direction.
Hold Last Direction retains the previous fixed lead for sections that need it.
Lead Smoothing controls moving and reversing response, Recenter Smoothing
controls the idle return, and Maximum Adjustment Speed places a hard limit on
how quickly either change can move the tracking point.

Gravity up is the stable default for the camera even when the player traverses
an inverted loop. Enable Allow Roll to use the selected player or path-frame up
axis and visually rotate with the route.

## Suggested starting values

For a conventional side-view section:

- Path Frame with Curve3D up vectors enabled
- 12 m entry and exit blends
- strict position and velocity locks
- Ribbon Surface Tangent enabled at full influence
- Preserve Ribbon Normal enabled
- Adaptive Centerline enabled, grounded only, 4 m maximum offset
- horizontal path input
- along-path assistance disabled
- gravity-up camera with roll disabled

For a heavily banked or corkscrew section, enable camera roll and select Path
Frame camera up. For a gimmick with a large authored depth shift, increase the
adaptive maximum offset and lower its maximum follow speed if the handoff should
be visibly gradual.
