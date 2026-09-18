# Technical Notes

## Scope

These notes document one **confirmed** recovery case for:

```text
INACCESSIBLE_BOOT_DEVICE
Bug Check 0x0000007B
```

on **Ghost Spectre Windows 11 25H2, OS build 26200.9168**.

The immediate cause confirmed in this case was a missing `mountmgr` service registry key while the actual `mountmgr.sys` driver file remained present.

This document intentionally separates **confirmed evidence** from **unconfirmed trigger hypotheses**.

## Confirmed machine

- Lenovo ThinkPad T14 Gen 1
- Ghost Spectre Windows 11 25H2
- OS build 26200.9168
- UEFI/GPT boot
- NVMe system disk
- Microsoft Standard NVM Express Controller
- `stornvme` storage miniport

A second Lenovo machine using the same Ghost Spectre image/build was available as a working comparison.

## Failure behavior

The affected machine repeatedly failed boot with:

```text
INACCESSIBLE_BOOT_DEVICE
0x0000007B
```

Safe Mode failed with the same error.

The machine had previously undergone a Windows Disk Management resize of the system disk. The resize itself occurred before the failure and Windows continued operating afterward, so this repository does **not** claim that the resize directly removed the `mountmgr` service registration.

## Storage and boot checks that did not identify the fault

Before the MountMgr registry anomaly was found, the following were checked.

### NVMe controller

The WinPE environment detected the controller as:

```text
Standard NVM Express Controller
Driver: stornvme.inf
```

The offline Windows registry also bound the same PCI NVMe controller to:

```text
Service = stornvme
```

This weakened the theory that the system was failing because of Intel RST/VMD/AHCI controller-mode mismatch.

### Boot-start storage stack

Critical components such as the following were present and registered as boot drivers:

- `stornvme`
- `partmgr`
- `volmgr`
- `volsnap`
- `volume`
- `fvevol`
- `EhStorClass`

### Filesystem

Read-only CHKDSK completed successfully with no filesystem errors or bad sectors reported.

### GPT

The raw GPT was inspected with GPT fdisk (`gdisk`).

The partition entry sequence was contiguous and valid. The Windows partition was GPT entry 3, matching the Windows boot metadata. `gdisk v` reported no GPT problems.

This ruled out the investigated "blank GPT entry before the boot partition" failure mode for this machine.

### MountedDevices

The offline SYSTEM hive's persistent mappings for `C:` and `D:` matched the current volume identities reported by WinPE.

Therefore there was no evidence that stale `C:` / `D:` mappings were the cause.

### BCD

The BCD was coherent and pointed to the correct Windows installation.

A clean BCD regeneration was tested and **did not eliminate the 0x7B**, strongly suggesting that the immediate failure was later in early boot.

The original BCD was subsequently restored.

## The decisive difference

On the failing T14:

```text
C:\Windows\System32\drivers\mountmgr.sys
```

existed.

However:

```text
HKLM\SYSTEM\CurrentControlSet\Services\mountmgr
```

was absent from the offline SYSTEM hive.

The same key was also absent from both available offline ControlSets that were checked.

By contrast, the working comparison machine had:

```text
Description     @%SystemRoot%\system32\drivers\mountmgr.sys,-101
DisplayName     @%SystemRoot%\system32\drivers\mountmgr.sys,-100
ErrorControl    REG_DWORD 0x3
Group           System Bus Extender
ImagePath       System32\drivers\mountmgr.sys
Start           REG_DWORD 0x0
Type            REG_DWORD 0x1
```

and:

```text
sc query mountmgr
STATE: RUNNING
TYPE: KERNEL_DRIVER
```

The WinPE recovery environment also contained the same normal `mountmgr` service definition.

## Repair performed

The offline SYSTEM hive was loaded into a temporary registry key.

Before modification, a complete hive backup was saved.

The missing `mountmgr` service definition was then copied from the running WinPE registry into the active offline ControlSet.

Equivalent manual sequence, assuming the offline Windows installation is `C:` and the active set is `ControlSet001`:

```bat
reg load HKLM\OFFSYS C:\Windows\System32\Config\SYSTEM

reg save HKLM\OFFSYS C:\SYSTEM-before-mountmgr.hiv /y

reg copy HKLM\SYSTEM\CurrentControlSet\Services\mountmgr ^
  HKLM\OFFSYS\ControlSet001\Services\mountmgr /s /f

reg query HKLM\OFFSYS\ControlSet001\Services\mountmgr

reg unload HKLM\OFFSYS
```

The public recovery script automates these steps but also discovers the active ControlSet instead of assuming `ControlSet001`.

## Result

After the missing service key was restored and the machine was fully powered off and started again:

- the 0x7B disappeared;
- Windows booted normally;
- no format or reinstall was required;
- no partition reconstruction was required;
- `mountmgr` was confirmed RUNNING inside the recovered Windows installation.

This gives strong experimental evidence that the **missing MountMgr service registration was the immediate cause of this machine's 0x7B**.

## What remains unknown

The process that removed the `Services\mountmgr` key has not yet been identified.

Known context includes:

- Ghost Spectre Windows 11 25H2;
- previous partition resizing;
- storage/device re-enumeration activity in Windows logs after the resize;
- multiple previous 0x7B incidents on other machines after storage-layout changes.

None of those facts, by themselves, proves what deleted the service key.

The repository therefore deliberately describes the **repair and confirmed immediate cause**, not an unproven upstream trigger.

## Why the script is guarded

A 0x7B can have many causes.

The tool will only perform this recovery when all of the following are true:

1. an offline Windows SYSTEM hive is found;
2. `mountmgr.sys` exists;
3. the active ControlSet can be determined;
4. `Services\mountmgr` is missing.

If `mountmgr` already exists, the tool exits without overwriting it.

## Recovery philosophy

The intended order is:

```text
0x7B
  |
  +-- mountmgr.sys missing? ----------------> stop; different failure
  |
  +-- Services\mountmgr already exists? ----> stop; different failure
  |
  +-- Services\mountmgr missing
         |
         +-- back up SYSTEM hive
         +-- restore service definition
         +-- verify
         +-- unload hive
         +-- full shutdown / power on
```

This keeps the repair narrowly scoped and avoids turning a specific fix into a generic registry modification.
