# ============================================================
#  ENABLE USER: EXTEND ACCOUNT EXPIRATION + RESET PASSWORD
#  Domain  : <YOUR_AD_DOMAIN>
#  Logic   : If expires <= today + 21 days -> extend based on employee type
#              VENDOR             -> today + 3 months
#              CONTRACT RESOURCE  -> today + 1 year
#            If expires > today + 21 days  -> reset password only (skip extend)
# ============================================================

Import-Module ActiveDirectory
# [1] Load the ActiveDirectory module so cmdlets like Get-ADUser,
#     Set-ADAccountPassword, etc. are available

$Server = 'dc01.corp.example.com'
# [2] Target Domain Controller: all AD commands are directed here

$UserList = @(
    'jdoe'
    'asmith'
    # ...
)
# [3] SamAccountName list of users to process

$FinalReport = @()
# [4] Empty array to collect the per-user results

$Today     = (Get-Date).Date
$Threshold = $Today.AddDays(21)
# [5] $Today = today at 00:00:00
#     $Threshold = today + 21 days
#     Used as the cutoff: does the user need extending or not

foreach ($Sam in $UserList) {
# [6] Loop through each user in $UserList

    try {
        $User = Get-ADUser -Identity $Sam -Server $Server `
                -Properties ipPhone, AccountExpirationDate, DisplayName
        # [7] Pull the user from AD, specifically 3 extra fields:
        #     - ipPhone                : used to classify employee type (VENDOR/CR)
        #     - AccountExpirationDate  : account expiry date
        #     - DisplayName            : display name for the report

        $IPPhone = $User.ipPhone
        if ($IPPhone -match 'VENDOR') {
            $TipePegawai = 'VENDOR'
        }
        elseif ($IPPhone -match 'CONTRACT RESOURCE|CR') {
            $TipePegawai = 'CONTRACT RESOURCE'
        }
        else {
            # [8] If ipPhone doesn't match VENDOR/CR -> skip this user
            Write-Host "[!] $Sam - Unrecognized IP Phone value ('$IPPhone'). Skipping."
            continue
        }

        $CurrentExpire = $User.AccountExpirationDate
        if (-not $CurrentExpire) {
            # [9] If expiration is empty (Never) -> skip, nothing to compute
            Write-Host "[!] $Sam - Account expiration is empty (Never). Skipping."
            continue
        }

        $EndOfDate = $CurrentExpire.Date.AddDays(-1)
        # [10] AD stores the expiration date as +1 day from what's shown in the GUI
        #      Example: GUI shows "End of 10 Jan 2026" -> AD stores 11 Jan 2026
        #      So $EndOfDate = the actual GUI-displayed date (AD value - 1 day)

        $DoExtend = $EndOfDate -le $Threshold
        # [11] Compare: is the expiration <= today + 21 days?
        #      TRUE  -> needs extending
        #      FALSE -> expiration is far enough out, skip extend

        if ($DoExtend) {
            # Extension length depends on employee type
            if ($TipePegawai -eq 'VENDOR') {
                $NewEndOfDate = $Today.AddMonths(3)
            }
            else {
                $NewEndOfDate = $Today.AddYears(1)
            }
            $NewAccountExpires = $NewEndOfDate.AddDays(1)
            Set-ADAccountExpiration -Identity $Sam -DateTime $NewAccountExpires -Server $Server
            $ActionLabel = 'EXTEND + RESET PASSWORD'
            # [12] If extending:
            #      - NewEndOfDate = today + 3 months (VENDOR) or today + 1 year (CONTRACT RESOURCE)
            #        (what will show in the GUI)
            #      - NewAccountExpires = NewEndOfDate + 1 day (the value AD actually stores)
            #      - Set-ADAccountExpiration -> apply to AD
        }
        else {
            $NewEndOfDate = $EndOfDate
            $ActionLabel  = 'RESET PASSWORD ONLY'
            # [13] If expiration is still far out -> don't change the date,
            #      log it as reset-only
        }

        # ── PASSWORD GENERATOR ────────────────────────────────────────
        $FirstChar      = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray() | Get-Random -Count 1
        $Upper          = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray() | Get-Random -Count 3
        $Lower          = 'abcdefghijkmnpqrstuvwxyz'.ToCharArray() | Get-Random -Count 4
        $Num            = '23456789'.ToCharArray()                   | Get-Random -Count 2
        $Sym            = '@#$%'.ToCharArray()                       | Get-Random -Count 2
        $RemainingChars = ($Upper + $Lower + $Num + $Sym) | Get-Random -Count 11
        $RawPassword    = $FirstChar + (-join $RemainingChars)
        $SecurePass     = ConvertTo-SecureString $RawPassword -AsPlainText -Force
        # [14] Generate a random 12-character password:
        #      - Char 1     : uppercase letter (mandatory)
        #      - Chars 2-4  : 3 random uppercase letters
        #      - Chars 5-8  : 4 random lowercase letters
        #      - Chars 9-10 : 2 random digits (no 0/1 to avoid ambiguity)
        #      - Chars 11-12: 2 random symbols from @#$%
        #      Everything except FirstChar gets reshuffled -> Get-Random -Count 11
        #      Single quotes are used so PowerShell doesn't expand $

        Set-ADAccountPassword -Identity $Sam -NewPassword $SecurePass -Reset -Server $Server
        # [15] Reset the user's password to the newly generated one

        Unlock-ADAccount -Identity $Sam -Server $Server
        # [16] Unlock the account if it was locked out (e.g. too many bad password attempts)

        Set-ADUser -Identity $Sam -ChangePasswordAtLogon $false -Server $Server
        # [17] Uncheck "User must change password at next logon"
        #      Technically: sets pwdLastSet = -1 (not 0)
        #      0  = must change password at next logon
        #      -1 = no change required

        Enable-ADAccount -Identity $Sam -Server $Server
        # [18] Enable the account if it was previously disabled

        $FinalReport += [PSCustomObject]@{
            UserID         = $Sam
            DisplayName    = $User.DisplayName
            TipePegawai    = $TipePegawai
            Action         = $ActionLabel
            AccExpiresLama = $EndOfDate.ToString('dddd, dd MMMM yyyy')
            AccExpiresBaru = $NewEndOfDate.ToString('dddd, dd MMMM yyyy')
            PasswordBaru   = $RawPassword
        }
        # [19] Append this user's result to $FinalReport for the final summary
    }
    catch {
        Write-Host "[!] Failed: $Sam - $($_.Exception.Message)"
        # [20] If an error occurs for a user -> print the error
        #      and continue with the next one (don't stop the whole run)
    }
}

# [21] Print a summary of all successfully processed users
foreach ($r in $FinalReport) {
    Write-Host "  UserID           : $($r.UserID)"
    Write-Host "  DisplayName      : $($r.DisplayName)"
    Write-Host "  Tipe Pegawai     : $($r.TipePegawai)"
    Write-Host "  Action           : $($r.Action)"
    Write-Host "  Acc Expires Lama : $($r.AccExpiresLama)"
    Write-Host "  Acc Expires Baru : $($r.AccExpiresBaru)"
    Write-Host "  Password Baru    : $($r.PasswordBaru)"
}
