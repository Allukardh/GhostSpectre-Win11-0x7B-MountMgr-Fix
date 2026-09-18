# GhostSpectre Windows 11 0x7B MountMgr Fix

A focused recovery tool and case study for a specific **INACCESSIBLE_BOOT_DEVICE (0x0000007B)** failure observed on **Ghost Spectre Windows 11 25H2** when the `mountmgr` service registry entry disappears from the offline SYSTEM hive while `mountmgr.sys` is still present.

> **This is not a universal 0x7B fix.**
>
> Error 0x7B has many possible causes. This repository only targets the specific failure documented below. The script checks for that condition first and aborts without changing the offline Windows installation if `Services\mountmgr` already exists.

## Verified environment

The recovery documented here was reproduced and confirmed on:

- Ghost Spectre Windows 11 25H2
- OS build **26200.9168**
- Lenovo ThinkPad T14 Gen 1
- NVMe system disk
- UEFI/GPT installation

A second Lenovo machine using the **same Ghost Spectre image/build** was used as a known-good comparison.

This issue may also occur on earlier **Windows 11 25H2 / 26200.x** builds, but **26200.9168 is the build directly verified by this repository**.

## Symptoms

Windows fails during boot with:

```text
INACCESSIBLE_BOOT_DEVICE
Bug Check: 0x0000007B
```

In the confirmed case:

- normal boot failed with 0x7B;
- Safe Mode also failed with the same 0x7B;
- the NVMe controller and Microsoft `stornvme` binding were correct;
- NTFS passed read-only CHKDSK;
- GPT layout was valid;
- the Windows partition and drive-letter mappings were correct;
- rebuilding the BCD did **not** fix the 0x7B;
- `C:\Windows\System32\drivers\mountmgr.sys` still existed;
- but `HKLM\SYSTEM\CurrentControlSet\Services\mountmgr` was missing.

After restoring the missing `mountmgr` service definition, Windows booted normally and `mountmgr` was confirmed **RUNNING**.

## Root cause confirmed in this case

The immediate failure was the missing Mount Manager service registry entry:

```text
HKLM\SYSTEM\CurrentControlSet\Services\mountmgr
```

The expected service definition is:

```text
Description     @%SystemRoot%\system32\drivers\mountmgr.sys,-101
DisplayName     @%SystemRoot%\system32\drivers\mountmgr.sys,-100
ErrorControl    0x3
Group           System Bus Extender
ImagePath       System32\drivers\mountmgr.sys
Start           0x0
Type            0x1
```

The driver file itself was still present:

```text
C:\Windows\System32\drivers\mountmgr.sys
```

## Quick recovery

Download **`FIX-0x7B-MOUNTMGR.cmd`** from the latest GitHub Release and copy it to a WinPE/Ghost boot USB.

Boot into WinPE / Ghost Boot Menu, open **Command Prompt as Administrator**, and run:

```bat
FIX-0x7B-MOUNTMGR.cmd
```

The script attempts to locate a unique offline Windows installation automatically.

If more than one Windows installation is found, specify the correct drive explicitly:

```bat
FIX-0x7B-MOUNTMGR.cmd C:
```

### What the script does

The script:

1. finds the offline Windows installation;
2. verifies that `mountmgr.sys` exists;
3. loads the offline SYSTEM hive under a temporary key;
4. reads `Select\Current` to determine the active ControlSet;
5. checks whether `Services\mountmgr` is actually missing;
6. **aborts without modifying anything if `mountmgr` already exists**;
7. saves a full SYSTEM hive backup before repair;
8. restores the `mountmgr` service definition, preferring the running WinPE's known-good definition;
9. verifies the restored key;
10. unloads the offline SYSTEM hive.

The script does **not** modify:

- GPT partition entries;
- partition sizes;
- drive-letter mappings;
- BCD;
- EFI files;
- NTFS metadata;
- user files.

## Backup created by the tool

Before changing the registry, the script writes:

```text
<WindowsDrive>:\SYSTEM-before-mountmgr.hiv
```

Keep this file until the recovered system has been fully verified.

## After a successful repair

Perform a complete shutdown and power the PC on again.

After Windows starts, verify from an elevated Command Prompt:

```bat
sc query mountmgr
reg query HKLM\SYSTEM\CurrentControlSet\Services\mountmgr
```

A healthy system should report `mountmgr` as a kernel driver with `STATE: RUNNING`, and the registry service should contain `Start=0` and `Type=1`.

## Confirmed recovery case

### Before

- `mountmgr.sys`: present
- `Services\mountmgr`: missing
- Windows boot: `INACCESSIBLE_BOOT_DEVICE (0x7B)`

### After restoring `Services\mountmgr`

- `mountmgr`: RUNNING
- Windows booted normally
- no partition recreation
- no Windows reinstall
- no formatting
- no user-data loss

## Important limitations

Do **not** assume every `0x7B` is caused by MountMgr.

If the script reports that `Services\mountmgr` already exists, stop and diagnose the machine for another 0x7B cause. Examples can include storage-controller drivers, firmware/storage-mode changes, filter drivers, inaccessible or corrupted boot volumes, or other early-boot storage failures.

This project intentionally refuses to overwrite an existing `mountmgr` service configuration.

## Repository layout

```text
.
├── README.md
├── LICENSE
├── fix/
│   └── FIX-0x7B-MOUNTMGR.cmd
└── docs/
    └── TECHNICAL-NOTES.md
```

## Background

This repository exists because this exact failure had previously led to unnecessary Windows reinstalls and data loss. The objective is to preserve a small, auditable and repeatable recovery procedure before formatting a machine.

The **trigger that caused the `mountmgr` registry service entry to disappear is still under investigation**. Partition resizing occurred in the history of the confirmed case, but this repository does **not** claim that resizing itself deletes the service key.

## References

- Microsoft — Bug Check 0x7B: INACCESSIBLE_BOOT_DEVICE  
  https://learn.microsoft.com/windows-hardware/drivers/debugger/bug-check-0x7b--inaccessible-boot-device
- Microsoft — HKLM\SYSTEM\CurrentControlSet\Services registry tree  
  https://learn.microsoft.com/windows-hardware/drivers/install/hklm-system-currentcontrolset-services-registry-tree
- Microsoft — Mount Manager / storage documentation  
  https://learn.microsoft.com/windows-hardware/drivers/storage/supporting-mount-manager-requests-in-a-storage-class-driver

## Disclaimer

This is an independent community recovery project. It is not affiliated with Microsoft or Ghost Spectre.

Use recovery tools at your own risk. A SYSTEM hive backup is created before the repair, but important data should still be backed up whenever possible.

## License

MIT
