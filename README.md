# AD Enable User Extend Expiry + Reset Password

A PowerShell automation script for Identity & Access Management (IAM) that bulk-processes
Active Directory user accounts: extending near-expiry accounts and resetting passwords in
a single pass, with a summary report at the end.

Written for a recurring IAM task: batches of vendor/contractor accounts that need periodic
expiration renewal and credential rotation, normally done one-by-one through ADUC (Active
Directory Users and Computers).

## What it does

For each user in the input list, the script:

1. Looks up the account in AD (`Get-ADUser`) and reads `ipPhone`, `AccountExpirationDate`,
   and `DisplayName`.
2. Classifies the account type (`VENDOR` / `CONTRACT RESOURCE`) from the `ipPhone` attribute.
   Accounts that don't match either are skipped.
3. Compares the account's expiration date against **today + 21 days**:
   - **Expiring soon** (`<= today + 21 days`) → extends the expiration based on employee type:
     - `VENDOR` → **today + 3 months**
     - `CONTRACT RESOURCE` → **today + 1 year**
   - **Not expiring soon** → leaves the expiration date untouched, password reset only.
4. Generates a random 12-character password (mixed case, digits, symbols, no visually
   ambiguous characters).
5. Resets the password, unlocks the account, clears "must change password at next logon",
   and enables the account.
6. Appends the result to a report, printed at the end for every user processed.

## Flow

```
Get-ADUser → check ipPhone → check AccountExpirationDate
     |
Expires <= today + 21 days?
   YES → VENDOR? → set expiration = today + 3 months  ──┐
       → CR?     → set expiration = today + 1 year     ──┤
   NO  → skip extend                                    ──┤
                                                            v
                               Generate 12-character password
                                                            v
                  Reset password + Unlock + Clear "must change" + Enable
                                                            v
                                      Append to FinalReport
```

## Sample output

```
[+] Success: user01 (VENDOR)
[+] Success: user02 (VENDOR)

  UserID           : user01
  DisplayName      : Jane Doe
  Tipe Pegawai     : VENDOR
  Action           : EXTEND + RESET PASSWORD
  Acc Expires Lama : Tuesday, 30 June 2026
  Acc Expires Baru : Wednesday, 30 September 2026
  Password Baru    : ************
```

## Requirements

- Windows Server / Windows with the **ActiveDirectory** PowerShell module (RSAT)
- Run as a user with delegated permissions to modify account expiration, reset passwords,
  and enable/unlock accounts on the target OU
- PowerShell run as Administrator

## Usage

```powershell
.\Enable-ADUser-ExtendExpiry-ResetPassword.ps1
```

Edit `$Server` and `$UserList` at the top of the script before running.

## Notes

This is a generic, illustrative reference implementation. Domain names, hostnames, and
usernames are placeholders. Generated passwords exist only in memory and are printed to
the operator's console at runtime; no credentials, real environment details, or output
logs are included.
