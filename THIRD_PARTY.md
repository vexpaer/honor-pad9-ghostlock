# Third-party components

This repository does not commit kernel images, KernelSU modules, APKs, or
prebuilt helper binaries. `scripts/fetch-bundle.ps1` downloads the artifacts
below into `bundle/`, verifies them, and leaves them ignored by git.

## GhostLock-H80GT v0.3.1

- Source: <https://github.com/yakidango-official/GhostLock-H80GT>
- Release: <https://github.com/yakidango-official/GhostLock-H80GT/releases/tag/v0.3.1>
- Archive: <https://github.com/yakidango-official/GhostLock-H80GT/releases/download/v0.3.1/ghostlock.tar.gz>
- Archive SHA256: `A5A3CFF2C3172BD5DEBE2A4E4F71C69402C00C8CFFD37906B1354437B4C8810E`
- License: Apache-2.0 (upstream `LICENSE`)

The fetch script extracts only these members:

| Member | SHA256 | Role |
|---|---|---|
| `kernelsu.ko` | `7B153982DD1C7354D7DA41689DF8B97DFC24ACA54B467A6A43311071E5643037` | KernelSU LKM used for the HEY2 191 late-load |
| `ksud` | `99AAA607E9C9DA6A0E898366ECF0A14DD67224EA726D952D1CE575E62D3B5C41` | KernelSU userspace daemon |
| `magiskpolicy` | `9837DB9DB475EB74B6715F081768CB6A1F2FB5A2B2AC15755686062501BACE27` | SELinux policy injection helper |

The LKM is a third-party build. It is not built by this repository and its
presence in the upstream release does not imply that KernelSU officially
supports HEY2-W09. Its KernelSU kernel-side code is GPL-2.0; `ksud` and
`magiskpolicy` are GPL-3.0 userspace components. The containing H80GT release
archive is distributed by its author under Apache-2.0.

## KernelSU Manager v3.3.0

- Source: <https://github.com/tiann/KernelSU>
- Release: <https://github.com/tiann/KernelSU/releases/tag/v3.3.0>
- APK: <https://github.com/tiann/KernelSU/releases/download/v3.3.0/KernelSU_v3.3.0_32601-release.apk>
- APK SHA256: `C197060ECB89702E7D54A4C95E29CF5E8D97369BBBB436979AB7FD6BCDE7B077`
- License: GPL-3.0 for the userspace project; KernelSU's kernel-side code is
  GPL-2.0.

## Magisk

- Source: <https://github.com/topjohnwu/Magisk>
- License: GPL-3.0
- The `magiskpolicy` binary is taken from the H80GT release bundle; it is not
  redistributed by this repository.

## KernelSU kernel-side material in `ksu/`

`ksu/load_ko.c`, `ksu/kmsg_dumper.c`, `ksu/ksu_loader.tmpl`,
`ksu/ksu_rules` and `ksu/ksu_rules.annotated` are provided under GPL-2.0
(`ksu/LICENSE`) because they derive from or interoperate with KernelSU's
kernel-side policy and loader work.

## Upstream chain

The GhostLock-H80GT project credits the following projects; this port retains
that attribution:

- NebuSec/CyberMeowfia: <https://github.com/NebuSec/CyberMeowfia>
- BuSung-dev/CVE-2026-43499-S25U: <https://github.com/BuSung-dev/CVE-2026-43499-S25U>
- F-19-F/IonStackQuest3: <https://github.com/F-19-F/IonStackQuest3>
