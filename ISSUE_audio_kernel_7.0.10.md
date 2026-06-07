# CS8409: no sound card on kernel 7.0.10 — UBSAN array-index-out-of-bounds in HDA generic parser (regression vs 7.0.9)

> Ready-to-paste bug report. Primary target: **davidjo/snd_hda_macbookpro**.
> Also worth filing against the **Debian kernel** (the regression is in the in-tree HDA code).
> Delete this note before posting.

## Summary

After upgrading the Debian kernel from **7.0.9 → 7.0.10**, the CS8409 codec fails to register a
sound card. `cs8409_probe` → `snd_hda_gen_parse_auto_config` trips multiple UBSAN
`array-index-out-of-bounds` reports in the **in-tree** HDA generic parser and the codec probe
fails, leaving the system with **no sound card** (`/proc/asound/cards` → `--- no soundcards ---`,
`/dev/snd/` has only `seq` and `timer`).

Audio works perfectly on **7.0.9** with the same driver and the same UBSAN config — so this is a
**regression in the in-tree HDA generic-parser code between 7.0.9 and 7.0.10**, exposed by the
CS8409 codec.

## Environment

| | |
|---|---|
| Hardware | Apple MacBookPro14,1 (Mac-B4831CEBD52A0C4C), 13" 2017, A1708 |
| Codec | Cirrus Logic CS8409 / CS42L83 |
| Broken kernel | `7.0.10+deb14-amd64` (Debian 7.0.10-1) |
| Working kernel | `7.0.9+deb14-amd64` (Debian 7.0.9-1) |
| Driver | davidjo/snd_hda_macbookpro @ `cb27cc4` (2026-05-05), DKMS |
| `AUTO_CFG_MAX_INS` (7.0.10) | 18 |

## What rules OUT "UBSAN was newly enabled"

Both kernels ship identical UBSAN config:

```
# /boot/config-7.0.9  AND  /boot/config-7.0.10
CONFIG_UBSAN=y
CONFIG_UBSAN_BOUNDS=y
CONFIG_UBSAN_BOUNDS_STRICT=y
```

Yet:
- **7.0.9**: 0 UBSAN reports during CS8409 probe, sound card registers, audio works.
- **7.0.10**: 10 UBSAN reports during CS8409 probe, probe fails, no sound card.

So the sanitizer was always strict; the **in-tree HDA parser code changed** in 7.0.10 in a way
that now drives `cfg->num_inputs` (or the input-label loop index) past the fixed array bounds.

## Where it breaks

The codec's autoconfig wrapper is the standard minimal one (patch_cs8409.c):

```c
static int cs8409_parse_auto_config(struct hda_codec *codec)
{
	struct cs8409_spec *spec = codec->spec;
	...
	err = snd_hda_parse_pin_defcfg(codec, &spec->gen.autocfg, NULL, 0);   // num_inputs = 2 here (correct)
	if (err < 0) return err;
	err = snd_hda_gen_parse_auto_config(codec, &spec->gen.autocfg);       // UBSAN fires INSIDE this
	if (err < 0) return err;
	...
}
```

Pin parse is correct — the kernel logs exactly two inputs just before the crash:

```
snd_hda_codec_cs8409 hdaudioC0D0: autoconfig for CS8409: line_outs=2 (0x24/0x25/...) type:speaker
snd_hda_codec_cs8409 hdaudioC0D0:    hp_outs=1 (0x2c/...)
snd_hda_codec_cs8409 hdaudioC0D0:    inputs:
snd_hda_codec_cs8409 hdaudioC0D0:      Internal Mic=0x44
snd_hda_codec_cs8409 hdaudioC0D0:      Mic=0x3c
```

The out-of-bounds accesses then happen **inside** `snd_hda_gen_parse_auto_config`, in the
input-label loop (`sound/hda/codecs/generic.c` ~3293–3313) and
`hda_get_autocfg_input_label` (`sound/hda/common/auto_parser.c` ~579–589). The reported indices
(18, 40, 41, 42, and a garbage label index 223) far exceed `num_inputs = 2`, which points to
`cfg->num_inputs` (or the loop bound) being corrupted/inflated inside the generic parser on
7.0.10.

## UBSAN reports (all 10)

```
generic.c:3294:30   index 18  out of range for 'auto_pin_cfg_item [18]'
auto_parser.c:579:24 index 41 out of range for 'auto_pin_cfg_item [18]'
auto_parser.c:582:31 index 40 out of range for 'auto_pin_cfg_item [18]'
auto_parser.c:583:49 index 42 out of range for 'auto_pin_cfg_item [18]'
auto_parser.c:589:23 index 41 out of range for 'auto_pin_cfg_item [18]'
auto_parser.c:588:52 index 41 out of range for 'auto_pin_cfg_item [18]'
generic.c:3304:26   index 40  out of range for 'char *[36]'
generic.c:3311:21   index 41  out of range for 'char *[36]'
generic.c:3312:25   index 41  out of range for 'int [36]'
generic.c:3305:34   index 223 out of range for 'char *[36]'
```

## Representative stack trace

