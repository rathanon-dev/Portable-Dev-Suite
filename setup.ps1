# ======================================================================
# SETUP v22: Enterprise CLI UX Edition (Modernized)
# Combined: CUDA, cuDNN, Git, Python, TCP Proxy & Auto-Cleanup
# Strict Compatibility: Windows PowerShell 5.1 (Win 10 / 11)
# ======================================================================
[CmdletBinding(PositionalBinding=$false)]
param (
    [bool]$EnableProxy = $true,
    [string]$ProxyServerUrl = "http://192.168.1.10:8080",
    [string]$DefaultPython = "3.12",
    [string]$DefaultCuda = "12",
    [Alias("h")][switch]$Help,
    [Alias("c")][switch]$Check,
    [Alias("l")][switch]$List,
    [Alias("i")][switch]$Install,
    [Alias("v")][string]$TargetVersion = "",
    [Alias("f")][switch]$Force,
    [Alias("y")][switch]$AutoYes,
    [Alias("e")][switch]$EnvMode,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

# Enforce TLS 1.2 for all web requests (PS 5.1 Standard)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = $PSScriptRoot
if ([string]::IsNullOrEmpty($root)) { $root = (Get-Location).Path }

# --------------------------------------------------------
# 1. Path Configurations
# --------------------------------------------------------
$toolsDir      = Join-Path $root "tools"
$mainTempDir   = Join-Path $root "temp"
$7zDir         = Join-Path $toolsDir "7zip"
$7zExe         = Join-Path $7zDir "7za.exe"
$aria2Dir      = Join-Path $toolsDir "aria2"
$aria2Exe      = Join-Path $aria2Dir "aria2c.exe"
$gitDir        = Join-Path $toolsDir "git"
$pythonDir     = Join-Path $toolsDir "python"
$pipDir        = Join-Path $pythonDir "Scripts"
$cudaBinDir    = Join-Path $toolsDir "nvidia\cuda\bin"
$cudnnBinDir   = Join-Path $toolsDir "nvidia\cudnn\bin"
$cudaStateFile = Join-Path $toolsDir "nvidia\cuda_state.txt"

$folders = @($toolsDir, $mainTempDir, $7zDir, $aria2Dir, $gitDir, $pythonDir, $cudaBinDir, $cudnnBinDir)
foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) { 
        New-Item -ItemType Directory -Force -Path $folder | Out-Null 
    }
}

$eliteCudaComponents = @(
    "cuda_cudart", "libcublas", "libcufft", "libcurand", 
    "libcusolver", "libcusparse", "libnpp", "libnvjpeg", 
    "cuda_nvrtc", "libnvjitlink", "libnvptxcompiler", 
    "libnvvm", "libnvfatbin"
)

$cudnnTargets = @(
    "cudnn_adv64_*.dll", "cudnn_cnn64_*.dll", "cudnn_engines_precompiled64_*.dll",
    "cudnn_engines_runtime_compiled64_*.dll", "cudnn_graph64_*.dll", "cudnn_heuristic64_*.dll",
    "cudnn_ops64_*.dll", "cudnn64_*.dll"
)

# --------------------------------------------------------
# 2. Smart Proxy & Network Engine
# --------------------------------------------------------
$script:IsProxyOnline = $null

function Test-ProxyHealth {
    [CmdletBinding(PositionalBinding=$false)]
    param ()
    if (-not $EnableProxy) { return $false }
    if ($null -ne $script:IsProxyOnline) { return $script:IsProxyOnline }

    try {
        $uri = [System.Uri]$ProxyServerUrl
        $tcp = New-Object Net.Sockets.TcpClient
        $async = $tcp.BeginConnect($uri.Host, $uri.Port, $null, $null)
        $success = $async.AsyncWaitHandle.WaitOne(1500, $true)
        
        if ($success -and $tcp.Connected) {
            $tcp.EndConnect($async)
            $script:IsProxyOnline = $true
            Write-Host " [PROXY] Local CDN Gateway Connected ($ProxyServerUrl)" -ForegroundColor Green
        }
        else {
            $script:IsProxyOnline = $false
            Write-Host " [PROXY WARN] Gateway Timeout! Auto-switching to Direct Internet Mode." -ForegroundColor Yellow
        }
        $tcp.Close()
    }
    catch {
        $script:IsProxyOnline = $false
        Write-Host " [PROXY WARN] Gateway Unreachable! Auto-switching to Direct Internet Mode." -ForegroundColor Yellow
    }
    return $script:IsProxyOnline
}

function Get-ProxifiedUrl {
    [CmdletBinding(PositionalBinding=$false)]
    param ([string]$OriginalUrl)
    
    if ([string]::IsNullOrWhiteSpace($OriginalUrl)) { return $OriginalUrl }
    
    $cleanProxy = $ProxyServerUrl.TrimEnd('/')
    if ($OriginalUrl.StartsWith($cleanProxy)) { return $OriginalUrl }
    
    if (Test-ProxyHealth) {
        return "$cleanProxy/$OriginalUrl"
    }
    return $OriginalUrl
}

# --------------------------------------------------------
# 2.5 I/O Seam Wrappers (Step 2)
# --------------------------------------------------------

function Invoke-SetupRestMethod {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [hashtable]$Headers = @{},
        [string]$UserAgent = "Mozilla/5.0"
    )
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -UserAgent $UserAgent -UseBasicParsing -ErrorAction Stop
}

function Invoke-SetupWebRequest {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [string]$OutFile = "",
        [string]$UserAgent = "Mozilla/5.0"
    )
    if ($OutFile) {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UserAgent $UserAgent -UseBasicParsing -ErrorAction Stop
    } else {
        return Invoke-WebRequest -Uri $Uri -UserAgent $UserAgent -UseBasicParsing -ErrorAction Stop
    }
}

function Invoke-SetupCommand {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory=$true)][string]$CommandPath,
        [string[]]$ArgumentList = @(),
        [switch]$NoOutput,
        [switch]$RedirectError,
        [switch]$AsString,
        [switch]$Parse7ZipProgress,
        [string]$ProgressLabel = "Processing"
    )
    
    if ($Parse7ZipProgress) {
        $lastPercent = -1
        & $CommandPath @ArgumentList | ForEach-Object {
            if ($_ -match '(\d+)%') {
                $percent = [int]$Matches[1]
                if ($percent -ne $lastPercent -and $percent -le 100) {
                    Write-Host -NoNewline "`r     [>] $ProgressLabel... $percent% Complete  "
                    $lastPercent = $percent
                }
            }
        }
        Write-Host -NoNewline "`r     [>] $ProgressLabel... 100% Complete  `n"
        return
    }
    
    if ($RedirectError -and $AsString) {
        $result = & $CommandPath @ArgumentList 2>&1 | Out-String
        return $result
    } elseif ($AsString) {
        $result = & $CommandPath @ArgumentList | Out-String
        return $result
    } elseif ($NoOutput) {
        & $CommandPath @ArgumentList 2>&1 | Out-Null
    } elseif ($RedirectError) {
        & $CommandPath @ArgumentList 2>&1
    } else {
        & $CommandPath @ArgumentList
    }
}

