# LS5 Engine 3 networking

The online stack uses netfox 1.35.3 for synchronized state and netfox.noray for internet connectivity.

## Connection modes

- **Internet (Invite Code)** registers both peers with the configured Noray service. The client attempts NAT punch-through first and requests a relay if the direct route fails or stops responding. Each route response, UDP handshake, and ENet connection receives its own timeout.
- **Direct IP / LAN** creates a normal ENet server or client on the selected UDP port. This is useful for local testing and LAN play. Internet use requires manual port forwarding.

The default public Noray endpoint is `tomfol.io:8890`, with UDP registration on port `8809`. These values and the handshake timeouts are exported by the `NetworkManager` autoload.

Failed host and join attempts write a timestamped diagnostic file under `user://network_logs`. The online menu shows the absolute path. Logs contain the failed stage, Godot error, route, endpoint, local UDP port, and a timestamped connection timeline. They do not include Noray's private ID. A relay UDP handshake failure indicates that the client did not complete two-way packet exchange; it does not by itself identify whether the relay, host, router, or firewall dropped packets.

Internet hosts can copy their invite code from the online section of the pause menu. The same panel shows the active route, netfox tick rate, client ping, and the current diff-state payload ratio in debug builds.

## Replication model

Player movement remains client-authoritative because the character controller relies on live Godot physics and is not deterministic enough for rollback resimulation.

Each online player receives two runtime children:

- `NetfoxStateSynchronizer` records the presentation snapshot on the player's authority and sends diff states on the netfox tick loop.
- `NetfoxTickInterpolator` smooths remote snapshots between ticks.

The synchronized snapshot includes transform, velocity, attachment and movement state, visual up, model orientation, movement direction, barrier gauge, and active action. Discrete gameplay events such as chat, race state, animation commands, sounds, and ring collection continue to use reliable or unreliable Godot RPCs as appropriate; netfox is designed to work alongside these RPCs.

Player state visibility is filtered by the level IDs managed by `NetworkSession`. Peers in separate streamed levels do not receive each other's continuous movement snapshots. A missing level ID remains visible during scene transitions so newly joined players can finish registration.

## Runtime flow

1. `NetworkManager` establishes an ENet peer directly or through Noray.
2. netfox `NetworkEvents` detects the peer and starts synchronized `NetworkTime` automatically.
3. The host sends the active game scene to a newly connected client.
4. `NetworkSession` creates matching authority-owned player nodes on every peer.
5. Runtime netfox synchronizers begin sampling and interpolating player presentation state.

## Project settings

The add-on defaults to a 30 Hz network tick rate with diff states enabled. Per-character settings are available in the **Networking** inspector group:

- `network_replication_enabled`
- `network_full_state_interval_ticks`
- `network_diff_ack_interval_ticks`
- `network_interpolate_remote_state`

Internet connection mode, direct address, last invite code, UDP port, and maximum player count are persisted in the existing settings file.