```
UBSAN: array-index-out-of-bounds in sound/hda/codecs/generic.c:3294:30
index 18 is out of range for type 'auto_pin_cfg_item [18]'
CPU: 0 UID: 0 PID: 386 Comm: (udev-worker) Tainted: G U OE 7.0.10+deb14-amd64 #1
Hardware name: Apple Inc. MacBookPro14,1/Mac-B4831CEBD52A0C4C, BIOS 529.140.2.0.0 06/23/2024
Call Trace:
 dump_stack_lvl+0x5d/0x80
 ubsan_epilogue+0x5/0x2b
 __ubsan_handle_out_of_bounds.cold+0x54/0x59
 snd_hda_gen_parse_auto_config+0x350d/0x3960 [snd_hda_codec_generic]
 cs8409_probe.cold+0x3a4/0xf07 [snd_hda_codec_cs8409]
 hda_codec_driver_probe+0xd0/0x190 [snd_hda_codec]
 really_probe+0xde/0x380
 __driver_probe_device+0x84/0x170
 driver_probe_device+0x1f/0xa0
 __driver_attach+0xcb/0x210
 bus_for_each_dev+0x85/0xd0
 <TASK>
```

## Result

```
$ cat /proc/asound/cards
--- no soundcards ---
$ ls /dev/snd/
seq  timer
```

No playback/capture devices; `snd_hda_codec_cs8409` is loaded but no card is created.

## Severity: not just UBSAN warnings — it can hard-crash (GP fault)

On at least one boot the out-of-bounds read produced a garbage pointer that was then dereferenced
by `strcmp`, faulting `modprobe` during codec load:

```
Oops: general protection fault, probably for non-canonical address 0x25002400000002: 0000 [#1] SMP PTI
RIP: 0010:strcmp+0x28/0x50
note: modprobe[896] exited with irqs disabled
note: modprobe[896] exited with preempt_count 1
```

This matches `generic.c:3305` `!strcmp(spec->input_labels[j], label)` reading
`spec->input_labels[]` past its bounds (UBSAN reported index 223 on `char *[36]`): the garbage
entry is used as a pointer and `strcmp` dereferences it. So the regression can range from "no
sound card" to a kernel general-protection fault depending on what the out-of-bounds memory holds.

It also faults when the codec is **coldplugged by udev** (not just manual modprobe). When a
`udevadm trigger` re-adds the HDA device, the udev worker loads `snd_hda_codec_cs8409` and faults
mid-probe, killing the worker:

```
systemd-udevd[331]: hdaudioC0D0: Worker [390] processing SEQNUM=3227 killed.
kernel: BUG: unable to handle page fault for address: ffffd2890333fd80
kernel: #PF: supervisor write access in kernel mode
kernel: RIP: 0010:idempotent_init_module+0x232/0x310   ... RIP: 0010:strcmp+0x28/0x50
kernel: Modules linked in: ... snd_hda_codec_cs8409(OE+) snd_hda_codec_generic ...
```

(The `(OE+)` marks the module loading at fault time.) A killed udev worker leaves the udev queue
non-empty, so any later `udevadm settle` blocks until timeout — a practical side effect beyond the
missing sound card.

## Workaround

Boot **7.0.9** (GRUB → Advanced options) — audio works, zero UBSAN reports.

## Possible mitigation (driver-side, needs your verification)

I'm not certain whether `cfg->num_inputs` is being inflated **inside** the in-tree
`snd_hda_gen_parse_auto_config` on 7.0.10, or whether it's a struct/layout mismatch — I couldn't
diff 7.0.9 vs 7.0.10 of `generic.c` / `auto_parser.c` locally. Two candidate directions:

1. **Driver-side defensive clamp** — in `cs8409_parse_auto_config`, bound `num_inputs` to the
   array size before the generic parser walks it:
   ```c
   err = snd_hda_parse_pin_defcfg(codec, &spec->gen.autocfg, NULL, 0);
   if (err < 0)
       return err;
   /* 7.0.10: guard against the input-label loop walking past inputs[AUTO_CFG_MAX_INS] */
   if (spec->gen.autocfg.num_inputs > AUTO_CFG_MAX_INS)
       spec->gen.autocfg.num_inputs = AUTO_CFG_MAX_INS;
   err = snd_hda_gen_parse_auto_config(codec, &spec->gen.autocfg);
   ```
   This is only useful **if** `num_inputs` is already > `AUTO_CFG_MAX_INS` at that point. On my
   system `snd_hda_parse_pin_defcfg` logged only 2 inputs, yet the in-tree loop reached index 40+
   — which suggests the count is inflated *inside* `snd_hda_gen_parse_auto_config`, in which case
   this clamp won't help and the fix has to be in-tree.

2. **In-tree fix** — if the regression is in the 7.0.10 `generic.c` input-label loop /
   `hda_get_autocfg_input_label` (e.g. the loop bound or a virtual-input addition no longer
   respecting `AUTO_CFG_MAX_INS`), that's where it should be corrected.

The decisive next step is a diff of `sound/hda/codecs/generic.c` and
`sound/hda/common/auto_parser.c` between 7.0.9 and 7.0.10. I'm happy to capture exact values
(e.g. instrument `num_inputs` before the loop) on the affected hardware if that helps.

## Questions for maintainers

1. What changed in the in-tree HDA generic parser (`generic.c` input-label loop /
   `hda_get_autocfg_input_label`) between 7.0.9 and 7.0.10 that lets the iteration run past
   `AUTO_CFG_MAX_INS` (18) / `input_labels[36]` for the CS8409 pin layout?
2. Is `cfg->num_inputs` being inflated inside `snd_hda_gen_parse_auto_config` (e.g. a virtual /
   stereo-mix input being added without a bounds check), or is the label loop bound wrong?
3. Should this be fixed in-tree (bounds the loop / clamp) or does the CS8409 driver need to
   adapt its pin/ADC setup for the new parser behavior?

I have the affected hardware and can test patches / provide additional logs, a full `alsa-info.sh`
dump, or a `codec#0` dump on request.
