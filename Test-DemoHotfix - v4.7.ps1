<#
.SYNOPSIS
    ProPhoenix Test / Demo Hotfix .
    1. Generates standard full Hotfix batch file.
    2. ADDED: Generates "Instance Update(BS).bat" in specific Phoenix Installation Master path.
    3. Secondary bat ONLY stops Phoenix services (leaves IIS alone), updates instances, and verifies.
    4. AUTOMATED: No prompts, captures screenshots of PS fetch and Bat verifications to PrintLog.
    5. RECORDING REMOVED: Uses single-frame screenshots instead of continuous session recording.
#>

$ErrorActionPreference = "Continue"

# --- 1. DEFINITIONS: HELPER SCRIPTS ---

# (A) Session Data Cleaner
$LogClearScriptContent = @"
Write-Host "========================================="
Write-Host "            SCRIPT STARTED               "
Write-Host "========================================="
`$proPhoenixBasePaths = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    "`$(`$_.Root)\Program Files\ProPhoenix"
} | Where-Object { Test-Path -Path `$_ }

Write-Host "`n[INFO] Searching for '_Instances' folders..."

# CLEAR SVR SESSION DATA
Write-Host "`n========================================="
Write-Host "      CLEARING SERVER SESSION DATA       "
Write-Host "========================================="
foreach (`$basePath in `$proPhoenixBasePaths) {
    `$cadServerPath = Join-Path -Path `$basePath -ChildPath "CAD Server\_Instances"
    if (Test-Path `$cadServerPath) {
        `$cadInstances = Get-ChildItem -Path `$cadServerPath -Directory
        foreach (`$inst in `$cadInstances) {
            `$sessionDataPath = Join-Path -Path `$inst.FullName -ChildPath "SvrSessionData"
            if (Test-Path `$sessionDataPath) {
                Write-Host "[INFO] Cleaning Session Data: `$sessionDataPath"
                `$filesDeleted = 0
                Get-ChildItem -Path `$sessionDataPath -File | ForEach-Object { 
                    Remove-Item -Path `$_.FullName -Force 
                    `$filesDeleted++
                }
                if (`$filesDeleted -gt 0) { Write-Host "  [SUCCESS] Removed `$filesDeleted session files." }
            }
        }
    }
}
Write-Host "`n========================================="
Write-Host "            SCRIPT COMPLETED             "
Write-Host "========================================="
"@

