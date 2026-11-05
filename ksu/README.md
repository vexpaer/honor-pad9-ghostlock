# ksu/

This directory contains the on-device loader pieces for the HEY2 191
late-load. It is GPL-2.0; see [LICENSE](LICENSE).

## Files

| File | Purpose |
|---|---|
| `load_ko.c` | Minimal `kernelsu.ko` loader: resolves undefined symbols against a prepared `/proc/kallsyms`, rewrites them to `SHN_ABS`, and calls `init_module(flags=0)` |
| `kmsg_dumper.c` | Streams `/dev/kmsg` to an `O_SYNC` file so diagnostics survive a fast reboot |
| `ksu_loader.tmpl` | On-device shell template rendered by `scripts/run-ksu.ps1` |
| `ksu_rules` | SELinux rules injected with `magiskpolicy --apply --live` before the module load |
| `ksu_rules.annotated` | The same rule set with provenance comments |

`kernelsu.ko`, `ksud`, and `magiskpolicy` are not committed. They come from
the pinned H80GT v0.3.1 release and the official KernelSU Manager release;
`scripts/fetch-bundle.ps1` verifies and stages them under `bundle/`.

## Loader behavior

The template freezes `hisecd` for the load window, relaxes
`kptr_restrict`, builds the fake kallsyms, injects the policy, loads the LKM,
runs the optional `ksud` stages, and restores the temporary settings. A
failed run is not a persistence mechanism: reboot is the cleanup boundary.

The `load_ko` flags are deliberately `0`. On this kernel, the IGNORE flags
route through `try_to_force_load()` and can fail silently; the module's empty
`__versions` section takes the flags-only vermagic path instead.

## Build

From the repository root:

```powershell
pwsh -File .\scripts\build.ps1 -NdkRoot '<android-ndk>'
```

This produces `ksu/load_ko` and `ksu/kmsg_dumper`, plus the exploit binaries
under `exploit/build/`.
