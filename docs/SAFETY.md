# Safety and recovery

## Scope

This repository is a research port for one exact target:

```text
HONOR Pad 9 HEY2-W09 / HNHEY2-Q
MagicOS 8.0.0.191C00E185R2P4
Android 14
Linux 5.10.252-android12-9-ga431fb50f9a2
```

The profile is not a general Honor exploit. The UAF and the surrounding
timing can fail even on the target. Do not run it on a device you do not own
or have explicit permission to test.

## What can go wrong

- The exploit can panic the kernel or reboot the device.
- A failed attempt can leave the current boot in an inconsistent state; the
  intended recovery boundary is a normal reboot.
- The chain temporarily changes SELinux and module-signature state. The
  loader attempts to restore them, but an interrupted run may not.
- Loading an untested module or adding persistence can turn a recoverable
  research run into a permanent failure.

## Do not

- Do not unlock or flash the bootloader as part of this procedure.
- Do not write `boot`, `super`, `vbmeta`, `vbmeta_system`, or other
  partitions.
- Do not add boot-time persistence before the late-load flow is independently
  verified on the exact firmware.
- Do not run unrelated panic PoCs, including the CVE-2026-98260 PoC, while
  validating this chain.
- Do not retry blindly after ADB disappears. A reboot or a changed wireless
  debugging port is not evidence that the previous run succeeded.

## Minimal sequence

1. Confirm the exact kernel and build.
2. Fetch and verify the pinned bundle.
3. Build the source locally.
4. Stage only, inspect the generated loader, and confirm the run directory.
5. Load the module with `-Stages 0 -Enforce 0 -AllowShell 0`.
6. Only after that succeeds, run the user-space stages with the documented
   flags.

The first run should not install modules or change persistent properties.
`-Authorize` is an explicit acknowledgement that the exploit is about to run.

## If ADB is lost

If the device rebooted, wait for it to come back and re-open wireless
debugging. The module and `su` are gone after reboot by design. If the device
does not boot, use the device's normal recovery path; this repository does not
provide a partition-level rescue procedure.
