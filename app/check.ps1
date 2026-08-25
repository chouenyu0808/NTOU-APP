# commit 前的把關：lint -> 測試。
#
# 用 `dart analyze` 而不是 `flutter analyze`：專案路徑裡的「桌面」是非 ASCII，
# Dart analysis server 走 LSP，長度標頭把 UTF-8 位元組當字元算，訊息一截斷就
# 丟 FormatException 然後整個 server 掛掉（exit 255）。dart analyze 不走 LSP。
#
# 個資檢查在 spike\check.py（那裡管 fixture）。這邊的 password_leak_test.dart
# 也會掃一次 fixture，所以跑 flutter test 就順便擋住了。
#
# 這支腳本自己印的字刻意用英文：Windows 主控台預設 cp950，而 PowerShell 5.1
# 的輸出編碼在啟動時就定了，腳本裡怎麼設都拉不回來。
# （flutter / dart 印的中文沒問題 —— 它們直接寫 UTF-8 bytes，不經過 PowerShell。）

$ErrorActionPreference = 'Stop'

$flutter = 'C:\Users\choue\flutter\bin\flutter.bat'
$dart = 'C:\Users\choue\flutter\bin\cache\dart-sdk\bin\dart.exe'

Push-Location $PSScriptRoot
try {
    Write-Output '== dart analyze =='
    & $dart analyze
    if ($LASTEXITCODE -ne 0) { throw 'dart analyze failed' }

    Write-Output ''
    Write-Output '== flutter test =='

    # OneDrive 偶爾會鎖住 build\，症狀是
    # "Flutter failed to delete a directory at build\unit_test_assets"。
    # 先刪掉，省得每次都要手動處理。
    if (Test-Path 'build') {
        Remove-Item -Recurse -Force 'build' -ErrorAction SilentlyContinue
    }

    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }

    Write-Output ''
    Write-Output 'OK - analyze clean, tests passed'
}
finally {
    Pop-Location
}
