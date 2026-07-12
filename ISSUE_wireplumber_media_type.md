Title: Linking hooks crash with a Lua error when a stream has no `media.type` property — client fails with "target not found"

## Summary

When a client stream connects without a `media.type` property, **both** target-selection linking hooks abort with unhandled Lua errors, so no target is ever picked and the client fails with `stream error: target not found` — even though a perfectly matchable device node exists and is idle.

1. `find-default-target` → `lutils.findDefaultLinkable()` → `cutils.getDefaultNode()` concatenates the property unguarded (`src/scripts/lib/common-utils.lua`, line 54 in 0.5.15; same code on current master):

   ```lua
   function cutils.getDefaultNode (properties, target_direction)
     local target_media_class =
     properties ["media.type"] ..
         (target_direction == "input" and "/Sink" or "/Source")
   ```

   → `attempt to concatenate a nil value (field 'media.type')` — the hook dies.

2. The fallback hook `find-best-target` then dies too, because building a `Constraint` with a nil value fails an assert (`src/scripts/linking/find-best-target.lua`, also unchanged on master):

   ```lua
   Constraint { "media.type", "=", si_props ["media.type"] },
   ```

   → `api.lua:57: Constraint: equals: expected constraint value`.

With both hooks gone, linking gives up and the stream errors out.

## Journal output (verbatim)

```
wireplumber[3051]: wplua: [string "common-utils.lua"]:54: attempt to concatenate a nil value (field 'media.type')
                   stack traceback:
                           [string "common-utils.lua"]:54: in field 'getDefaultNode'
                           [string "linking-utils.lua"]:330: in field 'findDefaultLinkable'
                           [string "find-default-target.lua"]:38: in function <[string "find-default-target.lua"]:24>
wireplumber[3051]: wplua: [string "api.lua"]:57: Constraint: equals: expected constraint value
                   stack traceback:
                           [C]: in global 'assert'
                           [string "api.lua"]:57: in global 'Constraint'
                           [string "find-best-target.lua"]:48: in function <[string "find-best-target.lua"]:26>
```

## Environment

- wireplumber 0.5.15 (Debian forky, 0.5.15-1), pipewire 1.6.8
- Trigger client: `gstpipewiresrc` (GStreamer 1.28.4) — it does not set `media.type` unless the
  application passes `stream-properties`, so any bare `pipewiresrc` pipeline reproduces this
- A healthy, idle V4L2 camera node was present the whole time (the same pipeline links and streams
  fine once `media.type = Video` is added to the stream properties)

## Reproducer

```
gst-launch-1.0 pipewiresrc ! fakesink
```

or the Python equivalent:

```python
#!/usr/bin/env python3
import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst
Gst.init(None)
pipe = Gst.parse_launch("pipewiresrc ! fakesink")
bus = pipe.get_bus()
pipe.set_state(Gst.State.PLAYING)
msg = bus.timed_pop_filtered(8 * Gst.SECOND,
                             Gst.MessageType.ERROR | Gst.MessageType.EOS)
if msg and msg.type == Gst.MessageType.ERROR:
    print("CLIENT ERROR:", msg.parse_error()[0].message)
pipe.set_state(Gst.State.NULL)
```

Result: `CLIENT ERROR: stream error: target not found` and the two Lua stack traces above in the
wireplumber journal. Adding `stream-properties` with `media.type=Video` to the same pipeline makes
it link and stream normally.

## Expected behavior

A missing, client-provided property should not abort target selection with unhandled Lua exceptions.
Expected: skip the default-node lookup (there is no meaningful default for an unknown media type) and
let best-target matching proceed on direction/device — or at minimum degrade cleanly with a log
message instead of two script crashes and an unhelpful client-facing "target not found".

## Suggested fix

- `cutils.getDefaultNode()`: return `nil` when `properties["media.type"]` is nil.
  `findDefaultLinkable()` already tolerates that (`Constraint { "node.id", "=", tostring(nil) }`
  simply matches nothing, so the hook falls through).
- `find-best-target.lua`: only include the `media.type` Constraint when `si_props["media.type"]`
  is non-nil.

Either change alone un-breaks linking; both together restore the intended fallback behavior.

(Found while investigating an unrelated camera freeze:
https://gitlab.freedesktop.org/pipewire/pipewire/-/work_items/5363)
