# 把 App 跑到接著的 Android 手機上。
#
#   .\run.ps1              裝到手機上並開著 hot reload
#   .\run.ps1 auth         重新握手，讓手機跳出 USB 偵錯授權的對話框
#   .\run.ps1 devices      看認得到哪些裝置
#   .\run.ps1 --release    跑 release 版（比較快，但沒有 hot reload）
#
# 存在的理由：Flutter SDK 沒有進系統 PATH，JAVA_HOME / ANDROID_HOME 也沒有設成
# 使用者環境變數 —— 刻意不改系統設定，所以每次要用就在這裡設一次。
#
# 這支腳本自己印的字用英文：Windows 主控台預設 cp950，PowerShell 5.1 的輸出編碼
# 在啟動時就定了，腳本裡怎麼設都拉不回來。flutter 自己印的中文不受影響。

$ErrorActionPreference = 'Stop'

$env:JAVA_HOME = 'C:\dev\toolchain\jdk17'
$env:ANDROID_HOME = 'C:\dev\android-sdk'
$env:Path = "C:\Users\choue\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

$flutter = 'C:\Users\choue\flutter\bin\flutter.bat'
$adb = 'C:\dev\android-sdk\platform-tools\adb.exe'

function Get-AndroidDevice {
    # adb devices 的每一行是 "<serial>\t<state>"，第一行是標題。
    # state 有三種要分開處理：device(好了) / unauthorized(還沒按確定) / offline(線鬆了)
    $lines = & $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() }
    foreach ($line in $lines) {
        $parts = $line -split "`t"
        if ($parts.Count -ge 2) {
            [PSCustomObject]@{ Serial = $parts[0].Trim(); State = $parts[1].Trim() }
        }
    }
}

function Show-Help($devices) {
    $unauth = @($devices | Where-Object { $_.State -eq 'unauthorized' })
    if ($unauth.Count -gt 0) {
        Write-Output ''
        Write-Output "Phone $($unauth[0].Serial) is connected but NOT authorized."
        Write-Output 'On the PHONE, in this order:'
        Write-Output '  1. Unlock the screen - the dialog will not appear on a locked phone'
        Write-Output '  2. Look for "Allow USB debugging?" -> tick "always allow" -> OK'
        Write-Output '  3. No dialog? Pull down the notification shade, tap the USB notification,'
        Write-Output '     set USB mode to "File transfer / MTP" (charging-only never prompts)'
        Write-Output '  4. Still nothing? Developer options -> "Revoke USB debugging'
        Write-Output '     authorisations", then unplug and replug'
        Write-Output ''
        Write-Output 'Then run:  .\run.ps1 auth'
        return
    }
    Write-Output 'No Android device found. Checklist:'
    Write-Output '  1. Developer options ON  (tap Build number 7 times)'
    Write-Output '  2. USB debugging ON'
    Write-Output '  3. USB mode = File transfer / MTP  (charging-only will not work)'
    Write-Output '  4. Try a different cable - plenty of them are charge-only'
    Write-Output ''
    & $adb devices -l
}

Push-Location $PSScriptRoot
try {
    if ($args.Count -gt 0 -and $args[0] -eq 'auth') {
        Write-Output 'Restarting the adb server to force a fresh handshake...'
        & $adb kill-server | Out-Null
        Start-Sleep -Seconds 1
        & $adb start-server | Out-Null
        Start-Sleep -Seconds 3
        $d = @(Get-AndroidDevice)
        if (@($d | Where-Object { $_.State -eq 'device' }).Count -gt 0) {
            Write-Output "OK - $($d[0].Serial) is authorised. Run .\run.ps1"
        } else {
            Show-Help $d
        }
        return
    }

    $known = @('devices', 'doctor', 'logs', 'install', 'attach', 'screenshot')
    if ($args.Count -gt 0 -and $known -contains $args[0]) {
        & $flutter @args
        return
    }

    $devices = @(Get-AndroidDevice)
    $ready = @($devices | Where-Object { $_.State -eq 'device' })
    if ($ready.Count -eq 0) {
        Show-Help $devices
        return
    }

    # -d <serial> 是刻意的：不指定的話 flutter 會把 Windows 桌面和 Chrome 也當成
    # 候選裝置，順手去下載 250MB 的 Windows SDK ——  這個專案根本不會跑在那上面。
    $serial = $ready[0].Serial
    Write-Output "Device $serial ready. Building and installing (first run takes a few minutes)..."
    Write-Output 'Once it is up:  r = hot reload   R = restart   q = quit'
    Write-Output ''
    & $flutter run -d $serial @args
}
finally {
    Pop-Location
}
