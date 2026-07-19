# Draft reply for wireplumber issue #972 / MR 861 (post as a comment, e.g. replying to @gkiagia)

> the media.type was already being set here. Why didn't this work already?

Because that block can only *infer* `media.type` from the `media.class` string, and
for this stream there is nothing to infer from. I captured the node of the bare
`pipewiresrc` reproducer with `pw-dump --monitor` while it was connecting — it
arrives with **no `media.type` at all** and with `media.class = "Stream/Input/Unknown"`:

```
node id 73
   client.id = 76
   media.class = 'Stream/Input/Unknown'
   media.name = 'python3.13'
   node.async = true
   node.autoconnect = true
   node.description = 'python3.13'
   node.dont-reconnect = true
   node.loop.class = 'main'
   node.name = 'python3.13'
   node.want-driver = true
   object.id = 73
   object.serial = 85
   port.group = 'stream.0'
   stream.is-live = true
```

The `"Unknown"` is synthesized by pipewire itself: `gstpipewiresrc` never sets
`PW_KEY_MEDIA_TYPE` (it only forwards the application-provided `stream-properties`,
which a bare pipeline doesn't have), so `pw_stream_connect()` builds the class as
`"Stream/%s/%s"` via `get_media_class()`, which returns `"Unknown"` when the media
type cannot be determined from the connect params (`src/pipewire/stream.c`, pipewire
1.6.8 — gstpipewiresrc offers caps for several media types, so the type is still
undetermined at connect time). Since `"Stream/Input/Unknown"` contains none of
`Audio`/`Video`/`Midi`, the `for` loop falls through without setting anything, and
both linking hooks then crash on the nil exactly as reported.

To rule out the other possibility you raised: nothing is modified locally. This is
stock Debian (wireplumber 0.5.15-1) — `dpkg --verify wireplumber` reports zero
changed files, and there are no override directories at all on this system (no
`/etc/wireplumber`, `~/.config/wireplumber`, `~/.local/share/wireplumber` or
`/usr/local/share/wireplumber`).

FWIW, if the proactive style is preferred, the minimal fix in that spirit would be a
final fallback in the same block, e.g.
`properties["media.type"] = properties["media.type"] or "Unknown"` — every session
item then always carries a media.type, `getDefaultNode()` would look up
"Unknown/Sink" (finds nothing, harmless) and the target constraints simply would not
match, which is the same end behavior as this MR. Either approach unblocks the
linking hooks; I'll happily test whichever lands.

For completeness: I understand that with either fix a bare `pipewiresrc` still ends
with "target not found" (an `Unknown` stream won't match a `Video` device) — that
conservative behavior seems correct to me; making it actually auto-link would be a
gst-plugin-pipewire change (set `media.type` from the negotiated caps), not a
WirePlumber one. The important part is that the session manager no longer aborts its
hooks on it.
