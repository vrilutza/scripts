Title: v4l2 source defaults to 4 buffers and pipewiresrc drops frames forever when they are not recycled — camera freezes on first frame (GNOME Snapshot)

## Summary

GNOME Snapshot (Camera) shows the first frame from the camera and then freezes permanently; recordings come out empty. After instrumenting every layer, the freeze is a buffer-starvation deadlock caused by the interaction of two PipeWire behaviors:

1. **The spa v4l2 source offers a hardcoded default of 4 buffers.** In `spa/plugins/v4l2/v4l2-source.c` (1.6.8):

   ```c
   SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(SPA_MIN(4u, port->max_buffers), 1, port->max_buffers),
   ```

   `gstpipewiresrc` suggests a default of 16 (`CLAMP (16, pwsrc->min_buffers, pwsrc->max_buffers)` in `handle_format_change`), but negotiation fixates on the node's default, so camera streams end up with a 4-buffer pool unless the client explicitly sets `min-buffers`.

2. **`gstpipewiresrc` has no fallback when a buffer is not recycled.** `dequeue_buffer()` (src/gst/gstpipewiresrc.c:735 in 1.6.8):

   ```c
   if (!data->queued) {
       GST_ERROR_OBJECT (pwsrc, "buffer %p was not recycled", data->buf);
       return NULL;
   }
   ```

   The frame is dropped. If the downstream pipeline is holding all 4 pool buffers (a GL display sink chain easily keeps 4 alive: current texture + upload in flight + queued), this repeats for every frame, forever — the stream is permanently frozen on the first frame while the producer keeps running.

3. (Aggravator) `spa_v4l2_mmap_init` hard-fails with `-ENOMEM` when the kernel driver grants fewer buffers than negotiated (`reqbuf.count < n_buffers`), instead of degrading to the granted count. Several V4L2 drivers cap REQBUFS at 4 (e.g. facetimehd), so a client that *does* request more buffers gets zero frames instead of a working 4-buffer stream.

## Environment

- pipewire 1.6.8 (Debian forky, 1.6.8-1), wireplumber 0.5.15
- GStreamer 1.28.4, GNOME Snapshot 50.0
- Camera: Apple FaceTime HD (`facetimehd` out-of-tree driver), 1280x720 YUY2 @ 30 fps, `/dev/video0`
- Kernel 7.1.3, Wayland/GNOME

## Measurements

| Test | Result |
|---|---|
| Direct V4L2 mmap capture (no PipeWire) | steady 30.0 fps, image live |
| `pipewiresrc ! fakesink` | 206 frames / 8 s, no gaps |
| appsink holding the last **3** samples referenced | sustained ~24-30 fps indefinitely |
| appsink holding the last **4** samples referenced | **exactly 4 frames, then frozen forever**; `buffer 0x… was not recycled` logged every ~133 ms |
| GNOME Snapshot (GST_DEBUG=3) | identical: first frame shown, then a continuous `not recycled` stream on the same buffer pointer |
| driver patched to grant 8 buffers + `min-buffers=8` on pipewiresrc | works even while holding 7 samples |
| unpatched driver (REQBUFS caps at 4) + `min-buffers=5` | 0 frames (`mmap_init` -ENOMEM path) |

## Minimal reproducer

Freezes after exactly 4 frames with any camera whose stream negotiates the default 4 buffers:

```python
#!/usr/bin/env python3
# hold N samples referenced, like a display sink chain does
import sys, time, collections, gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst, GLib
Gst.init(None)
HOLD = int(sys.argv[1]) if len(sys.argv) > 1 else 4

src = Gst.ElementFactory.make("pipewiresrc", None)
props = Gst.Structure.new_empty("props")
props.set_value("media.type", "Video")
props.set_value("media.category", "Capture")
props.set_value("media.role", "Camera")
src.set_property("stream-properties", props)
sink = Gst.ElementFactory.make("appsink", None)
sink.set_property("emit-signals", True)
sink.set_property("sync", False)
pipe = Gst.Pipeline.new(None)
pipe.add(src); pipe.add(sink); src.link(sink)

held = collections.deque(maxlen=HOLD)
n = [0]
def on_sample(s):
    n[0] += 1
    held.append(s.emit("pull-sample"))
    return Gst.FlowReturn.OK
sink.connect("new-sample", on_sample)

loop = GLib.MainLoop()
pipe.set_state(Gst.State.PLAYING)
GLib.timeout_add(6000, loop.quit)
t0 = time.monotonic()
loop.run()
pipe.set_state(Gst.State.NULL)
print(f"hold={HOLD}: {n[0]} frames in {time.monotonic()-t0:.1f}s")
# hold=3 -> ~146 frames; hold=4 -> exactly 4 frames (frozen)
```

## Suggested fixes (any one of these breaks the deadlock)

- Raise the v4l2 source default, e.g. `SPA_MIN(8u, port->max_buffers)` — the gst client already asks for 16 by default.
- `gstpipewiresrc`: when a dequeued buffer was not recycled, copy its contents into a new GstBuffer and requeue, instead of dropping frames forever.
- `spa_v4l2_mmap_init`: degrade gracefully to `reqbuf.count` when the driver grants fewer buffers than negotiated.

The end-user impact today is that GNOME Snapshot's viewfinder freezes on the first frame on affected cameras (separate report filed against Snapshot: https://gitlab.gnome.org/GNOME/snapshot/-/work_items/367).