function Write-SetupStatus {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("OK", "WARN", "ERROR", "INFO", "RAW", "SUB", "PROMPT")]
        [string]$Type = "RAW",
        [System.ConsoleColor]$Color = [System.ConsoleColor]::White,
        [switch]$NoNewLine
    )
    
    $prefix = ""
    $fgColor = $Color
    
    if ($Type -eq "OK") { $prefix = " [+] "; $fgColor = "Green" }
    if ($Type -eq "WARN") { $prefix = " [!] "; $fgColor = "Yellow" }
    if ($Type -eq "ERROR") { $prefix = " [-] "; $fgColor = "Red" }
    if ($Type -eq "INFO") { $prefix = " [*] "; $fgColor = "Cyan" }
    if ($Type -eq "SUB") { $prefix = "     [>] "; $fgColor = "Gray" }
    if ($Type -eq "PROMPT") { $prefix = " [?] "; $fgColor = "Magenta" }
    
    $outMsg = "$prefix$Message"
    if ($Type -eq "RAW") { $outMsg = $Message }
    
    if ($NoNewLine) {
        Write-Host $outMsg -ForegroundColor $fgColor -NoNewline
    } else {
        Write-Host $outMsg -ForegroundColor $fgColor
    }
}

function Invoke-FallbackDownload {
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [Parameter(Mandatory=$true)][string]$DownloadUrl, 
        [Parameter(Mandatory=$true)][string]$OutFilePath
    )
    
    $effectiveUrl = Get-ProxifiedUrl -OriginalUrl $DownloadUrl

    if (Test-Path $aria2Exe) {
        try {
            Write-SetupStatus -Message "Attempting download via Aria2..." -Type INFO
            $targetDir = Split-Path $OutFilePath -Parent
            $targetFile = Split-Path $OutFilePath -Leaf
            Invoke-SetupCommand -CommandPath $aria2Exe -ArgumentList @($effectiveUrl, "-o", $targetFile, "-d", $targetDir, "-x", "1", "-s", "1", "--console-log-level=warn", "--summary-interval=0")
            if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFilePath)) { return }
        }
        catch {}
    }
    
    $curlCmd = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($curlCmd) {
        try {
            Write-SetupStatus -Message "Attempting download via cURL..." -Type INFO
            Invoke-SetupCommand -CommandPath $curlCmd.Source -ArgumentList @("-L", "-f", "-A", "Mozilla/5.0", "-s", $effectiveUrl, "-o", $OutFilePath)
            if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFilePath)) { return }
        }
        catch {}
    }
    
    try {
        Write-SetupStatus -Message "Attempting download via PowerShell Native..." -Type INFO
        Invoke-SetupWebRequest -Uri $effectiveUrl -OutFile $OutFilePath -UserAgent "Mozilla/5.0"
        if (Test-Path $OutFilePath) { return }
    }
    catch {}
    
    Write-SetupStatus -Message "Download failed across ALL engines for URL: $DownloadUrl" -Type ERROR
    exit 1
}

