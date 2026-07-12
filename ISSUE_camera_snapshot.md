Title: Viewfinder permanently freezes on the first frame — pipeline holds the camera's entire 4-buffer PipeWire pool

## Summary

On cameras whose PipeWire stream negotiates the default buffer count, the pool has only **4 buffers** (the spa v4l2 node's hardcoded default — `SPA_MIN(4u, port->max_buffers)` in `spa/plugins/v4l2/v4l2-source.c`). Snapshot's pipeline keeps 4 buffers referenced at once (display chain), so `pipewiresrc` finds every subsequently dequeued buffer "not recycled" and drops it — with GST_DEBUG=3:

```
ERROR pipewiresrc gstpipewiresrc.c:735:dequeue_buffer:<pipewiresrc0> buffer 0x… was not recycled
```

repeating every ~133 ms on the same buffer pointer for as long as the app runs. The viewfinder shows the first frame and freezes forever; video recordings come out empty. The user-visible result is "camera shows one frame then hangs".

## Environment

- GNOME Snapshot 50.0 (Debian package, not flatpak), GStreamer 1.28.4
- pipewire 1.6.8, wireplumber 0.5.15
- Camera: Apple FaceTime HD (`facetimehd` driver), 1280x720 YUY2 @ 30 fps
- Kernel 7.1.3, GNOME on Wayland

## Evidence that the camera/stack is otherwise healthy

- Direct V4L2 capture: steady 30 fps, live image.
- `pipewiresrc ! fakesink`: 206 frames / 8 s, no gaps.
- Synthetic consumer holding the last N samples referenced: N=3 runs at full rate indefinitely; **N=4 delivers exactly 4 frames and freezes** — precisely Snapshot's behavior.
- With the driver patched to provide 8 buffers and `min-buffers=8` set on `pipewiresrc`, a stream works even while holding 7 samples.

## Suggested fix

In aperture, on the `pipewiresrc` element, either:

- set `min-buffers` to something sane for a viewfinder+recording pipeline (8 worked in testing), and/or
- set `always-copy=true` so held display buffers never starve the source pool.

Either change unfreezes the viewfinder on 4-buffer cameras. (There is an underlying PipeWire issue about the 4-buffer default and the drop-forever behavior: LINK-PIPEWIRE-ISSUE — but Snapshot can protect itself regardless of how that lands, and 4-buffer V4L2 devices will keep existing.)
