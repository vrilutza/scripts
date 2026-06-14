# install.cirrus.driver.sh fails on Debian (.tar.xz) and on RC kernels (kernel.org 404)

> Ready-to-paste issue for **davidjo/snd_hda_macbookpro**. Delete this note before posting.

## Summary

The DKMS pre-build step (`install.cirrus.driver.sh`) obtains the kernel's `sound/hda` tree two ways:
1. from a local `/usr/src/linux-source-<ver>.tar.**bz2**`, or
2. by downloading `linux-<ver>.tar.xz` from kernel.org.

Both paths fail on **Debian** and on **release-candidate** kernels:

- **On Debian the local-source path is never even reached.** The `/usr/src/linux-source-*.tar.bz2`
  check lives inside the `if [ $isubuntu -ge 1 ]` branch, so non-Ubuntu distros skip it entirely and
  go straight to the kernel.org download branch — the installed Debian source is ignored. (It is also
  `.tar.xz`, not the `.tar.bz2` the Ubuntu branch looks for.)
- **The download path 404s for RC kernels (and mis-parses the Debian version).** `kernel_version` is
  `uname -r` cut at the first `-`, which on Debian keeps the ABI suffix: `7.0.10+deb14-amd64` →
  `7.0.10+deb14`. So it first fetches `linux-7.0.10+deb14.tar.xz` (404), then falls back to
  `linux-<major>.<minor>.tar.xz`. That base tarball exists for *released* kernels but **not for an
  `-rc`** (kernel.org only has `testing/linux-<ver>-rcN.tar.gz`), so the build aborts.

Net effect on a Debian box running an `-rc` kernel (e.g. from `experimental`): the module never
even reaches the HDA source — it fails before compiling anything.

## Environment

| | |
|---|---|
| Distro | Debian (forky / testing), experimental kernel |
| Hardware | Apple MacBookPro14,1 (CS8409) |
| Kernel under build | `7.1-amd64` (Debian package `7.1~rc5-1~exp1`) |
| Local source present | `/usr/src/linux-source-7.1.tar.xz` (from `linux-source-7.1`) |

## Exact failure (DKMS make.log)

```
Running the pre_build script
# command: .../install.cirrus.driver.sh -k 7.1-amd64 --dkms
--2026-… https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.1.tar.xz
HTTP request sent, awaiting response... 404 Not Found
Failed to download linux-7.1.tar.xz
Trying to download base kernel version linux-7.1.tar.xz
… 404 Not Found
kernel could not be downloaded...exiting

Building module(s)
# command: make -j4 KERNELRELEASE=7.1-amd64
…/Makefile:211: *** specified external module directory
".../build/build/hda" does not exist.  Stop.
make: *** [Makefile:16: all] Error 2
```

The `build/hda` directory is missing because the source extraction never ran (download 404'd and
the local `.tar.bz2` was not present — Debian's file is `.tar.xz`).

## Relevant lines in install.cirrus.driver.sh

```sh
30:  kernel_version=$(echo $UNAME | cut -d '-' -f1)     # "7.1-amd64" -> "7.1"
...
167: if [ ! -e /usr/src/linux-source-$kernel_version.tar.bz2 ]; then   # only .bz2 checked
...
181:   tar … -xvf /usr/src/linux-source-$kernel_version.tar.bz2 … sound/hda   # only .bz2
...
189:   wget -c https://cdn.kernel.org/pub/linux/kernel/v$major_version.x/linux-$kernel_version.tar.xz …
201:   [[ $? -ne 0 ]] && echo "kernel could not be downloaded...exiting" && exit
```

Two problems:
1. The local-source check/extract (lines 167, 181) is hard-coded to `.tar.bz2`. Debian's
   `linux-source-*` package provides `.tar.xz`.
2. The download fallback (line 189) assumes a released kernel; `-rc` kernels have no stable
   `linux-<ver>.tar.xz` at that URL.

## Suggested fix

Prefer the locally installed Debian/Ubuntu source and accept both compressions before downloading:

```sh
# Debian names the source package by the X.Y base version (e.g. linux-source-7.0),
# ships it as /usr/src/linux-source-<X.Y>.tar.xz, archive top dir is linux-source-<X.Y>/.
# Prefer it: exact patched source, no network, and the only workable source for -rc.
src_ver=$major_version.$minor_version          # e.g. 7.0  (NOT 7.0.10+deb14)
local_src=""
for ext in tar.xz tar.bz2 tar.gz; do
    if [ -e "/usr/src/linux-source-$src_ver.$ext" ]; then
        local_src="/usr/src/linux-source-$src_ver.$ext"
        break
    fi
done

if [ -n "$local_src" ]; then
    # tar -xf auto-detects xz/bz2/gz
    tar --strip-components=2 -xf "$local_src" --directory=build/ \
        "linux-source-$src_ver/sound/hda"
else
    # fall back to kernel.org download (released kernels only)
    ...
fi
```

`tar -xf` auto-detects xz/bz2/gz, so a single extract call works for all three. This makes the
driver build on Debian out of the box and avoids the kernel.org dependency entirely when the
distro source package is installed (which is the normal case for DKMS users on Debian/Ubuntu).

For `-rc` kernels there is no stable kernel.org tarball at all, so using the locally installed
`linux-source-*` package is the only workable source — another reason to prefer it.

## Notes

- `linux-source-<ver>` is the standard Debian package providing the matching kernel source; it is
  already a sensible build dependency for this DKMS module on Debian.
- I have the hardware and can test a patched `install.cirrus.driver.sh` against a Debian `-rc`
  kernel on request.