function Start-Aria2BatchDownload {
    [CmdletBinding(PositionalBinding=$false)]
    param ([string[]]$QueueLines)
    
    if ($QueueLines.Count -eq 0) { return }
    
    $queueFile = Join-Path $mainTempDir "aria2_queue.txt"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($queueFile, $QueueLines, $utf8NoBom)
    
    Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Cyan
    Write-SetupStatus -Message "Handing over $($QueueLines.Count / 3) files to Aria2 Engine" -Type OK
    if (Test-ProxyHealth) { Write-SetupStatus -Message "[PROXY] Active Gateway: $ProxyServerUrl" -Type INFO }
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan
    
    Invoke-SetupCommand -CommandPath $aria2Exe -ArgumentList @("--input-file=$queueFile", "-j", "4", "-x", "1", "-s", "1", "--console-log-level=notice", "--summary-interval=3")
    Remove-Item $queueFile -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------
# 3. Core Bootstrappers & Python Engine
# --------------------------------------------------------
function Clear-TempDirectory {
    [CmdletBinding(PositionalBinding=$false)]
    param ()
    if (Test-Path $mainTempDir) {
        Write-SetupStatus -Message "Removing temporary directory $mainTempDir..." -Type INFO
        Remove-Item -Path $mainTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-DefaultTools {
    [CmdletBinding(PositionalBinding=$false)]
    param ([switch]$ForceInstall)
    
    if (-not (Test-Path $7zExe) -or $ForceInstall) {
        Write-SetupStatus -Message "Setting up 7-Zip Core Engine..." -Type INFO
        $tempZip = Join-Path $mainTempDir "7z_temp.zip"
        $tempExtract = Join-Path $mainTempDir "7z_temp_extract"
        $nugetUrl = Get-ProxifiedUrl -OriginalUrl "https://azuresearch-usnc.nuget.org/query?q=packageid:7-Zip.CommandLine&prerelease=false"
        $latestVersion = (Invoke-SetupRestMethod -Uri $nugetUrl).data[0].version
        
        Invoke-FallbackDownload -DownloadUrl "https://www.nuget.org/api/v2/package/7-Zip.CommandLine/$latestVersion" -OutFilePath $tempZip
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
        Move-Item -Path (Join-Path $tempExtract "tools\7za.exe") -Destination $7zExe -Force
        Remove-Item -Path $tempZip, $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        Write-SetupStatus -Message "7-Zip Engine Deployed." -Type OK
    }

    if (-not (Test-Path $aria2Exe) -or $ForceInstall) {
        Write-SetupStatus -Message "Setting up Aria2 Engine..." -Type INFO
        $tempZip = Join-Path $mainTempDir "aria2_temp.zip"
        $tempExtract = Join-Path $mainTempDir "aria2_temp_extract"
        $apiUrl = Get-ProxifiedUrl -OriginalUrl "https://api.github.com/repos/aria2/aria2/releases/latest"
        $asset = (Invoke-SetupRestMethod -Uri $apiUrl).assets | Where-Object { $_.name -match "win-64bit.*\.zip$" } | Select-Object -First 1
        
        Invoke-FallbackDownload -DownloadUrl $asset.browser_download_url -OutFilePath $tempZip
        
        if (Test-Path $7zExe) { 
            Invoke-SetupCommand -CommandPath $7zExe -ArgumentList @("x", $tempZip, "-y", "-o$tempExtract", "-bsp1", "-bso0") -Parse7ZipProgress -ProgressLabel "Unpacking Aria2"
        } else { 
            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force 
        }
        
        Move-Item -Path (Get-ChildItem -Path $tempExtract -Filter "aria2c.exe" -Recurse).FullName -Destination $aria2Exe -Force
        Remove-Item -Path $tempZip, $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        Write-SetupStatus -Message "Aria2 Engine Deployed." -Type OK
    }

    $gitBin = Join-Path $gitDir "cmd\git.exe"
    if (-not (Test-Path $gitBin)) { $gitBin = Join-Path $gitDir "bin\git.exe" }
    if (-not (Test-Path $gitBin) -or $ForceInstall) {
        Write-SetupStatus -Message "Setting up Git Portable..." -Type INFO
        $gitApiUrl = Get-ProxifiedUrl -OriginalUrl "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $gitAsset = (Invoke-SetupRestMethod -Uri $gitApiUrl).assets | Where-Object { $_.name -match "PortableGit-.*-64-bit\.7z\.exe" } | Select-Object -First 1
        $tempGitFile = Join-Path $mainTempDir $gitAsset.name
        
        Invoke-FallbackDownload -DownloadUrl $gitAsset.browser_download_url -OutFilePath $tempGitFile
        if (Test-Path $gitDir) { Remove-Item -Path "$gitDir\*" -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $7zExe) { Invoke-SetupCommand -CommandPath $7zExe -ArgumentList @("x", $tempGitFile, "-y", "-o$gitDir", "-bsp1", "-bso0") -Parse7ZipProgress -ProgressLabel "Unpacking Git Portable" }
        Remove-Item -Path $tempGitFile -Force -ErrorAction SilentlyContinue
        Write-SetupStatus -Message "Git Portable Deployed." -Type OK
    }
}

function Get-PythonVersions {
    [CmdletBinding(PositionalBinding=$false)]
    param ()
    
    $apiUrl = Get-ProxifiedUrl -OriginalUrl "https://api.nuget.org/v3-flatcontainer/python/index.json"
    try {
        $index = Invoke-SetupRestMethod -Uri $apiUrl
        if (-not $index -or -not $index.versions) { return $null }
        return ($index.versions | Where-Object { $_ -match '^[0-9]+\.[0-9]+\.[0-9]+$' })
    }
    catch { return $null }
}

function Install-Python {
    [CmdletBinding(PositionalBinding=$false)]
    param ([string]$Version)
    
    Write-SetupStatus -Message "`n[PROCESS] Fetching Portable Python v$Version from NuGet..." -Type INFO
    try {
        $nupkgName = "python.$Version.nupkg"
        $dlUrl = "https://api.nuget.org/v3-flatcontainer/python/$Version/$nupkgName"
        $tempPython = Join-Path $mainTempDir $nupkgName
        
        Invoke-FallbackDownload -DownloadUrl $dlUrl -OutFilePath $tempPython
        
        Write-SetupStatus -Message "Unpacking Python Payload using 7-Zip..." -Type INFO
        $tempExtractDir = Join-Path $mainTempDir "temp_py_extract"
        if (Test-Path $tempExtractDir) { Remove-Item -Path $tempExtractDir -Recurse -Force }
        New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null
        
        Invoke-SetupCommand -CommandPath $7zExe -ArgumentList @("x", $tempPython, "-y", "-o$tempExtractDir", "-bsp1", "-bso0") -Parse7ZipProgress -ProgressLabel "Unpacking Python"
        
        $sourceTools = Join-Path $tempExtractDir "tools"
        if (-not (Test-Path (Join-Path $sourceTools "python.exe"))) { $sourceTools = $tempExtractDir }
        if (Test-Path $pythonDir) { Remove-Item -Path "$pythonDir\*" -Recurse -Force -ErrorAction SilentlyContinue }
        
        Get-ChildItem -Path $sourceTools -Force | ForEach-Object {
            $destPath = Join-Path $pythonDir $_.Name
            if ($_.PSIsContainer) { 
                Copy-Item -Path $_.FullName -Destination $destPath -Recurse -Force 
            } else { 
                Copy-Item -Path $_.FullName -Destination $pythonDir -Force 
            }
        }
        
        Get-ChildItem -Path $pythonDir -Filter "*._pth" | ForEach-Object {
            $content = Get-Content -Path $_.FullName
            $content = $content -replace '#\s*import site', 'import site'
            Set-Content -Path $_.FullName -Value $content
        }
        
        Write-SetupStatus -Message "Initializing Pip Component..." -Type INFO
        $pyExe = Join-Path $pythonDir "python.exe"
        Invoke-SetupCommand -CommandPath $pyExe -ArgumentList @("-m", "ensurepip", "--upgrade") -NoOutput
        
        if (-not (Test-Path (Join-Path $pipDir "pip.exe"))) {
            Write-SetupStatus -Message "Fallback to get-pip.py bootstrap..." -Type INFO
            $getPipScript = Join-Path $mainTempDir "get-pip.py"
            Invoke-FallbackDownload -DownloadUrl "https://bootstrap.pypa.io/get-pip.py" -OutFilePath $getPipScript
            Invoke-SetupCommand -CommandPath $pyExe -ArgumentList @($getPipScript, "--no-warn-script-location")
        }
        else {
            Invoke-SetupCommand -CommandPath $pyExe -ArgumentList @("-m", "pip", "install", "--upgrade", "pip") -NoOutput
        }
        
        Remove-Item -Path $tempPython, $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Green
        Write-SetupStatus -Message "Python v$Version & PIP Deployed Successfully!" -Type RAW -Color Green
        Write-SetupStatus -Message "Target: $pythonDir" -Type RAW -Color Yellow
        Write-SetupStatus -Message "======================================================================" -Type RAW -Color Green
    }
    catch { 
        Write-SetupStatus -Message "Failed to deploy Python: $_" -Type ERROR
        exit 1 
    }
}

# --------------------------------------------------------
# 4. State Management
# --------------------------------------------------------
function Get-CurrentCudaMajorState {
    [CmdletBinding(PositionalBinding=$false)]
    param ()
    
    if (Test-Path $cudaStateFile) {
        $savedVer = Get-Content $cudaStateFile -Raw
        if ($savedVer -match "^\d+") { return $Matches[0] }
    }
    return $null
}

function Set-CurrentCudaMajorState {
    [CmdletBinding(PositionalBinding=$false)]
    param ([string]$VerString)
    
    if ($VerString -match "^\d+") {
        $major = $Matches[0]
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($cudaStateFile, $major, $utf8NoBom)
        Write-SetupStatus -Message "Saved Active CUDA Major State: v$major.x -> $cudaStateFile" -Type INFO
    }
}

# --------------------------------------------------------
# 5. Diagnostics
# --------------------------------------------------------
function Get-NvidiaInfo {
    [CmdletBinding(PositionalBinding=$false)]
    param ()
    
    $info = [PSCustomObject]@{ 
        OS64Bit = [Environment]::Is64BitOperatingSystem; 
        GPUName = "Unknown GPU"; 
        Driver = "Unknown"; 
        MaxCuda = "Unknown" 
    }
    
    $smiPath = "C:\WINDOWS\system32\nvidia-smi.exe"
    if (-not (Test-Path $smiPath)) { 
        $smiCmd = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue
        if ($smiCmd) { $smiPath = $smiCmd.Source } else { return $info } 
    }
    
    try {
        $csvOutput = Invoke-SetupCommand -CommandPath $smiPath -ArgumentList @("--query-gpu=driver_version,name", "--format=csv,noheader") -AsString 2>$null
        if ($csvOutput) { 
            $parts = $csvOutput -split ","
            if ($parts.Count -ge 2) { 
                $info.Driver = $parts[0].Trim()
                $info.GPUName = $parts[1].Trim() 
            } 
        }
        $rawOutput = Invoke-SetupCommand -CommandPath $smiPath -RedirectError -AsString
        if ($rawOutput -match "CUDA(?:\s+UMD)?\s+Version\s*:\s*([0-9\.]+)") { 
            $info.MaxCuda = $Matches[1] 
        }
    }
    catch {}
    return $info
}

function Get-RemoteVersions {
    [CmdletBinding(PositionalBinding=$false)]
    param ([string]$Tool)
    
    $rawBaseUrl = "https://developer.download.nvidia.com/compute/$Tool/redist/"
    $baseUrl = Get-ProxifiedUrl -OriginalUrl $rawBaseUrl
    
    try {
        $indexRes = Invoke-SetupWebRequest -Uri $baseUrl
        $regex = "redistrib_([0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)\.json"
        $matches = [regex]::Matches($indexRes.Content, $regex)
        
        $versions = foreach ($m in $matches) { $m.Groups[1].Value }
        return ($versions | Select-Object -Unique | Sort-Object { try { [version]$_ } catch { [version]"0.0.0" } } -Descending)
    }
    catch { return $null }
}

function Show-GroupedVersions {
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [string]$Tool, 
        [array]$Versions
    )
    
    Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Cyan
    Write-SetupStatus -Message "   AVAILABLE $($Tool.ToUpper()) VERSIONS (ONLINE)" -Type RAW -Color Green
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan
    
    $parsedList = New-Object System.Collections.Generic.List[object]
    foreach ($ver in $Versions) {
        try { 
            $parsedList.Add([PSCustomObject]@{ Version = $ver; MajorMinor = "$(([version]$ver).Major).$(([version]$ver).Minor)" }) 
        }
        catch { 
            $parsedList.Add([PSCustomObject]@{ Version = $ver; MajorMinor = $ver }) 
        }
    }
    
    $groups = $parsedList | Group-Object -Property MajorMinor
    $tableData = New-Object System.Collections.Generic.List[object]
    
    foreach ($g in $groups) {
        $sortedPatches = $g.Group | Sort-Object { [version]$_.Version } -Descending
        $tableData.Add([PSCustomObject]@{ 
            "Branch" = $g.Name; 
            "Latest Patch" = $sortedPatches[0].Version; 
            "Available Patches" = (($g.Group | Sort-Object { [version]$_.Version }).Version) -join ", " 
        })
    }
    $tableData | Format-Table -AutoSize
}

function Show-SmartCudnnVersions {
    [CmdletBinding(PositionalBinding=$false)]
    param ([array]$Versions)
    
    $activeCudaMajor = Get-CurrentCudaMajorState
    if ([string]::IsNullOrEmpty($activeCudaMajor)) {
        Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Red
        Write-SetupStatus -Message "Active CUDA State is NOT set!" -Type RAW -Color Red
        Write-SetupStatus -Message " Please install CUDA first to allow cuDNN to filter packages." -Type RAW -Color Yellow
        Write-SetupStatus -Message "======================================================================`n" -Type RAW -Color Red
        return
    }

    Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Cyan
    Write-SetupStatus -Message "   AVAILABLE CUDNN VERSIONS (FILTERED FOR CUDA ${activeCudaMajor}.x)" -Type RAW -Color Green
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan
    Write-SetupStatus -Message " Active CUDA Target : CUDA ${activeCudaMajor}.x" -Type RAW -Color Yellow
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan

    $tableData = New-Object System.Collections.Generic.List[object]
    
    foreach ($ver in $Versions) {
        $manifestUrl = Get-ProxifiedUrl -OriginalUrl "https://developer.download.nvidia.com/compute/cudnn/redist/redistrib_${ver}.json"
        try {
            $manifestData = Invoke-SetupRestMethod -Uri $manifestUrl
            $matchedCudaVariants = @()
            
            foreach ($rp in $manifestData.psobject.Properties) {
                $winNode = $rp.Value.'windows-x86_64'
                if ($winNode) {
                    foreach ($sub in $winNode.psobject.Properties) {
                        if ($sub.Name -match "cuda(\d+)" -and $sub.Value.relative_path) {
                            $varTag = "cuda" + $Matches[1]
                            if ($matchedCudaVariants -notcontains $varTag) { $matchedCudaVariants += $varTag }
                        }
                    }
                    if ($winNode.relative_path) {
                        if ($winNode.relative_path -match "cuda(\d+)") {
                            $varTag = "cuda" + $Matches[1]
                            if ($matchedCudaVariants -notcontains $varTag) { $matchedCudaVariants += $varTag }
                        }
                        else {
                            if ($matchedCudaVariants -notcontains "cuda$activeCudaMajor") { $matchedCudaVariants += "cuda$activeCudaMajor" }
                        }
                    }
                }
            }
            if ($matchedCudaVariants -contains "cuda$activeCudaMajor") {
                $tableData.Add([PSCustomObject]@{ 
                    "cuDNN Version" = $ver; 
                    "Windows CUDA Variant" = ($matchedCudaVariants | Select-Object -Unique) -join ", "; 
                    "Target Match State" = "MATCHED (cuda$activeCudaMajor)" 
                })
            }
        }
        catch {}
    }
    if ($tableData.Count -gt 0) { $tableData | Format-Table -AutoSize }
}

# --------------------------------------------------------
# 6. Installation Engine (CUDA, cuDNN & ALL Suite)
# --------------------------------------------------------
function Invoke-SetupDownloadAndExtract {
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [Parameter(Mandatory=$true)][string]$ModuleName,
        [Parameter(Mandatory=$true)][array]$DownloadTasks,
        [Parameter(Mandatory=$true)][string]$DestinationDir,
        [Parameter(Mandatory=$true)][array]$ExtractFilters
    )
    
    $aria2Queue = @()
    foreach ($task in $DownloadTasks) {
        if (-not (Test-Path $task.TargetPath) -or ((Get-Item $task.TargetPath).Length -ne $task.ExpectedSize)) {
            $aria2Queue += $task.Url
            $aria2Queue += "  dir=$mainTempDir"
            $aria2Queue += "  out=$($task.FileName)"
        }
    }
    
    Start-Aria2BatchDownload -QueueLines $aria2Queue
    
    Write-SetupStatus -Message "`n[VERIFY] Testing $ModuleName archives integrity..." -Type INFO
    foreach ($task in $DownloadTasks) {
        $isCorrupted = $false
        if (Test-Path $task.TargetPath) {
            if (Test-Path $7zExe) {
                Invoke-SetupCommand -CommandPath $7zExe -ArgumentList @("t", $task.TargetPath, "-bsp1", "-bso0") -Parse7ZipProgress -ProgressLabel "Verifying [$($task.FileName)]"
                if ($LASTEXITCODE -ne 0) { $isCorrupted = $true }
            }
            if ((Get-Item $task.TargetPath).Length -ne $task.ExpectedSize) { $isCorrupted = $true }
        }
        else {
            $isCorrupted = $true
        }
        
        if ($isCorrupted) {
            Write-SetupStatus -Message "Archive '$($task.FileName)' corrupted! Re-downloading via Fallback..." -Type RAW -Color Red
            if (Test-Path $task.TargetPath) { Remove-Item $task.TargetPath -Force -ErrorAction SilentlyContinue }
            Invoke-FallbackDownload -DownloadUrl $task.Url -OutFilePath $task.TargetPath
        }
    }
    
    Write-SetupStatus -Message "`n[EXTRACT] Unpacking $ModuleName DLLs to $DestinationDir..." -Type INFO
    foreach ($task in $DownloadTasks) {
        if (Test-Path $task.TargetPath) {
            # Build 7z extract arguments
            $args = @("e", $task.TargetPath, "-o$DestinationDir")
            $args += $ExtractFilters
            $args += @("-r", "-y", "-bsp1", "-bso0")
            
            Invoke-SetupCommand -CommandPath $7zExe -ArgumentList $args -Parse7ZipProgress -ProgressLabel "Extracting [$($task.FileName)]"
            Remove-Item $task.TargetPath -Force -ErrorAction SilentlyContinue
        }
    }
}
function Install-Cuda {
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [string]$RequestedVer,
        [switch]$ForceInstall
    )

    $sysInfo = Get-NvidiaInfo
    $autoCudnn = $false

    if (-not $ForceInstall) {
        if ($sysInfo.MaxCuda -ne "Unknown") {
            try {
                $maxVer = [version]($sysInfo.MaxCuda)
                $reqVer = [version]($RequestedVer.Split('.')[0..1] -join '.')
                if ($reqVer -gt $maxVer) {
                    Write-SetupStatus -Message "`n[WARNING] Requested Version (v$RequestedVer) > Driver Supported (Max v$($sysInfo.MaxCuda))!" -Type RAW -Color Red
                    $prompt = Read-Host "Proceed anyway? (y/N)"
                    if ($prompt -notmatch "^[Yy]$") { return }
                }
            }
            catch {}
        }

        Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Cyan
        Write-SetupStatus -Message "   CUDA INSTALLATION MENU" -Type RAW -Color Green
        Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan
        Write-SetupStatus -Message " Target CUDA Version     : v$RequestedVer" -Type RAW -Color Yellow
        Write-SetupStatus -Message " Max Supported by Driver : v$($sysInfo.MaxCuda)" -Type RAW -Color DarkGray
        Write-SetupStatus -Message "--------------------------------------------------------" -Type RAW -Color Cyan
        Write-SetupStatus -Message " [A] Auto : Install CUDA + Auto-match & Install latest cuDNN" -Type RAW -Color White
        Write-SetupStatus -Message " [Y] Yes  : Install CUDA only (Manual cuDNN later)" -Type RAW -Color White
        Write-SetupStatus -Message " [N] No   : Cancel installation" -Type RAW -Color White
        Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan
        
        $choice = Read-Host " Select an option (A/Y/N)"
        if ($choice -match "^[Nn]$") { Write-SetupStatus -Message "Installation aborted." -Type INFO; return }
        $autoCudnn = ($choice -match "^[Aa]$")
    }

    Write-SetupStatus -Message "`n[PROCESS] Fetching CUDA Index..." -Type INFO
    $availableVersions = Get-RemoteVersions -Tool "cuda"
    $matched = $availableVersions | Where-Object { $_ -like "$RequestedVer*" } | Select-Object -First 1
    
    if (-not $matched) { 
        Write-SetupStatus -Message "Version '$RequestedVer' not found." -Type ERROR
        return 
    }

    Write-SetupStatus -Message "Reading Manifest for CUDA v$matched..." -Type INFO
    $realBaseUrl = "https://developer.download.nvidia.com/compute/cuda/redist/"
    $manifestData = Invoke-SetupRestMethod -Uri (Get-ProxifiedUrl -OriginalUrl "${realBaseUrl}redistrib_${matched}.json")

    $downloadTasks = @()
    
    foreach ($compKey in $eliteCudaComponents) {
        $winPkg = $manifestData.$compKey.'windows-x86_64'
        if ($winPkg -and $winPkg.relative_path) {
            $dlUrl = Get-ProxifiedUrl -OriginalUrl "${realBaseUrl}$($winPkg.relative_path)"
            $fName = Split-Path $winPkg.relative_path -Leaf
            $tPath = Join-Path $mainTempDir $fName
            
            $taskObj = [PSCustomObject]@{ 
                Url = $dlUrl; 
                TargetPath = $tPath; 
                FileName = $fName; 
                ExpectedSize = [long]$winPkg.size 
            }
            $downloadTasks += $taskObj
        }
    }

    Invoke-SetupDownloadAndExtract -ModuleName "CUDA" -DownloadTasks $downloadTasks -DestinationDir $cudaBinDir -ExtractFilters @("*.dll")

    Set-CurrentCudaMajorState -VerString $matched
    Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Green
    Write-SetupStatus -Message "CUDA v$matched Deployed Successfully!" -Type RAW -Color Green
    Write-SetupStatus -Message "DLL Target: $cudaBinDir" -Type RAW -Color Yellow
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Green

    if ($autoCudnn) {
        Write-SetupStatus -Message "`n[AUTO TRIGGER] Handing over to cuDNN Auto-Installer..." -Type RAW -Color Magenta
        Install-Cudnn -RequestedVer "" -ForceInstall:$ForceInstall
    }
}