# (B) Instance Verification Script
$VerificationScriptContent = @"
param([string]`$LogPath)

function Log-Msg {
    param([string]`$Msg, [string]`$Color="White")
    Write-Host `$Msg -ForegroundColor `$Color
    if (`$LogPath -and (Test-Path (Split-Path `$LogPath))) {
        Add-Content -Path `$LogPath -Value `$Msg
    }
}

Log-Msg "[INFO] Starting DLL verification..." "Cyan"

`$prophoenixPaths = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    `$driveRoot = "`$(`$_.Root)Program Files\ProPhoenix"
    if (Test-Path `$driveRoot) { `$driveRoot }
}

if (-not `$prophoenixPaths) {
    Log-Msg "[ERROR] No ProPhoenix installation found." "Red"
    exit
}

# --- EXCLUSION LIST ---
`$excludedFolders = @(
    "PhoenixHub",
    "Phoenix Gateway",
    "Payment Gateway",
    "FTP"
)

`$completedCount = 0
`$notCompletedCount = 0
`$totalChecked = 0

foreach (`$basePath in `$prophoenixPaths) {
    Log-Msg "`n[INFO] Scanning applications in: `$basePath" "Yellow"

    `$appFolders = Get-ChildItem -Path `$basePath -Directory -ErrorAction SilentlyContinue | 
                  Where-Object { `$excludedFolders -notcontains `$_.Name }

    foreach (`$app in `$appFolders) {
        `$instancesPath = Join-Path `$app.FullName "_Instances"
        `$baseDlls = Get-ChildItem -Path `$app.FullName -Filter *.dll -File -ErrorAction SilentlyContinue

        # --- CHECK 1: Main Application Verification ---
        if (Test-Path `$instancesPath) {
            # Scenario A: App has Instances
            `$instanceEnvs = Get-ChildItem -Path `$instancesPath -Directory -ErrorAction SilentlyContinue
            
            foreach (`$env in `$instanceEnvs) {
                `$instanceDlls = Get-ChildItem -Path `$env.FullName -Filter *.dll -File -ErrorAction SilentlyContinue
                `$status = "Completed"

                foreach (`$dll in `$baseDlls) {
                    `$match = `$instanceDlls | Where-Object { `$_.Name -eq `$dll.Name }
                    if (`$match) {
                        if ((`$match.LastWriteTime -lt `$dll.LastWriteTime) -or (`$match.Length -ne `$dll.Length)) {
                            `$status = "Not Completed"; break
                        }
                    } else { `$status = "Not Completed"; break }
                }

                `$totalChecked++
                if (`$status -eq "Completed") {
                    `$completedCount++
                    Log-Msg ("[OK] " + `$app.Name + " -> " + `$env.Name + " : Completed") "Green"
                } else {
                    `$notCompletedCount++
                    Log-Msg ("[WARN] " + `$app.Name + " -> " + `$env.Name + " : Not Completed") "Red"
                }
            }
        } elseif (`$baseDlls.Count -gt 0) {
            # Scenario B: App has NO Instances (e.g., Police RMS) - Verify Base
            `$totalChecked++
            `$completedCount++
            Log-Msg ("[OK] " + `$app.Name + " (Base) : Verified") "Green"
        }

        # --- CHECK 2: Nested Help Docs Verification ---
        `$helpDocsPath = Join-Path `$app.FullName "UserDocs"
        if (Test-Path `$helpDocsPath) {
             `$hdFiles = Get-ChildItem -Path `$helpDocsPath -File -ErrorAction SilentlyContinue
             if (`$hdFiles.Count -gt 0) {
                 `$totalChecked++
                 `$completedCount++
                 Log-Msg ("[OK] " + `$app.Name + " F1 Help Docs : Verified") "Green"
             }
        }
    }
}

Log-Msg "`n--------------------------------------" "White"
Log-Msg ("Total Verified : " + `$totalChecked) "White"
Log-Msg ("Completed      : " + `$completedCount) "Green"
Log-Msg ("Not Completed  : " + `$notCompletedCount) "Red"
Log-Msg "--------------------------------------" "White"
[Console]::ResetColor()
"@

# (C) Automated Screenshot Script
$ScreenshotScriptContent = @"
param([string]`$LogDir, [string]`$Prefix)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
`$bmp = New-Object System.Drawing.Bitmap `$screen.Width, `$screen.Height
`$graphics = [System.Drawing.Graphics]::FromImage(`$bmp)
`$graphics.CopyFromScreen(`$screen.Location, [System.Drawing.Point]::Empty, `$screen.Size)
`$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
`$file = Join-Path `$LogDir "`$Prefix`_`$timestamp.png"
`$bmp.Save(`$file, [System.Drawing.Imaging.ImageFormat]::Png)
`$graphics.Dispose()
`$bmp.Dispose()
Write-Host "Screenshot saved to: `$file" -ForegroundColor Cyan
"@

# --- 2. CONFIGURATION ---
$ClientAppsDef = @{
    "CAD Client"     = "KPI.Phoenix.CADClient.exe"
    "WDA"            = "KPI.Phoenix.CADMobileClient.exe"
    "Phoenix WDA V2" = "Phoenix.WDAV2.Client.Shell.exe"
}

# FULL SERVICE LIST
$ServiceProductList = @(
    "JobServer", "TraCSServer", "VideoServer", "FingerPrintServer", "EmailWatcher", 
    "CADServer", "CADNLBServer", "CAD2CADTellusServer", "E911Server", "ZetronServer", 
    "ExternalInterface", "GPSServer", "NCICServer", "NCICStateServer", "FTPServer", 
    "LocutionCADVoiceServer", "DeviceNotification", "StreamingNotification", "ReportService", 
    "FolderWatcher", "DocsServer", "PhoenixTonerServer", "PhoenixAlertApp", "PhoenixTExt2Dispatch", 
    "PHOENIXAIWATCHERSERVICE", "PHOENIXJOBSVRV2"
)

# UPDATED MAPPING DATA (FROM USER)
$RawMappingData = @"
::Script - Updating Root path for all products
%AppMgrExePath%\PnxAppMgr.exe "MAINSETTINGS" "RMSRootPath" "PoliceRms=%PnxInstallPath%\Police RMS" "FireRms=%PnxInstallPath%\Fire RMS" "JobServer=%PnxInstallPath%\Job Server" "TraCSServer=%PnxInstallPath%\TraCS Server" "VideoServer=%PnxInstallPath%\Video Server" "FingerPrintServer=%PnxInstallPath%\Finger Print Server" "ReportServer=%PnxInstallPath%\Report Server" "ReportService=%PnxInstallPath%\Report Service" "PhoenixWebService=%PnxInstallPath%\WebService" "HazmatGuide=%PnxInstallPath%\User Docs" "FireWebService=%PnxInstallPath%\Fire WebService" "ProvisionManager=%PnxInstallPath%\Provision Manager" "FolderWatcher=%PnxInstallPath%\PnxFolderWatcher" "InternalAffair=%PnxInstallPath%\PhoenixIA" "NIBRS=%PnxInstallPath%\NIBRSInterface" "EmailWatcher=%PnxInstallPath%\Phoenix Email Watcher" "PoliceF1HelpDocs=%PnxInstallPath%\Police RMS\UserDocs" "FireF1HelpDocs=%PnxInstallPath%\Fire RMS\UserDocs" "IAF1HelpDocs=%PnxInstallPath%\PhoenixIA\UserDocs"

::Script - Updating Root path for all products
%AppMgrExePath%\PnxAppMgr.exe "MAINSETTINGS" "CADRootPath" "CADServer=%PnxInstallPath%\CAD Server" "CADNLBServer=%PnxInstallPath%\CAD NLB Message Server" "E911Server=%PnxInstallPath%\E911 Server" "GPSServer=%PnxInstallPath%\GPS Server" "ZetronServer=%PnxInstallPath%\CAD Zetron Server" "TonerWIServer=%PnxInstallPath%\Toner WI Server" "ExternalInterface=%PnxInstallPath%\External Interface Server" "NCICServer=%PnxInstallPath%\NCIC Server" "NCICStateServer=%PnxInstallPath%\NCIC State Server" "KGISPDServer=%PnxInstallPath%\KGIS PD WebService" "KGISCentralServer=%PnxInstallPath%\KGIS Central WebService" "LocutionCADVoiceServer=%PnxInstallPath%\Locution CAD Voice Server" "DeviceNotification=%PnxInstallPath%\Phoenix Device Notification" "DeviceNotification=%PnxInstallPath%\Device Notification Server" "PnxWDAAppWebService=%PnxInstallPath%\WDA App webservice" "PnxWDAAppWebService=%PnxInstallPath%\Fire Response CAD Webservice" "StreamingNotification=%PnxInstallPath%\Streaming Notification" "PhoenixAlertApp=%PnxInstallPath%\Alert App" "PhoenixTExt2Dispatch=%PnxInstallPath%\Text2Dispatch" "PhoenixTExt2Dispatch=%PnxInstallPath%\CADText2Dispatch" "PhoenixTExt2Dispatch=%PnxInstallPath%\CADTxt2Dispatch" "PhoenixTExt2Dispatch=%PnxInstallPath%\Txt2Dispatch" "CAD2CADTellusServer=%PnxInstallPath%\CAD2CAD Tellus Server" "ReportWriterAPI=%PnxInstallPath%\Phoenix Report Writer API"

::Script - Updating Root path for all products
%AppMgrExePath%\PnxAppMgr.exe "MAINSETTINGS" "OtherRootPath" "CitizenServices=%PnxInstallPath%\Citizen Services Link" "InmateLookup=%PnxInstallPath%\Inmate Lookup" "WIJIS=%PnxInstallPath%\WIJIS" "SWISS=%PnxInstallPath%\SWISS" "CJIN=%PnxInstallPath%\CJIN Integration Service" "NDEX=%PnxInstallPath%\WIJIS NDEX WebService" "FTPServer=%PnxInstallPath%\FTP Server" "CRM=%PnxInstallPath%\CRM" "InmateLocator=%PnxInstallPath%\Inmate Locator" "FireCSPWCF=%PnxInstallPath%\FireCSPhoenixLink" "PoliceCSPWebAPI=%PnxInstallPath%\CitizenServices" "FireCSPWebsite=%PnxInstallPath%\FireCitizenServices" "ADRWebService=%PnxInstallPath%\ADRCollectionRepositoryWS" "WhatsNewWebService=%PnxInstallPath%\WhatsNewWebService" "DocsServer=%PnxInstallPath%\DocsServer" "PhoenixTonerServer=%PnxInstallPath%\Toner Server" "JailCellCheck=%PnxInstallPath%\Jail Cell Check App Service" "ScenePD=%PnxInstallPath%\PhoenixScenePD" "PDFService=%PnxInstallPath%\PhoenixPDFService" "PDFService=%PnxInstallPath%\Phoenix PDF Service" "DBUtility=%PnxInstallPath%\Database Utility"

::Script - Updating Root path for all products
%AppMgrExePath%\PnxAppMgr.exe "MAINSETTINGS" "StageForClientAppsRootPath" "StageCADClient=%PnxInstallPath%\FTP\CAD Client Stage" "StageWDA=%PnxInstallPath%\FTP\WDA Stage" "StagePrintClient=%PnxInstallPath%\FTP\Print Server Stage" "StageClientAppManager=%PnxInstallPath%\FTP\Client Application Manager Stage" "StageFingerPrintClient=%PnxInstallPath%\FTP\Finger Print Client Stage" "StageIDScannerClient=%PnxInstallPath%\FTP\ID Scanner Stage" "StageStationKIOSKRFIDClient=%PnxInstallPath%\FTP\Station KIOSK RFID Client Stage" "StageRFIDClient=%PnxInstallPath%\FTP\RFID Client Stage" "StageAVLRecorder=%PnxInstallPath%\FTP\AVL Recorder Stage" "StageInOutClient=%PnxInstallPath%\FTP\In Out Client Stage" "StageZetronClient=%PnxInstallPath%\FTP\Zetron Client Stage" "StagePhoenixDashboard=%PnxInstallPath%\FTP\Phoenix Dashboard Stage" "StageMobileInspectionApp=%PnxInstallPath%\FTP\Mobile Inspection App Stage" "PHOENIXJOBSVRV2=%PnxInstallPath%\Job Server V2" "PHOENIXAIWATCHERSERVICE=%PnxInstallPath%\Phoenix AI Watcher" "PNXDIAGRAM=%PnxInstallPath%\PNXDiagram" "PNXDIAGRAMAPI=%PnxInstallPath%\PNXDiagramAPI" "INSPECTIONAPI=%PnxInstallPath%\Phoenix Inspection API" "FIRECSPCONVERSION=%PnxInstallPath%\Fire CSP Conversion" "CAMERASERVER=%PnxInstallPath%\Phoenix Camera Server" "PHOENIXPAWN=%PnxInstallPath%\Phoenix Pawn" "StagePhoenixWDAV2=%PnxInstallPath%\FTP\Phoenix WDA V2 Stage"

:: --- AUTOMATICALLY ADDED MAPPINGS (FOUND IN YOUR APPREG_MAIN.XML BUT MISSING ABOVE) ---
"Authenticator=%PnxInstallPath%\Phoenix Authenticator" "InterfaceFolderWatcher=%PnxInstallPath%\Phoenix Interface Folder Watcher" "RegionalCAD2CAD=%PnxInstallPath%\Phoenix Regional CAD2CAD Service" "CADLiveStreaming=%PnxInstallPath%\CADLiveStreamingService" "CADLiveStreaming=%PnxInstallPath%\Phoenix CAD Live Streaming Service" "DBUtilityCodeBook=%PnxInstallPath%\Phoenix Database Utility CodeBook" "CRMHubAPI=%PnxInstallPath%\CRMHubAPI" "CSPProcessQueue=%PnxInstallPath%\CSPProcessQueueService" "CSPConversion=%PnxInstallPath%\CSP Conversion" "AIMugMatch=%PnxInstallPath%\PhoenixAIMugMatch" "AIAPI=%PnxInstallPath%\CRMHubAPI\PNXAIAPI" "ExpenseAPI=%PnxInstallPath%\CRMHubAPI\PNXExpenseAPI" "CustomerAPI=%PnxInstallPath%\CRMHubAPI\PNXCustomerAPI" "EmploymentClient=%PnxInstallPath%\Phoenix Employment Client" "AzureFileDownloader=%PnxInstallPath%\Azure File Downloader"
"@

Clear-Host
Write-Host "==============================================" -ForegroundColor Yellow
Write-Host "   ProPhoenix Test / Demo Hotfix" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Yellow

# --- 2.5: UPDATER SETTINGS CHECK ---
$ConfigFilesToCheck = @(
    "ProPhoenix\Server Application Manager\PnxConfigMgr.exe.config",
    "ProPhoenix\Phoenix Server Application Manager\PnxConfigMgr.exe.config",
    "Program Files (x86)\ProPhoenix\Server Application Manager\PnxConfigMgr.exe.config",
    "Program Files (x86)\ProPhoenix\Phoenix Server Application Manager\PnxConfigMgr.exe.config"
)

Write-Host "`n[INFO] Checking Updater Settings..." -ForegroundColor Cyan
$Drives = Get-PSDrive -PSProvider FileSystem
$FoundConfig = $false

foreach ($d in $Drives) {
    foreach ($cfgPath in $ConfigFilesToCheck) {
        $fullPath = Join-Path -Path $d.Root -ChildPath $cfgPath
        if (Test-Path $fullPath) {
            try {
                [xml]$configXml = Get-Content -Path $fullPath
                $updateLoc = ($configXml.configuration.appSettings.add | Where-Object { $_.key -eq "UpdateLocation" }).value
                $updateUser = ($configXml.configuration.appSettings.add | Where-Object { $_.key -eq "UpdateUserName" }).value
                
                Write-Host "  Found Config: $fullPath" -ForegroundColor Green
                Write-Host "  Update Location: $updateLoc" -ForegroundColor Cyan
                Write-Host "  Update User:     $updateUser" -ForegroundColor Cyan
                $FoundConfig = $true
            } catch {
                Write-Host "  [WARN] Failed to read config: $fullPath" -ForegroundColor Red
            }
        }
    }
}
if (-not $FoundConfig) { Write-Host "  [INFO] No Updater Config file found." -ForegroundColor DarkGray }

# --- 3. FIND INSTANCES ---
$FileName = "Appreg_main.xml"
Write-Host "`n[STEP 1] Scanning for $FileName..." -ForegroundColor Cyan

$PossibleParents = @(
    "ProPhoenix\Server Application Manager",
    "Program Files (x86)\ProPhoenix\Server Application Manager",
    "Program Files\ProPhoenix\Server Application Manager",
    "ProPhoenix\Phoenix Server Application Manager",
    "Program Files (x86)\ProPhoenix\Phoenix Server Application Manager",
    "Program Files\ProPhoenix\Phoenix Server Application Manager"
)
$FoundFiles = @()

foreach ($d in $Drives) {
    foreach ($folder in $PossibleParents) {
        $TestPath = Join-Path -Path $d.Root -ChildPath $folder
        $FullFilePath = Join-Path -Path $TestPath -ChildPath $FileName
        if (Test-Path $FullFilePath) { $FoundFiles += $FullFilePath }
    }
}

if ($FoundFiles.Count -eq 0) {
    Write-Error "No instances found. Exiting."
    Start-Sleep -Seconds 3; exit
}

# --- 4. FIND CLIENT APPS ---
Write-Host "`n[STEP 1.5] Scanning for Client Applications..." -ForegroundColor Cyan
$ClientLaunchLogic = ""
$CommonRoots = @(
    "ProPhoenix", 
    "Program Files\ProPhoenix", 
    "Program Files (x86)\ProPhoenix"
)

foreach ($key in ($ClientAppsDef.Keys | Sort-Object)) {
    $FolderName = $key
    $ExeName = $ClientAppsDef[$key]
    $FoundClient = $false
    foreach ($d in $Drives) {
        foreach ($root in $CommonRoots) {
            $TryPath = Join-Path -Path $d.Root -ChildPath $root | Join-Path -ChildPath $FolderName | Join-Path -ChildPath $ExeName
            if (Test-Path $TryPath) {
                Write-Host "  [FOUND] $FolderName -> $TryPath" -ForegroundColor Green
                
                $PSCommand = "
                `$path = '$TryPath'; 
                `$desktop = [Environment]::GetFolderPath('Desktop'); 
                `$public = [Environment]::GetFolderPath('CommonDesktopDirectory'); 
                `$shell = New-Object -ComObject WScript.Shell; 
                `$shortcut = Get-ChildItem -Path `$desktop, `$public -Filter '*.lnk' | Where-Object { `$shell.CreateShortcut(`$_.FullName).TargetPath -eq `$path } | Select-Object -First 1; 
                if (`$shortcut) { 
                    Write-Host 'Found Shortcut: ' `$shortcut.Name; 
                    Start-Process `$shortcut.FullName -Verb RunAs; 
                } else { 
                    Write-Host 'No shortcut found, running exe directly.'; 
                    Start-Process `$path -Verb RunAs; 
                }"
                
                $PSCommandFlat = $PSCommand -replace "`r`n", " " -replace "\s+", " "
                $ClientLaunchLogic += "%PSExe% -WindowStyle Hidden -Command `"$PSCommandFlat`"`r`n"
                
                $FoundClient = $true
                break
            }
        }
        if ($FoundClient) { break }
    }
}

# --- 5. PROCESS LOOP ---
$InstanceCount = 1

foreach ($FoundPath in $FoundFiles) {
    Write-Host "`n--------------------------------------------------" -ForegroundColor Yellow
    Write-Host " PROCESSING INSTANCE #$InstanceCount" -ForegroundColor Yellow
    Write-Host " Source: $FoundPath" -ForegroundColor Gray
    Write-Host "--------------------------------------------------" -ForegroundColor Yellow
    
    $InstallDrive = (Split-Path $FoundPath -Qualifier)
    $AppMgrFolder = (Split-Path $FoundPath -Parent)
    
    # Logging Setup
    $LogDir = Join-Path -Path $AppMgrFolder -ChildPath "PnxLog\PrintLog"
    if (-not (Test-Path $LogDir)) { try { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null } catch {} }
    if (-not (Test-Path $LogDir)) { $LogDir = $env:TEMP }
    $LogFileName = "InstallGen_Inst${InstanceCount}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $LogFile = Join-Path -Path $LogDir -ChildPath $LogFileName

    $LogMsg = {
        param([string]$Msg, [string]$Lvl="INFO", [string]$Clr="White")
        $TS = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "[$TS] [$Lvl] $Msg"
        if ($Lvl -eq "ERROR") { Write-Host $Msg -ForegroundColor Red }
        elseif ($Lvl -eq "SUCCESS") { Write-Host $Msg -ForegroundColor Green }
        elseif ($Lvl -eq "WARN") { Write-Host $Msg -ForegroundColor Yellow }
        else { Write-Host $Msg -ForegroundColor $Clr }
    }
    & $LogMsg -Msg "Logging started: $LogFile" -Clr Cyan

    # Backup XML
    Write-Host "`n[STEP 2] Backing up Configuration..." -ForegroundColor Cyan
    $BackupFile = "$FoundPath.$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
    try {
        Copy-Item -Path $FoundPath -Destination $BackupFile -ErrorAction Stop
        & $LogMsg -Msg "Backup created: $BackupFile" -Lvl SUCCESS
    } catch { & $LogMsg -Msg "Backup Failed" -Lvl ERROR; continue }

    # Prepare PnxTemp
    Write-Host "`n[STEP 3] Preparing PnxTemp & Helper Scripts..." -ForegroundColor Cyan
    $PnxTempPath = Join-Path -Path (Split-Path $AppMgrFolder -Parent) -ChildPath "PnxTemp"
    if (-not (Test-Path $PnxTempPath)) { try { New-Item -ItemType Directory -Path $PnxTempPath -Force | Out-Null } catch {} }

    # Write Helper Scripts
    $LogClearPath = Join-Path -Path $PnxTempPath -ChildPath "LogClear.ps1"
    Set-Content -Path $LogClearPath -Value $LogClearScriptContent -Encoding ASCII
    & $LogMsg -Msg "Generated Helper Script: $LogClearPath" -Lvl SUCCESS

    $VerifyScriptPath = Join-Path -Path $PnxTempPath -ChildPath "InstanceVerification.ps1"
    Set-Content -Path $VerifyScriptPath -Value $VerificationScriptContent -Encoding ASCII
    & $LogMsg -Msg "Generated Helper Script: $VerifyScriptPath" -Lvl SUCCESS

    $ScreenshotPath = Join-Path -Path $PnxTempPath -ChildPath "TakeScreenshot.ps1"
    Set-Content -Path $ScreenshotPath -Value $ScreenshotScriptContent -Encoding ASCII
    & $LogMsg -Msg "Generated Helper Script: $ScreenshotPath" -Lvl SUCCESS

    # Parse Mappings
    Write-Host "`n[STEP 4] Analyzing Products..." -ForegroundColor Cyan
    $PathMap = @{}
    $Regex = '"([^"]+)=%PnxInstallPath%\\([^"]+)"'
    foreach ($m in [regex]::Matches($RawMappingData, $Regex)) {
        $ShortID = $m.Groups[1].Value
        $Suffix = $m.Groups[2].Value.Replace("/", "\").Trim()
        if (-not $PathMap.ContainsKey($Suffix)) { $PathMap[$Suffix] = $ShortID }
    }

    try { [xml]$xmlData = Get-Content $FoundPath } catch { & $LogMsg -Msg "Invalid XML" -Lvl ERROR; continue }
    
    $InstallArgs = new-object System.Collections.Generic.List[string]
    $UpdateArgs  = new-object System.Collections.Generic.List[string]
    $InstallArgs.Add('"INSTALL"')
    $UpdateArgs.Add('"UPDATEINSTANCE"')

    if ($xmlData.PhoenixApplications.AppReg) {
        foreach ($app in $xmlData.PhoenixApplications.AppReg) {
            $Ver = $app.CurrentVersion
            
            # --- FIX: Trim trailing slashes from path to match the dictionary properly ---
            $FPath = $app.AppPath.Replace("/", "\").Trim().TrimEnd('\')
            
            # --- STRICT EXCLUSION ---
            if ($app.AppName -match "Hub|Gateway" -or $FPath -match "Hub|Gateway") {
                & $LogMsg -Msg "Skipped: $($app.AppName) (Excluded by Hub/Gateway rule)" -Lvl WARN
                continue
            }

            if ($Ver -ne "0.0.0.0") {
                $BestID = $null; $BestLen = 0
                foreach ($k in $PathMap.Keys) {
                    if ($FPath.EndsWith($k, [System.StringComparison]::OrdinalIgnoreCase)) {
                        if ($k.Length -gt $BestLen) { $BestID = $PathMap[$k]; $BestLen = $k.Length }
                    }
                }
                if ($BestID) {
                    $InstallArgs.Add("`"$BestID`"")
                    $LogStr = "Included: $($app.AppName) -> $BestID"
                    if ($ServiceProductList -contains $BestID) {
                        $UpdateArgs.Add("`"$BestID`"")
                        $LogStr += " [Service Updated]"
                    }
                    & $LogMsg -Msg $LogStr -Lvl SUCCESS
                } else { & $LogMsg -Msg "Skipped: $($app.AppName) (No mapping found)" -Lvl WARN }
            }
        }
    }

    # --- TAKE POWERSHELL FETCH SCREENSHOT ---
    Start-Sleep -Seconds 1
    & $LogMsg -Msg "Taking Screenshot of PowerShell Product Fetch..." -Lvl INFO
    % { & $PSHOME\powershell.exe -ExecutionPolicy Bypass -Command "& '$ScreenshotPath' -LogDir '$LogDir' -Prefix 'PS_ProductFetch'" }

    # Generate PRIMARY Batch File
    Write-Host "`n[STEP 5] Generating Primary Batch File..." -ForegroundColor Cyan
    $InstallLine = $InstallArgs -join " "
    $UpdateLine  = $UpdateArgs -join " "
    
    $BaseName = "Hotfix_Automation"; $Ext = ".bat"; $Counter = 0
    $FinalName = "$BaseName$Ext"
    $OutputBatFile = Join-Path -Path $PnxTempPath -ChildPath $FinalName
    while (Test-Path $OutputBatFile) {
        $Counter++; $FinalName = "${BaseName}${Counter}${Ext}"; $OutputBatFile = Join-Path -Path $PnxTempPath -ChildPath $FinalName
    }

    $PathParts = $AppMgrFolder.Split('\')
    $CdBlock = "$InstallDrive`r`ncd ..\..\..\..\`r`n"
    for ($i = 1; $i -lt $PathParts.Count; $i++) { if ($PathParts[$i]) { $CdBlock += "cd `"$($PathParts[$i])`"`r`n" } }

    $UpdateCmd = ""
    if ($UpdateArgs.Count -gt 1) {
        $UpdateCmd = "::Script - Updating Windows Service Instance`r`n%AppMgrExePath%\PnxAppMgr.exe $UpdateLine | %PSExe% -Command `"`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }`"`r`n"
    }

    # --- PRIMARY BATCH FILE CONTENT ---
    $BatchContent = @"
$CdBlock
@echo off
SET AppMgrExePath="$AppMgrFolder"
SET PSExe=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe

:: --- SIMPLE LOGGING (Crash Free) ---
SET LOGFILE="%~dp0Install_Log.txt"
SET LOGFILE_PATH=%~dp0Install_Log.txt

echo Logging Execution to: %LOGFILE%
echo --- Installation Started --- > %LOGFILE%

echo ===================================================
echo   STEP 0: UPDATING APPLICATION MANAGER
echo ===================================================
echo [LOG] Updating Application Manager... >> %LOGFILE%
%AppMgrExePath%\PnxAppMgr.exe "UPDAPPMANAGER" | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo ===================================================
echo   STEP 1: STOPPING SERVICES AND PROCESSES
echo ===================================================
echo [LOG] Stopping IIS... >> %LOGFILE%
%windir%\System32\iisreset.exe /stop | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1
%windir%\System32\sc.exe query W3SVC | find "STATE" | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo Killing Client Applications (if running)...
echo [LOG] Killing Client Apps... >> %LOGFILE%
%windir%\System32\taskkill.exe /F /IM "KPI.Phoenix.CADClient.exe" /T 2>nul >> %LOGFILE% 2>&1
%windir%\System32\taskkill.exe /F /IM "KPI.Phoenix.CADMobileClient.exe" /T 2>nul >> %LOGFILE% 2>&1
%windir%\System32\taskkill.exe /F /IM "Phoenix.WDAV2.Client.Shell.exe" /T 2>nul >> %LOGFILE% 2>&1

echo Stopping Phoenix Services...
echo [LOG] Stopping Phoenix Services... >> %LOGFILE%
%PSExe% -Command "Get-Service -Name 'Phoenix*' | Where-Object { `$_.Status -eq 'Running' } | ForEach-Object { Stop-Service -Name `$_.Name -Force }" >> %LOGFILE% 2>&1

echo ===================================================
echo   STEP 2: CLEANING LOGS AND SESSION DATA
echo ===================================================
echo Running Cleaner Script...
echo [LOG] Running LogClear.ps1... >> %LOGFILE%
%PSExe% -ExecutionPolicy Bypass -File "%~dp0LogClear.ps1" | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo ===================================================
echo   STEP 3: INSTALLATION
echo ===================================================
:loopSelf
%windir%\System32\tasklist.exe /fi "imagename eq PnxAppMgr.exe" |find ":" > nul
if "%ERRORLEVEL%"=="1" goto loopSelf

::Script - Installing products
echo [LOG] Running PnxAppMgr Install... >> %LOGFILE%
%AppMgrExePath%\PnxAppMgr.exe $InstallLine | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo ===================================================
echo   STEP 4: STARTING IIS AND UPDATING INSTANCES
echo ===================================================
echo Starting IIS...
echo [LOG] Starting IIS... >> %LOGFILE%
%windir%\System32\iisreset.exe /start | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1
%windir%\System32\sc.exe query W3SVC | find "STATE" | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo [LOG] Updating Windows Instances... >> %LOGFILE%
$UpdateCmd

::Show Instances
%AppMgrExePath%\PnxAppMgr.exe "SHOWINSTANCES" | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo ===================================================
echo   STEP 4.5: STARTING PHOENIX SERVICES
echo ===================================================
echo Starting Phoenix Services...
echo [LOG] Starting Phoenix Services... >> %LOGFILE%
%PSExe% -Command "Get-Service -Name 'Phoenix*' | Where-Object { `$_.Status -eq 'Stopped' } | ForEach-Object { Start-Service -Name `$_.Name; Write-Host 'Started ' `$_.Name }" 2>&1 | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo ===================================================
echo   STEP 4.6: VERIFYING INSTANCE UPDATES
echo ===================================================
echo Running Instance Verification...
echo [LOG] Running Instance Verification... >> %LOGFILE%
%PSExe% -ExecutionPolicy Bypass -Command "& '%~dp0InstanceVerification.ps1' -LogPath '%LOGFILE_PATH%'"

echo.
echo ===================================================
echo   TAKING SCREENSHOT OF VERIFICATION STATUS
echo ===================================================
%PSExe% -ExecutionPolicy Bypass -Command "& '%~dp0TakeScreenshot.ps1' -LogDir '$LogDir' -Prefix 'Bat_PrimaryVerification'"

echo ===================================================
echo   STEP 5: LAUNCHING CLIENT APPLICATIONS
echo ===================================================
echo [LOG] Launching Clients... >> %LOGFILE%
$ClientLaunchLogic

echo.
echo Process Complete. Log saved to: %LOGFILE%
echo Auto-Closing in 5 seconds...
timeout /t 5 >nul
::End of Script::
"@

    try {
        Set-Content -Path $OutputBatFile -Value $BatchContent -Encoding ASCII
        & $LogMsg -Msg "SUCCESS! Primary Script created at: $OutputBatFile" -Lvl SUCCESS
    } catch { & $LogMsg -Msg "Failed to write Primary BAT file" -Lvl ERROR }

    # --- 6. GENERATE SECONDARY BATCH FILE (INSTANCE UPDATE ONLY) ---
    Write-Host "`n[STEP 6] Generating Secondary Script (Instance Update Only)..." -ForegroundColor Cyan
    $SecondaryBatDir = "C:\pnxtemp\Phoenix Installation Master\Phoenix Installation Master"
    
    # Ensure nested directory path exists
    if (-not (Test-Path $SecondaryBatDir)) { 
        try { New-Item -ItemType Directory -Path $SecondaryBatDir -Force | Out-Null } catch { } 
    }

    # Copy the verification and screenshot scripts into this secondary folder so it can execute locally
    $SecondaryVerifyScriptPath = Join-Path -Path $SecondaryBatDir -ChildPath "InstanceVerification.ps1"
    Set-Content -Path $SecondaryVerifyScriptPath -Value $VerificationScriptContent -Encoding ASCII
    
    $SecondaryScreenshotPath = Join-Path -Path $SecondaryBatDir -ChildPath "TakeScreenshot.ps1"
    Set-Content -Path $SecondaryScreenshotPath -Value $ScreenshotScriptContent -Encoding ASCII

    $SecondaryBatFile = Join-Path -Path $SecondaryBatDir -ChildPath "Instance Update(BS).bat"

    $SecondaryBatchContent = @"
$CdBlock
@echo off
SET AppMgrExePath="$AppMgrFolder"
SET PSExe=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe

:: --- SIMPLE LOGGING ---
SET LOGFILE="%~dp0InstanceUpdate_Log.txt"
SET LOGFILE_PATH=%~dp0InstanceUpdate_Log.txt

echo Logging Execution to: %LOGFILE%
echo --- Instance Update Started --- > %LOGFILE%

echo ===================================================
echo   STEP 1: STOPPING PHOENIX SERVICES
echo ===================================================
echo Stopping Phoenix Services...
echo [LOG] Stopping Phoenix Services... >> %LOGFILE%
%PSExe% -Command "Get-Service -Name 'Phoenix*' | Where-Object { `$_.Status -eq 'Running' } | ForEach-Object { Stop-Service -Name `$_.Name -Force }" >> %LOGFILE% 2>&1

echo ===================================================
echo   STEP 2: UPDATING INSTANCES
echo ===================================================
echo [LOG] Updating Windows Instances... >> %LOGFILE%
$UpdateCmd

::Show Instances
%AppMgrExePath%\PnxAppMgr.exe "SHOWINSTANCES" | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo ===================================================
echo   STEP 3: STARTING PHOENIX SERVICES
echo ===================================================
echo Starting Phoenix Services...
echo [LOG] Starting Phoenix Services... >> %LOGFILE%
%PSExe% -Command "Get-Service -Name 'Phoenix*' | Where-Object { `$_.Status -eq 'Stopped' } | ForEach-Object { Start-Service -Name `$_.Name; Write-Host 'Started ' `$_.Name }" 2>&1 | %PSExe% -Command "`$input | ForEach-Object { Write-Host `$_; `$_ | Out-File -FilePath '%LOGFILE%' -Append -Encoding ASCII }" 2>&1

echo ===================================================
echo   STEP 4: VERIFYING INSTANCE UPDATES
echo ===================================================
echo Running Instance Verification...
echo [LOG] Running Instance Verification... >> %LOGFILE%
%PSExe% -ExecutionPolicy Bypass -Command "& '%~dp0InstanceVerification.ps1' -LogPath '%LOGFILE_PATH%'"

echo.
echo ===================================================
echo   TAKING SCREENSHOT OF VERIFICATION STATUS
echo ===================================================
%PSExe% -ExecutionPolicy Bypass -Command "& '%~dp0TakeScreenshot.ps1' -LogDir '$LogDir' -Prefix 'Bat_SecondaryVerification'"

echo.
echo ===================================================
echo   INSTANCE UPDATE COMPLETE
echo ===================================================
echo Auto-Closing in 5 seconds...
timeout /t 5 >nul
::End of Script::
"@

    try {
        Set-Content -Path $SecondaryBatFile -Value $SecondaryBatchContent -Encoding ASCII
        & $LogMsg -Msg "SUCCESS! Secondary Script created at: $SecondaryBatFile" -Lvl SUCCESS
    } catch { & $LogMsg -Msg "Failed to write Secondary BAT file" -Lvl ERROR }

    $InstanceCount++
}

Write-Host "`n==============================================" -ForegroundColor Yellow
Write-Host "   ALL INSTANCES PROCESSED" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Yellow

# --- FULLY AUTOMATED LAUNCH ---
if ($OutputBatFile -and (Test-Path $OutputBatFile)) {
    Write-Host "`nAuto-Launching Primary Batch File in 3 seconds..." -ForegroundColor Green
    Start-Sleep -Seconds 3
    Start-Process -FilePath $OutputBatFile
}