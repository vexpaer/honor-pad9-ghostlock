# Offset provenance

The public profile is:

```text
exploit/src/targets/honor-HEY2-W09_8.0.0.191/target.h
```

All values below are for the verified 191 kernel. They are not a portable
table and must not be reused for another build.

## Kernel memory layout

| Name | Value |
|---|---|
| `KIMAGE_TEXT_BASE` | `0xffffffc008000000` |
| `P0_PAGE_OFFSET` | `0xffffff8000000000` |
| `P0_PHYS_OFFSET` | `0x80000000` |
| `P0_KERNEL_PHYS_LOAD` | `0xa8000000` |

## `struct task_struct` and related offsets

| Field | Offset |
|---|---|
| `usage` | `0x40` |
| `prio` | `0x84` |
| `normal_prio` | `0x8c` |
| `sched_class` | `0x98` |
| `real_cred` | `0x7b0` |
| `cred` | `0x7b8` |
| `comm` | `0x7c8` |
| `mm` | `0x548` |
| `active_mm` | `0x550` |
| `fs` | `0x7f0` |
| `files` | `0x7f8` |
| `nsproxy` | `0x808` |
| `seccomp.mode` | `0x880` |
| `alloc_lock` | `0x8a0` |
| `pi_lock` | `0x8a4` |
| `pi_waiters` | `0x8b8` |
| `pi_top_task` | `0x8c8` |
| `pi_blocked_on` | `0x8d0` |
| `mm.owner` | `0x348` |

The `cred` object size is `0xa8`; `usage` is `0x00`, `uid` is `0x04`,
`security` is `0x78`, `user` is `0x80`, `user_ns` is `0x88`, and
`group_info` is `0x90`.

## `sysctl_bootid` control entry

```text
random_table             0xffffffc00ac3a420
boot_id entry             random_table + 0x100
procname                  "boot_id"
data                      0xffffffc00ae87d65
maxlen                    0
mode                      0444
handler                   0xffffffc0098258a8
```

The aligned `rb_erase` write lands at `sysctl_bootid + 3`, which is inside
the 16-byte boot ID buffer. The profile records the control-entry address,
the data-field offset, and the aligned write target separately so the loader
and exploit do not confuse them.

## KSU loader link addresses

| Name | Address |
|---|---|
| `commit_creds` | `0xffffffc008315740` |
| `boot_id` control entry | `0xffffffc00ac3a520` |
| `sysctl_bootid` | `0xffffffc00ae87d65` |

## Cross-checks

- The H80GT v0.3.1 `kernelsu.ko` DWARF `task_struct`, `cred`, `mm_struct`,
  and `ctl_table` layouts match the measured HEY2 191 layout.
- The module's `208` undefined symbols all have names in the HEY2 191
  symbolized kernel.
- `struct module` is `0x400` bytes on this kernel; the module's
  `.gnu.linkonce.this_module` section is also `0x400` bytes.
- The module has an empty `__versions` section. The loader uses
  `init_module(flags=0)`; the IGNORE flags route through
  `try_to_force_load()` on this kernel and are not used.

## Reproducibility boundary

The raw boot image, kernel binary, symbolized ELF, and kallsyms capture are
not included. They contain device-specific data and are not needed to read
the source. Re-measure the profile from an exact matching image before making
any claim about another firmware.