function Install-Cudnn {
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [string]$RequestedVer,
        [switch]$ForceInstall
    )

    $activeMajor = Get-CurrentCudaMajorState
    if ([string]::IsNullOrEmpty($activeMajor)) {
        Write-SetupStatus -Message "`n[ERROR] Cannot install cuDNN! No CUDA State found. Install CUDA first." -Type ERROR
        return
    }

    Write-SetupStatus -Message "`n[PROCESS] Fetching cuDNN Index..." -Type INFO
    $availableVersions = Get-RemoteVersions -Tool "cudnn"
    $targetVer = ""
    $realBaseUrl = "https://developer.download.nvidia.com/compute/cudnn/redist/"

    if ([string]::IsNullOrEmpty($RequestedVer)) {
        Write-SetupStatus -Message "Finding highest cuDNN compatible with CUDA ${activeMajor}.x..." -Type INFO
        foreach ($ver in $availableVersions) {
            try {
                $manifestData = Invoke-SetupRestMethod -Uri (Get-ProxifiedUrl -OriginalUrl "${realBaseUrl}redistrib_${ver}.json")
                $isMatch = $false
                
                foreach ($rp in $manifestData.psobject.Properties) {
                    $winNode = $rp.Value.'windows-x86_64'
                    if ($winNode) {
                        foreach ($sub in $winNode.psobject.Properties) { 
                            if ($sub.Name -eq "cuda$activeMajor" -and $sub.Value.relative_path) { 
                                $isMatch = $true; break 
                            } 
                        }
                        if ($winNode.relative_path -and ($winNode.relative_path -match "cuda$activeMajor" -or $winNode.relative_path -notmatch "cuda\d+")) { 
                            $isMatch = $true 
                        }
                    }
                }
                if ($isMatch) { $targetVer = $ver; break }
            }
            catch {}
        }
        if (-not $targetVer) { 
            Write-SetupStatus -Message "No matched cuDNN found." -Type ERROR
            return 
        }
        Write-SetupStatus -Message "Selected cuDNN v$targetVer" -Type OK
    }
    else {
        $matched = $availableVersions | Where-Object { $_ -like "$RequestedVer*" } | Select-Object -First 1
        if ($matched) { $targetVer = $matched } 
        else { Write-SetupStatus -Message "cuDNN '$RequestedVer' not found." -Type ERROR; return }
    }

    Write-SetupStatus -Message "Reading Manifest for cuDNN v$targetVer..." -Type INFO
    $manifestData = Invoke-SetupRestMethod -Uri (Get-ProxifiedUrl -OriginalUrl "${realBaseUrl}redistrib_${targetVer}.json")

    $downloadTasks = @()
    
    foreach ($rp in $manifestData.psobject.Properties) {
        $winNode = $rp.Value.'windows-x86_64'
        if ($winNode) {
            $relPath = $null
            foreach ($sub in $winNode.psobject.Properties) { 
                if ($sub.Name -eq "cuda$activeMajor" -and $sub.Value.relative_path) { 
                    $relPath = $sub.Value.relative_path; break 
                } 
            }
            if (-not $relPath -and $winNode.relative_path) {
                if ($winNode.relative_path -match "cuda$activeMajor" -or $winNode.relative_path -notmatch "cuda\d+") { 
                    $relPath = $winNode.relative_path 
                }
            }
            if ($relPath) {
                $dlUrl = Get-ProxifiedUrl -OriginalUrl "${realBaseUrl}$relPath"
                $fName = Split-Path $relPath -Leaf
                $tPath = Join-Path $mainTempDir $fName
                
                $taskObj = [PSCustomObject]@{ 
                    Url = $dlUrl; 
                    TargetPath = $tPath; 
                    FileName = $fName; 
                    ExpectedSize = [long]$winNode.size 
                }
                $downloadTasks += $taskObj
            }
        }
    }

    Invoke-SetupDownloadAndExtract -ModuleName "cuDNN" -DownloadTasks $downloadTasks -DestinationDir $cudnnBinDir -ExtractFilters $cudnnTargets

    Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Green
    Write-SetupStatus -Message "cuDNN v$targetVer Deployed Successfully!" -Type RAW -Color Green
    Write-SetupStatus -Message "DLL Target: $cudnnBinDir" -Type RAW -Color Yellow
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Green
}

