Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Tag = 'v0.4.0'
$Version = '0.4.0'
$ReleaseBaseUrl = 'https://github.com/bigtrader91/dicli-releases/releases/download/v0.4.0'
$SupportedTargets = 'linux-x86_64, windows-x86_64, macos-arm64, macos-x86_64'

function Read-RequiredOptionValue {
    param(
        [string[]] $Arguments,
        [int] $Index,
        [string] $Option
    )

    if (
        $Index + 1 -ge $Arguments.Count -or
        [string]::IsNullOrEmpty($Arguments[$Index + 1]) -or
        $Arguments[$Index + 1].StartsWith('--', [System.StringComparison]::Ordinal)
    ) {
        throw "missing value for $Option"
    }
    return $Arguments[$Index + 1]
}

function Read-DicliVersion {
    param([string] $Binary)

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Binary
    $start.Arguments = '--version'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) {
        throw 'could not start staged dicli --version'
    }
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'staged dicli --version timed out'
        }
        $stdout = $stdoutTask.Result
        $null = $stderrTask.Result
        if ($process.ExitCode -ne 0) {
            if ($process.ExitCode -eq -1073741515) {
                throw 'required Windows runtime DLL is missing (0xC0000135; commonly VCRUNTIME140.dll); install Microsoft Visual C++ Redistributable x64 from https://aka.ms/vc14/vc_redist.x64.exe, then retry'
            }
            throw 'staged dicli --version failed'
        }
    }
    finally {
        $process.Dispose()
    }

    if (-not $stdout.EndsWith("`n", [System.StringComparison]::Ordinal)) {
        throw 'staged version output needs a final LF'
    }
    $line = $stdout.Substring(0, $stdout.Length - 1)
    if ($line.EndsWith("`r", [System.StringComparison]::Ordinal)) {
        $line = $line.Substring(0, $line.Length - 1)
    }
    if (
        $line.Contains("`n") -or
        $line.Contains("`r") -or
        $line -notmatch '\Adicli (0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z'
    ) {
        throw 'staged version output is not one strict dicli semantic-version line'
    }
    return $line
}

function Save-HttpsFile {
    param(
        [string] $Uri,
        [string] $Destination
    )

    Add-Type -AssemblyName System.Net.Http
    $client = $null
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        $client = New-Object System.Net.Http.HttpClient
        $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode()
        $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outputStream = [System.IO.File]::Open(
            $Destination,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $inputStream.CopyTo($outputStream)
    }
    finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
    }
}

