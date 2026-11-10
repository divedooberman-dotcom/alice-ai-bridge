# Automatic reading without a Mac

On 9 November 2026, the Family AI skill was published and its webhook answered
the local health probe on A1. Automatic reading was unavailable. The Mac relay
was stopped, its autostart was disabled, and A1 reported zero of two stations
ready. In that state the skill returns «Нет связи с автоматическим чтением».

The bridge on A1 queues answer text for the station that received the question.
The relay pulls that station's jobs and asks it to speak through Glagol. The
existing relay can run on A1 once it has a private network path to each station.

The A1 network check on 9 November reached Kolobok's Glagol TCP port 1961
directly through Tailscale. A1 had no Tailscale route to the Midi's LAN address.
Kolobok already advertises the approved home subnet, which can carry the Midi
traffic once A1 is configured to accept the route and the tailnet policy allows
the connection. The TCP check verified reachability to Kolobok only.

1. Run the relay as a dedicated systemd service on A1. Use an explicit device
   inventory and protected server credentials. Start with Kolobok and keep a
   single queue consumer for that station.
2. Enable the private route to the Midi, restrict access to its Glagol port,
   and verify authenticated Glagol connectivity from A1 before adding the Midi
   to the service. This route depends on Kolobok staying online.
3. With the Mac off, ask a question that requires automatic continuation on
   each station. Verify that both stations are ready and that each reads its
   own complete answer without a «продолжай» command.

The migration and the two-station playback test are pending. Cloudflare Tunnel
also supports private IP routes, but would require a home connector and a
Cloudflare client or equivalent private network access on A1. The existing
Tailscale setup provides the starting point for this migration.