function Install-AllSuite {
    [CmdletBinding(PositionalBinding=$false)]
    param ([bool]$IsAutoMode = $false)

    Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Cyan
    Write-SetupStatus -Message "   STARTING AUTOMATED FULL SUITE DEPLOYMENT (-i all)" -Type RAW -Color Green
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan

    Write-SetupStatus -Message "`n [ALL 1/3] Resolving Python Target (Default: v$DefaultPython)..." -Type INFO
    $targetPyVersion = ""
    $pyVers = Get-PythonVersions
    if ($null -ne $pyVers) {
        $escapedV = [regex]::Escape($DefaultPython)
        $matched = $pyVers | Where-Object { $_ -match "^$escapedV\." }
        if ($matched) {
            $sorted = $matched | ForEach-Object { [version]$_ } | Sort-Object
            $targetPyVersion = ($sorted[-1]).ToString()
        }
        elseif ($DefaultPython -match '^\d+\.\d+\.\d+$') {
            $targetPyVersion = $DefaultPython
        }
    }
    if ([string]::IsNullOrEmpty($targetPyVersion)) { $targetPyVersion = $DefaultPython }

    Install-Python -Version $targetPyVersion

    Write-Host "`n [ALL 2/3] Resolving CUDA Target (Default: $DefaultCuda)..." -ForegroundColor Yellow
    Install-Cuda -RequestedVer $DefaultCuda -ForceInstall:$Force

    Write-Host "`n [ALL 3/3] Resolving cuDNN Target (Auto-matching CUDA State)..." -ForegroundColor Yellow
    Install-Cudnn -RequestedVer "" -ForceInstall:$Force

    Write-Host "`n======================================================================" -ForegroundColor Green
    Write-Host " [SUCCESS] FULL SUITE DEPLOYMENT COMPLETE!" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
}