function Get-FileSha256 {
    param([string] $Path)

    $stream = $null
    $sha256 = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $digest = $sha256.ComputeHash($stream)
        return [System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) {
            $sha256.Dispose()
        }
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Invoke-Installer {
    param([string[]] $Arguments)

    $assetDir = $null
    $installDir = $null
    $requestedTarget = $null
    $assetDirSet = $false
    $installDirSet = $false
    $targetSet = $false
    $temporaryDir = $null
    $stagedInstall = $null
    $replacementBackup = $null
    $succeeded = $false
    $exitCode = 1

    try {
        for ($index = 0; $index -lt $Arguments.Count; $index++) {
            switch -CaseSensitive ($Arguments[$index]) {
                '--asset-dir' {
                    if ($assetDirSet) { throw 'duplicate option --asset-dir' }
                    $assetDir = Read-RequiredOptionValue $Arguments $index '--asset-dir'
                    $assetDirSet = $true
                    $index++
                }
                '--install-dir' {
                    if ($installDirSet) { throw 'duplicate option --install-dir' }
                    $installDir = Read-RequiredOptionValue $Arguments $index '--install-dir'
                    $installDirSet = $true
                    $index++
                }
                '--target' {
                    if ($targetSet) { throw 'duplicate option --target' }
                    $requestedTarget = Read-RequiredOptionValue $Arguments $index '--target'
                    $targetSet = $true
                    $index++
                }
                default {
                    throw 'unknown option'
                }
            }
        }

        if ($assetDirSet) {
            if (-not $installDirSet) {
                throw '--asset-dir requires --install-dir'
            }
        }
        elseif ($installDirSet -or $targetSet) {
            throw '--target and --install-dir are accepted only with --asset-dir'
        }

        if ($targetSet) {
            $target = $requestedTarget
        }
        else {
            $isWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                [System.Runtime.InteropServices.OSPlatform]::Windows
            )
            $isX64 = (
                [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq
                [System.Runtime.InteropServices.Architecture]::X64
            )
            if (-not $isWindows -or -not $isX64) {
                throw "unsupported platform; supported targets: $SupportedTargets"
            }
            $target = 'windows-x86_64'
        }

        if ($target -cne 'windows-x86_64') {
            throw "unsupported target; supported targets: $SupportedTargets"
        }

        $archiveName = 'dicli-v0.4.0-windows-x86_64.zip'
        $checksumName = "$archiveName.sha256"
        $prefix = 'dicli-v0.4.0-windows-x86_64'

        $temporaryDir = [System.IO.Path]::Combine(
            [System.IO.Path]::GetTempPath(),
            "dicli-install-v0.4.0-$([System.Guid]::NewGuid().ToString('N'))"
        )
        $null = [System.IO.Directory]::CreateDirectory($temporaryDir)
        $archivePath = [System.IO.Path]::Combine($temporaryDir, $archiveName)
        $checksumPath = [System.IO.Path]::Combine($temporaryDir, $checksumName)

        if ($assetDirSet) {
            $assetDir = [System.IO.Path]::GetFullPath($assetDir)
            $sourceArchive = [System.IO.Path]::Combine($assetDir, $archiveName)
            $sourceChecksum = [System.IO.Path]::Combine($assetDir, $checksumName)
            if (-not [System.IO.File]::Exists($sourceArchive)) {
                throw "missing asset: $sourceArchive"
            }
            if (-not [System.IO.File]::Exists($sourceChecksum)) {
                throw "missing asset: $sourceChecksum"
            }
            [System.IO.File]::Copy($sourceArchive, $archivePath, $false)
            [System.IO.File]::Copy($sourceChecksum, $checksumPath, $false)
        }
        else {
            Save-HttpsFile "$ReleaseBaseUrl/$archiveName" $archivePath
            Save-HttpsFile "$ReleaseBaseUrl/$checksumName" $checksumPath
        }

        $checksumBytes = [System.IO.File]::ReadAllBytes($checksumPath)
        $expectedChecksumSize = 64 + 2 + $archiveName.Length + 1
        if ($checksumBytes.Length -ne $expectedChecksumSize) {
            throw "invalid checksum file; expected one strict ASCII line for $archiveName"
        }
        foreach ($byte in $checksumBytes) {
            if ($byte -gt 127) {
                throw 'invalid checksum file; ASCII required'
            }
        }
        if ($checksumBytes[$checksumBytes.Length - 1] -ne 10) {
            throw 'invalid checksum file; final LF is required'
        }
        $checksumLine = [System.Text.Encoding]::ASCII.GetString(
            $checksumBytes,
            0,
            $checksumBytes.Length - 1
        )
        $checksumPattern = '\A(?<digest>[0-9a-f]{64})  ' +
            [System.Text.RegularExpressions.Regex]::Escape($archiveName) + '\z'
        $checksumMatch = [System.Text.RegularExpressions.Regex]::Match(
            $checksumLine,
            $checksumPattern,
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if (-not $checksumMatch.Success) {
            throw "invalid checksum file; expected '<sha256>  $archiveName'"
        }
        $expectedDigest = $checksumMatch.Groups['digest'].Value
        $actualDigest = Get-FileSha256 $archivePath
        if ($actualDigest -cne $expectedDigest) {
            throw "checksum mismatch for $archiveName"
        }

        Add-Type -AssemblyName System.IO.Compression
        $archiveStream = $null
        $zip = $null
        try {
            $archiveStream = [System.IO.File]::Open(
                $archivePath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            )
            $zip = [System.IO.Compression.ZipArchive]::new(
                $archiveStream,
                [System.IO.Compression.ZipArchiveMode]::Read,
                $false
            )
            $entries = @($zip.Entries)
            $expectedEntries = @(
                "$prefix/",
                "$prefix/LICENSE",
                "$prefix/README.md",
                "$prefix/THIRD-PARTY-LICENSES.html",
                "$prefix/dicli.exe"
            )
            if ($entries.Count -ne $expectedEntries.Count) {
                throw 'archive members differ from the required exact set'
            }
            for ($entryIndex = 0; $entryIndex -lt $expectedEntries.Count; $entryIndex++) {
                $entry = $entries[$entryIndex]
                if ($entry.FullName -cne $expectedEntries[$entryIndex]) {
                    throw 'archive members differ from the required exact set'
                }
                $externalAttributes = [System.BitConverter]::ToUInt32(
                    [System.BitConverter]::GetBytes([int] $entry.ExternalAttributes),
                    0
                )
                $fileType = (($externalAttributes -shr 16) -band 0xF000)
                if ($entryIndex -eq 0) {
                    if ($fileType -ne 0x4000 -or -not $entry.FullName.EndsWith('/')) {
                        throw 'archive root entry is not one exact directory'
                    }
                }
                elseif ($fileType -ne 0x8000 -or $entry.FullName.EndsWith('/')) {
                    throw "archive member is not an exact regular file: $($entry.FullName)"
                }
            }

            if (-not $assetDirSet) {
                if ([string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
                    throw 'LOCALAPPDATA is required for a per-user installation'
                }
                $installDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'dicli', 'bin')
            }
            $installDir = [System.IO.Path]::GetFullPath($installDir)
            $null = [System.IO.Directory]::CreateDirectory($installDir)
            $destination = [System.IO.Path]::Combine($installDir, 'dicli.exe')
            if ([System.IO.Directory]::Exists($destination)) {
                throw "install destination must be a regular file or absent: $destination"
            }
            if ([System.IO.File]::Exists($destination)) {
                $destinationAttributes = [System.IO.File]::GetAttributes($destination)
                if (
                    ($destinationAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
                ) {
                    throw "install destination cannot be a reparse point: $destination"
                }
            }
            $stagedInstall = [System.IO.Path]::Combine(
                $installDir,
                ".dicli-install-v0.4.0-$([System.Guid]::NewGuid().ToString('N')).tmp"
            )
            $binaryEntry = $entries[$expectedEntries.Count - 1]
            $binaryStream = $null
            $stagedStream = $null
            try {
                $binaryStream = $binaryEntry.Open()
                $stagedStream = [System.IO.File]::Open(
                    $stagedInstall,
                    [System.IO.FileMode]::CreateNew,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::None
                )
                $binaryStream.CopyTo($stagedStream)
            }
            finally {
                if ($null -ne $stagedStream) { $stagedStream.Dispose() }
                if ($null -ne $binaryStream) { $binaryStream.Dispose() }
            }
        }
        finally {
            if ($null -ne $zip) { $zip.Dispose() }
            if ($null -ne $archiveStream) { $archiveStream.Dispose() }
        }

        if ([System.IO.File]::Exists($destination)) {
            try {
                $existingVersion = Read-DicliVersion $destination
                [Console]::Out.WriteLine("Existing dicli at ${destination}: $existingVersion")
            }
            catch {
                [Console]::Out.WriteLine("Existing dicli at ${destination}: version unavailable")
            }
        }

        $stagedVersion = Read-DicliVersion $stagedInstall
        if ($stagedVersion -cne "dicli $Version") {
            throw "staged version mismatch; expected exactly 'dicli $Version'"
        }

        if ([System.IO.File]::Exists($destination)) {
            $replacementBackup = [System.IO.Path]::Combine(
                $installDir,
                ".dicli-install-v0.4.0-$([System.Guid]::NewGuid().ToString('N')).backup"
            )
            [System.IO.File]::Replace(
                $stagedInstall,
                $destination,
                $replacementBackup,
                $true
            )
            $stagedInstall = $null
            [System.IO.File]::Delete($replacementBackup)
            $replacementBackup = $null
        }
        else {
            [System.IO.File]::Move($stagedInstall, $destination)
            $stagedInstall = $null
        }

        [Console]::Out.WriteLine("Installed dicli $Version at $destination")
        $pathReady = $false
        foreach ($pathEntry in ($env:PATH -split ';')) {
            if (
                -not [string]::IsNullOrEmpty($pathEntry) -and
                [string]::Equals(
                    $pathEntry.TrimEnd('\', '/'),
                    $installDir.TrimEnd('\', '/'),
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            ) {
                $pathReady = $true
                break
            }
        }
        [Console]::Out.WriteLine('Manual next command:')
        if ($pathReady) {
            [Console]::Out.WriteLine('  dicli demo')
        }
        else {
            $quotedDestination = $destination.Replace("'", "''")
            $quotedInstallDir = $installDir.Replace("'", "''")
            [Console]::Out.WriteLine("  & '$quotedDestination' demo")
            [Console]::Out.WriteLine('To use dicli by name in this PowerShell session:')
            [Console]::Out.WriteLine("  `$env:PATH = '$quotedInstallDir;' + `$env:PATH")
        }

        $succeeded = $true
        $exitCode = 0
    }
    catch {
        [Console]::Error.WriteLine("dicli installer: error: $($_.Exception.Message)")
    }
    finally {
        if ($null -ne $stagedInstall -and [System.IO.File]::Exists($stagedInstall)) {
            try {
                [System.IO.File]::Delete($stagedInstall)
            }
            catch {
                [Console]::Error.WriteLine('dicli installer: error: could not remove atomic install stage')
                $exitCode = 1
            }
        }
        if (
            $null -ne $replacementBackup -and
            [System.IO.File]::Exists($replacementBackup)
        ) {
            [Console]::Error.WriteLine(
                "dicli installer: replacement backup retained at $replacementBackup"
            )
        }
        if ($null -ne $temporaryDir -and [System.IO.Directory]::Exists($temporaryDir)) {
            if ($succeeded) {
                try {
                    [System.IO.Directory]::Delete($temporaryDir, $true)
                }
                catch {
                    [Console]::Error.WriteLine('dicli installer: error: could not remove diagnostic temporary directory')
                    $exitCode = 1
                }
            }
            else {
                [Console]::Error.WriteLine("dicli installer: diagnostic files retained at $temporaryDir")
            }
        }
    }

    return $exitCode
}

exit (Invoke-Installer -Arguments $args)
