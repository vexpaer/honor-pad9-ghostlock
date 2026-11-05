# Verification summary

Target: HONOR Pad 9 `HEY2-W09` / `HNHEY2-Q`, MagicOS
`8.0.0.191C00E185R2P4`, Android 14, kernel
`5.10.252-android12-9-ga431fb50f9a2`.

The run was performed on 2026-11-05 with explicit authorization on the
research device. The module was late-loaded into the current boot. No boot,
super, vbmeta, or other partition was written.

## Observed results

| Check | Result |
|---|---|
| KernelSU LKM load | `module loaded OK` |
| Undefined symbols | `208/208` resolved |
| `/proc/modules` | `kernelsu` present |
| Manager state | `工作中 [越狱模式]`, `LKM`, `32601-2` |
| `ksud --version` | `ksud 3.3.0 (uapi: 2)` |
| `su -c id` | `uid=0(root)`, context `u:r:ksu:s0` |
| `ksud post-fs-data` | exit 0 |
| `ksud services` | exit 0 |
| `ksud boot-completed` | exit 0 |
| `ksud install` | exit 0 |
| SELinux after verified run | permissive |

Representative loader output:

```text
resolved 208/208 from /proc/kallsyms
patched 208 symbols to SHN_ABS; 0 unresolved
module loaded OK!
kernelsu 212992 1 - Live ... (OE)
KernelSU module loaded
```

## Evidence handling

The original run directory and raw `kmsg` capture are not published. They
contain device/network identifiers, including addresses and interface
metadata. The cropped Manager screenshot in
[`assets/manager-working.png`](../assets/manager-working.png) is the only
published device image.

The screenshot was cropped to remove the status bar, navigation bar, and
wireless-network details. Its SHA256 is:

```text
CB5FD95C3718FA8337148DA2B9BFD5CBA26B72F6B36306CB1D5F180E985CE48E
```

## Not verified

- Persistence across reboot.
- SELinux `Enforce=1` as an independent regression run.
- Third-party KernelSU modules.
- Any other MagicOS build, model, or kernel.