# --------------------------------------------------------
# 7. Environment & Shell Loader
# --------------------------------------------------------
function Update-SessionPath {
    [CmdletBinding(PositionalBinding=$false)]
    param ()
    
    $resolvedGitBin = Join-Path $gitDir "cmd"
    if (-not (Test-Path (Join-Path $resolvedGitBin "git.exe"))) { $resolvedGitBin = Join-Path $gitDir "bin" }
    $env:PATH = "$cudaBinDir;$cudnnBinDir;$pythonDir;$pipDir;$resolvedGitBin;$7zDir;$env:PATH"
}

function Enter-LiveDevShell {
    [CmdletBinding(PositionalBinding=$false)]
    param ()
    
    # 1. Ensure core bootstrapping tools (7-Zip, Aria2, Git) are ready
    Ensure-DefaultTools -ForceInstall:$Force

    # 2. Check Portable Python in tools/python
    $pyExe = Join-Path $pythonDir "python.exe"
    if (-not (Test-Path $pyExe)) {
        Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Yellow
        Write-SetupStatus -Message "Portable Python not found in tools/python" -Type RAW -Color Yellow
        Write-SetupStatus -Message "Installing default Base Python v$DefaultPython..." -Type RAW -Color Yellow
        Write-SetupStatus -Message "======================================================================`n" -Type RAW -Color Yellow
        
        $targetPyVersion = ""
        $pyVers = Get-PythonVersions
        if ($null -ne $pyVers) {
            $escapedV = [regex]::Escape($DefaultPython)
            $matched = $pyVers | Where-Object { $_ -match "^$escapedV\." }
            if ($matched) {
                $sorted = $matched | ForEach-Object { [version]$_ } | Sort-Object
                $targetPyVersion = ($sorted[-1]).ToString()
            }
        }
        if ([string]::IsNullOrEmpty($targetPyVersion)) { $targetPyVersion = "3.12.8" }
        
        # Install ONLY Python Base Stack (No CUDA / cuDNN)
        Install-Python -Version $targetPyVersion
    }

    Clear-TempDirectory
    Update-SessionPath
    
    Write-SetupStatus -Message "`n======================================================================" -Type RAW -Color Cyan
    Write-SetupStatus -Message " [ON] Dev Suite Beta Live Shell Environment" -Type RAW -Color Green
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan
    
    # Verify Python via Direct EXE
    if (Test-Path $pyExe) {
        $pyVerStr = Invoke-SetupCommand -CommandPath $pyExe -ArgumentList @("-V") -RedirectError -AsString
        Write-SetupStatus -Message "python -V : $pyVerStr" -Type RAW -Color DarkGray
    }
    else { 
        Write-SetupStatus -Message "python  : NOT INSTALLED" -Type RAW -Color Yellow 
    }

    # Verify Git
    $gitExe = Join-Path $gitDir "cmd\git.exe"
    if (-not (Test-Path $gitExe)) { $gitExe = Join-Path $gitDir "bin\git.exe" }
    if (Test-Path $gitExe) {
        $gitVerStr = Invoke-SetupCommand -CommandPath $gitExe -ArgumentList @("--version") -RedirectError -AsString
        Write-SetupStatus -Message "git -v    : $gitVerStr" -Type RAW -Color DarkGray
    }
    else { 
        Write-SetupStatus -Message "git     : NOT INSTALLED" -Type RAW -Color Yellow 
    }

    # Verify CUDA Status
    $hasCuda = $false
    if (Test-Path $cudaBinDir) {
        $cudaDlls = Get-ChildItem -Path $cudaBinDir -Filter "*.dll" -ErrorAction SilentlyContinue
        if ($cudaDlls.Count -gt 0) {
            $hasCuda = $true
            $cudaState = Get-CurrentCudaMajorState
            $cudaVerTag = if ($cudaState) { " (v$cudaState.x)" } else { "" }
            Write-SetupStatus -Message "CUDA      : Active${cudaVerTag} -> $cudaBinDir ($($cudaDlls.Count) DLLs)" -Type RAW -Color Green
        }
    }
    if (-not $hasCuda) {
        Write-SetupStatus -Message "CUDA    : NOT INSTALLED" -Type RAW -Color Yellow
    }

    # Verify cuDNN Status
    $hasCudnn = $false
    if (Test-Path $cudnnBinDir) {
        $cudnnDlls = Get-ChildItem -Path $cudnnBinDir -Filter "*.dll" -ErrorAction SilentlyContinue
        if ($cudnnDlls.Count -gt 0) {
            $hasCudnn = $true
            Write-SetupStatus -Message "cuDNN     : Active -> $cudnnBinDir ($($cudnnDlls.Count) DLLs)" -Type RAW -Color Green
        }
    }
    if (-not $hasCudnn) {
        Write-SetupStatus -Message "cuDNN   : NOT INSTALLED" -Type RAW -Color Yellow
    }
    
    Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan
    
    # Detailed Guidance Notice Box for Missing Components
    if (-not $hasCuda -or -not $hasCudnn) {
        Write-SetupStatus -Message "Running in CPU / Base Runtime Mode (No GPU Acceleration)." -Type RAW -Color Yellow
        Write-SetupStatus -Message "--------------------------------------------------------" -Type RAW -Color Cyan
        Write-SetupStatus -Message "" -Type RAW -Color Yellow
        Write-SetupStatus -Message "  * List Online Versions : .\setup.ps1 -l <python|cuda|cudnn>" -Type RAW -Color DarkGray
        Write-SetupStatus -Message "  * Install CUDA DLLs    : .\setup.ps1 -i cuda -v 12.8" -Type RAW -Color DarkGray
        Write-SetupStatus -Message "  * Install cuDNN DLLs   : .\setup.ps1 -i cudnn" -Type RAW -Color DarkGray
        Write-SetupStatus -Message "  * Deploy Full Heavy AI : .\setup.ps1 -i all -y" -Type RAW -Color Cyan
        Write-SetupStatus -Message "  * Show Complete Manual : .\setup.ps1 -h" -Type RAW -Color DarkGray
        Write-SetupStatus -Message "======================================================================" -Type RAW -Color Cyan
    }

    Write-SetupStatus -Message " Type 'exit' to quit live environment context." -Type RAW -Color Yellow
}

