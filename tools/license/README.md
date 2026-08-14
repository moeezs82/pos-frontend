# CounterIQ Offline Machine Licensing

CounterIQ uses machine-bound offline activation. Customers do not need an activation server or internet connection.

## 1. Create the licensing authority — ONCE

From the CounterIQ frontend project on your trusted Windows computer:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\license\setup_license_keys.ps1
```

The script asks you to create a password and produces:

- `counteriq-license-private.pfx` — PRIVATE, password protected, used only by Application Owner to issue licenses.
- `counteriq-license-public.cer` — PUBLIC, safe to keep/share.
- It automatically embeds the public certificate in `lib/config/license_public_key.dart`.

By default the key files are saved outside the project at:

```text
%USERPROFILE%\Documents\CounterIQ-License-Authority\
```

Do **not** regenerate the authority for each customer. All released CounterIQ builds should keep the same public licensing certificate unless you intentionally perform a key rotation.

## 2. Back up the private key safely

Backing up the password-protected `.pfx` in Google Drive is acceptable for portability, provided:

- the PFX has a strong unique password;
- the password is **not** stored in the same Google Drive folder/file;
- preferably keep the password in a password manager and an additional offline recovery copy;
- never upload an unencrypted raw private key;
- never include the PFX in Git, source ZIPs, Flutter assets, the Go backend, or the MSIX package.

If the PFX is lost, you will not be able to create new licenses that validate against already-released CounterIQ builds.

## 3. Customer activation

On first launch CounterIQ shows a 64-hex machine code in grouped form. The customer sends that code to Application Owner.

Generate the customer's license:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\license\generate_license.ps1 `
  -Customer "Eadam Market" `
  -MachineCode "AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD-EEEEEEEE-FFFFFFFF-11111111-22222222" `
  -Edition local
```

The script asks for the private PFX password and creates a `.ciqlic` file. Send only that `.ciqlic` file to the customer.

For a server build use:

```powershell
-Edition server
```

A `local` license cannot activate a `server` build and vice versa.

## 4. Customer imports the license

The customer clicks **Import License File**, selects the `.ciqlic`, and CounterIQ verifies all of these offline:

1. the license was signed by the Application Owner private key;
2. the license belongs to this physical Windows computer;
3. the license edition matches the installed CounterIQ build;
4. the license has not expired, if an expiry was issued.

After activation the license is stored in CounterIQ's Windows application support directory and normal startup continues without internet access.

## 5. Number of installations

For 1 purchased device, issue 1 machine-bound license.
For 2 purchased devices, issue 2 licenses for the two machine codes.
For 5 purchased devices, issue 5 licenses.

The same `.ciqlic` cannot be copied to another computer because the machine fingerprint will not match.

## 6. Replaced hardware / Windows reinstall

The fingerprint prefers SMBIOS system UUID, BIOS serial, and motherboard serial. `MachineGuid` is used only as a fallback when the OEM exposes too little stable hardware information.

Major hardware replacement may create a new machine code. Treat that as a manual replacement/reissue according to your licensing policy.