function Show-HelpMenu {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host " :: PORTABLE DEV SUITE :: COMMAND REFERENCE" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host " [USAGE] " -ForegroundColor Yellow
    Write-Host "   .\setup.ps1 [OPTIONS]"
    Write-Host " [OPTIONS]" -ForegroundColor Yellow
    Write-Host "   -h, --help       Show this help manual"
    Write-Host "   -c, --check      Run hardware & driver diagnostics"
    Write-Host "   -l, --list       List online versions (python | cuda | cudnn)"
    Write-Host "   -i, --install    Install specific module (python | git | cuda | cudnn | all)"
    Write-Host "   -v, --version    Specify target version (e.g., -v 3.12, -v 12.8)"
    Write-Host "   -f, --force      Force re-download and overwrite existing files"
    Write-Host "   -y, --yes        Auto-confirm all prompts (Silent Mode)"
    Write-Host "   -e, --env        Enter Live Shell environment directly"
    Write-Host " [EXAMPLES]" -ForegroundColor Yellow
    Write-Host "   .\setup.ps1 -i all -f -y"
    Write-Host "   .\setup.ps1 -i cuda -v 13.3"
    Write-Host "======================================================================" -ForegroundColor Cyan
}

# --------------------------------------------------------
# 8. Router

# --------------------------------------------------------

if ($EnvMode) { Enter-LiveDevShell; exit }

if ($Help -or $PSBoundParameters.Count -eq 0) {
    Show-HelpMenu
    exit
}

if ($Check) {
    $sysInfo = Get-NvidiaInfo
    Write-Host "`n======================================================================" -ForegroundColor Cyan
    Write-Host "   SYSTEM HARDWARE & DRIVER DIAGNOSTICS" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Cyan
    
    $osColor = if ($sysInfo.OS64Bit) { "Green" } else { "Red" }
    Write-Host ("  [OK] OS System          : " + $(if ($sysInfo.OS64Bit) { "Windows 64-bit" } else { "Unsupported (32-bit/ARM)" })) -ForegroundColor $osColor
    Write-Host "  [OK] GPU Detected       : $($sysInfo.GPUName)" -ForegroundColor Green
    Write-Host "  [OK] NVIDIA Driver      : v$($sysInfo.Driver)" -ForegroundColor Green
    Write-Host "  [OK] Max CUDA Supported : v$($sysInfo.MaxCuda)" -ForegroundColor Cyan
    Write-Host "======================================================================`n" -ForegroundColor Cyan
    exit
}

if ($List) {
    if (-not $RemainingArgs -or $RemainingArgs.Count -eq 0) {
        Write-SetupStatus -Message "Missing module for -l (List). Please specify 'python', 'cuda', or 'cudnn'." -Type ERROR
        Show-HelpMenu
        exit
    }
    $ToolToList = $RemainingArgs[0]
    Ensure-DefaultTools -ForceInstall:$Force

    $tList = $ToolToList.ToLower()
    $validListTools = @('python', 'cuda', 'cudnn')
    if ($tList -notin $validListTools) {
        Write-SetupStatus -Message "Invalid module '$ToolToList' for -l (List)." -Type ERROR
        Show-HelpMenu
        exit
    }
    if ($tList -eq 'python') {
        Write-Host "`n[PROCESS] Fetching Python versions from NuGet..." -ForegroundColor Yellow
        $pyVers = Get-PythonVersions
        if ($null -ne $pyVers) {
            $parsedList = New-Object System.Collections.Generic.List[object]
            foreach ($ver in $pyVers) {
                try { 
                    $parsedList.Add([PSCustomObject]@{ Version = $ver; MajorMinor = "$(([version]$ver).Major).$(([version]$ver).Minor)" }) 
                } catch {}
            }
            $groups = $parsedList | Group-Object -Property MajorMinor
            $tableData = New-Object System.Collections.Generic.List[object]
            foreach ($g in $groups) {
                $sortedPatches = $g.Group | Sort-Object { [version]$_.Version } -Descending
                $tableData.Add([PSCustomObject]@{ 
                    "Branch" = $g.Name; 
                    "Latest Patch" = $sortedPatches[0].Version; 
                    "Available Patches" = (($g.Group | Sort-Object { [version]$_.Version }).Version) -join ", " 
                })
            }
            $tableData | Format-Table -AutoSize
        }
        else { Write-Error "[ERROR] Could not fetch Python versions." }
    }
    elseif ($tList -in @("cuda", "cudnn")) {
        Write-Host "`n[PROCESS] Fetching $tList index..." -ForegroundColor Yellow
        $vers = Get-RemoteVersions -Tool $tList
        if ($null -ne $vers) {
            if ($tList -eq "cuda") { Show-GroupedVersions -Tool "cuda" -Versions $vers }
            elseif ($tList -eq "cudnn") { Show-SmartCudnnVersions -Versions $vers }
        }
        else { Write-Error "[ERROR] Failed to fetch data." }
    }
    Clear-TempDirectory
    exit
}

if ($Install) {
    if (-not $RemainingArgs -or $RemainingArgs.Count -eq 0) {
        Write-SetupStatus -Message "Missing module for -i (Install). Please specify 'python', 'cuda', 'cudnn', 'git', '7zip', or 'all'." -Type ERROR
        Show-HelpMenu
        exit
    }
    $ToolToInstall = $RemainingArgs[0]
    $tool = $ToolToInstall.ToLower()
    $validTools = @('git', 'python', 'cuda', 'cudnn', 'all', '7zip')
    if ($tool -notin $validTools) {
        Write-SetupStatus -Message "Invalid module '$ToolToInstall' for -i (Install)." -Type ERROR
        Show-HelpMenu
        exit
    }

    Ensure-DefaultTools -ForceInstall:$Force

    # --------------------------------------------------------
    # [ROUTER BRANCH 1] FULL SUITE INSTALLATION (-i all)
    # --------------------------------------------------------
    if ($tool -eq 'all') {
        if (-not $AutoYes) {
            Write-Host "`n======================================================================" -ForegroundColor Cyan
            Write-Host "        PORTABLE RUNTIME INJECTOR" -ForegroundColor Green
            Write-Host "======================================================================" -ForegroundColor Cyan
            Write-Host " Selected Target : FULL SUITE (ALL)" -ForegroundColor Yellow
            Write-Host " Python Target   : v$DefaultPython (Default)" -ForegroundColor Yellow
            Write-Host " CUDA Target     : v$DefaultCuda (Default)" -ForegroundColor Yellow
            Write-Host " cuDNN Target    : Auto-match CUDA State" -ForegroundColor Yellow
            Write-Host "======================================================================" -ForegroundColor Cyan
            $confirm = Read-Host "Proceed with deployment? (y/N)"
            if ($confirm -notmatch "^[Yy]$") { Write-Host "Installation cancelled."; exit }
        }

        Install-AllSuite -IsAutoMode $AutoYes
        Clear-TempDirectory
        Enter-LiveDevShell
        exit
    }

    # --------------------------------------------------------
    # [ROUTER BRANCH 2] INDIVIDUAL TOOL INSTALLATION
    # --------------------------------------------------------
    $targetPyVersion = ""
    if ($tool -eq 'python') {
        $pyVers = Get-PythonVersions
        if ($null -ne $pyVers) {
            if ([string]::IsNullOrEmpty($TargetVersion)) {
                $sorted = $pyVers | ForEach-Object { [version]$_ } | Sort-Object
                $targetPyVersion = ($sorted[-1]).ToString()
            }
            else {
                if ($TargetVersion -match '^\d+\.\d+$') {
                    $escapedV = [regex]::Escape($TargetVersion)
                    $matched = $pyVers | Where-Object { $_ -match "^$escapedV\." }
                    $sorted = $matched | ForEach-Object { [version]$_ } | Sort-Object
                    $targetPyVersion = ($sorted[-1]).ToString()
                }
                elseif ($TargetVersion -match '^\d+\.\d+\.\d+$') {
                    $targetPyVersion = $TargetVersion
                }
            }
        }
    }

    if (-not $AutoYes -and $tool -notin @('cuda', 'cudnn')) {
        Write-Host "`n======================================================================" -ForegroundColor Cyan
        Write-Host "        PORTABLE RUNTIME INJECTOR" -ForegroundColor Green
        Write-Host "======================================================================" -ForegroundColor Cyan
        Write-Host " Selected Target : $ToolToInstall" -ForegroundColor Yellow
        if ($targetPyVersion) { Write-Host " Python Version  : v$targetPyVersion" -ForegroundColor Yellow }
        Write-Host "======================================================================" -ForegroundColor Cyan
        $confirm = Read-Host "Proceed with deployment? (y/N)"
        if ($confirm -notmatch "^[Yy]$") { Write-Host "Installation cancelled."; exit }
    }

    if ($tool -eq 'python') { Install-Python -Version $targetPyVersion }
    if ($tool -eq 'cuda')   { Install-Cuda -RequestedVer $TargetVersion -ForceInstall:$Force }
    if ($tool -eq 'cudnn')  { Install-Cudnn -RequestedVer $TargetVersion -ForceInstall:$Force }

    Clear-TempDirectory
    Enter-LiveDevShell
    exit
}
