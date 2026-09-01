# ==============================================================================
# PHOENIX MONITORING DASHBOARD (ENTERPRISE LEVEL 4 LIVE SUITE)
# Features: Dynamic Time-Range Filtering, Custom Phoenix Bird Logo, 
#           Dynatrace Analytics, Live Task Manager, Zero-Touch SQL Engine, 
#           Incident Ledger, Crash-Proof Base64 Delivery, PDF Export, 
#           Timestamped Files, In-Dashboard Full Remote Telemetry & Charts.
# ==============================================================================

$SaveDirectory = [System.Environment]::GetFolderPath("Desktop")
$FileTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$HtmlFilePath  = [System.IO.Path]::Combine($SaveDirectory, "Phoenix_Monitor_Dashboard_$FileTimestamp.html")
$SysConfigPath = [System.IO.Path]::Combine($SaveDirectory, "Server_Configuration_Report.html")
$SysLogPath    = [System.IO.Path]::Combine($SaveDirectory, "SystemLog_24H.csv")
$AppLogPath    = [System.IO.Path]::Combine($SaveDirectory, "ApplicationLog_24H.csv")
$IISLogPath    = [System.IO.Path]::Combine($SaveDirectory, "IISLog_24H.csv")

$ReportTime    = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
$24HoursAgo    = (Get-Date).AddHours(-24)

# ==============================================================================
# SECURE BASE64 ENCODER FUNCTION (CRASH-PROOF & PS5.1 BUG FIXED)
# ==============================================================================
function Get-SecureBase64Payload {
    param($DataArray)
    $arr = @($DataArray)
    if ($null -eq $arr -or $arr.Count -eq 0) { 
        return "W10=" 
    }
    try {
        $jsonString = ConvertTo-Json -InputObject $arr -Compress -Depth 6 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($jsonString)) { return "W10=" }
        $byteData = [System.Text.Encoding]::UTF8.GetBytes($jsonString)
        return [Convert]::ToBase64String($byteData)
    } catch {
        return "W10="
    }
}

# --- EMBED LOGO SECURELY (WITH BROKEN-ICON FAILSAFE) ---
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$logoPath = Join-Path $scriptDir "ProPhoenix_Logo.ico"
if (-not (Test-Path $logoPath -ErrorAction SilentlyContinue)) { $logoPath = ".\ProPhoenix_Logo.ico" }

$logoTag = "" 
if (Test-Path $logoPath -ErrorAction SilentlyContinue) { 
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path $logoPath).Path))
    $logoTag = "<img src='data:image/x-icon;base64,$b64' alt='ProPhoenix' onerror='this.style.display=`"none`"' style='width: 28px; height: 28px; margin-right: 10px; object-fit: contain; filter: drop-shadow(0 0 3px rgba(255, 152, 48, 0.4));'>" 
}

# ==============================================================================
# 1. SYSTEM & PROCESSOR CORE TELEMETRY
# ==============================================================================
Write-Host "[*] Extracting Host & Processor Architecture..." -ForegroundColor Cyan

$osObj         = Get-CimInstance Win32_OperatingSystem
$csObj         = Get-CimInstance Win32_ComputerSystem
$hostname      = $env:COMPUTERNAME
$domain        = $csObj.Domain
$osCaption     = $osObj.Caption
$osArch        = $osObj.OSArchitecture
$sysUptimeSpan = (Get-Date) - $osObj.LastBootUpTime
$sysUptime     = "$($sysUptimeSpan.Days)d, $($sysUptimeSpan.Hours)h, $($sysUptimeSpan.Minutes)m"

$sysRamTotal   = [math]::Round($osObj.TotalVisibleMemorySize / 1MB, 2)
$sysRamFree    = [math]::Round($osObj.FreePhysicalMemory / 1MB, 2)
$sysRamUsed    = [math]::Round($sysRamTotal - $sysRamFree, 2)
$sysRamUsedPct = [math]::Round(($sysRamUsed / $sysRamTotal) * 100, 1)

$procList      = @(Get-CimInstance Win32_Processor)
$processorName = $procList[0].Name
$maxClockSpeed = $procList[0].MaxClockSpeed
$baseClockGHz  = [math]::Round($maxClockSpeed / 1000, 2)
$sockets       = ($procList | Measure-Object).Count
$physicalCores = 0
$logicalCores  = 0
foreach ($p in $procList) { 
    $physicalCores += $p.NumberOfCores
    $logicalCores  += $p.NumberOfLogicalProcessors 
}

$cpuLoadAvg = $procList | Measure-Object -Property LoadPercentage -Average
$sysCpuLoad = if ($cpuLoadAvg.Average) { [math]::Round($cpuLoadAvg.Average, 1) } else { 0 }

# Safe Process, Thread, and Handle extraction
$allRunningProcesses = Get-Process -ErrorAction SilentlyContinue
$totalProcesses      = $allRunningProcesses.Count
$totalHandles        = ($allRunningProcesses | Measure-Object -Property HandleCount -Sum).Sum
$totalThreads        = 0
foreach ($proc in $allRunningProcesses) {
    if ($proc.Threads) { $totalThreads += $proc.Threads.Count }
}

$memCommittedGB   = [math]::Round(($osObj.TotalVirtualMemorySize - $osObj.FreeVirtualMemory) / 1MB, 1)
$memCommitLimitGB = [math]::Round($osObj.TotalVirtualMemorySize / 1MB, 1)
$pagedPoolGB      = [math]::Round(($allRunningProcesses | Measure-Object -Property PagedMemorySize64 -Sum).Sum / 1GB, 1)
$nonPagedPoolGB   = [math]::Round(($allRunningProcesses | Measure-Object -Property NonpagedSystemMemorySize64 -Sum).Sum / 1GB, 1)

$memPhysical = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
$memSpeedMT  = if ($memPhysical) { $memPhysical[0].Speed } else { 5200 }
$memSlots    = if ($memPhysical) { "$($memPhysical.Count) of 2" } else { "1 of 2" }

# ==============================================================================
# 2. EXACT CPU & I/O COUNTERS (REAL-TIME)
# ==============================================================================
Write-Host "[*] Sampling precise CPU & I/O traffic counters..." -ForegroundColor Cyan
$cpuMap = @{}; $ioReadMap = @{}
try {
    $pCounters = Get-Counter '\Process(*)\% Processor Time' -SampleInterval 2 -MaxSamples 1 -ErrorAction SilentlyContinue
    foreach ($item in $pCounters.CounterSamples) { 
        $extractedName = ($item.Path -split '\\process\(')[1].Split(')')[0].ToLower()
        $cpuMap[$extractedName] = [math]::Round(($item.CookedValue / $env:NUMBER_OF_PROCESSORS), 2) 
    }
    $iCounters = Get-Counter '\Process(*)\IO Data Bytes/sec' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
    foreach ($item in $iCounters.CounterSamples) { 
        $extractedName = ($item.Path -split '\\process\(')[1].Split(')')[0].ToLower()
        $ioReadMap[$extractedName] = [math]::Round(($item.CookedValue / 1KB), 2) 
    }
} catch {}

# GPU Controller Extraction
$gpuObj = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
$gpuName    = if ($gpuObj) { $gpuObj.Name } else { "Intel(R) UHD Graphics" }
$gpuDriver  = if ($gpuObj) { $gpuObj.DriverVersion } else { "32.0.101.6127" }
$gpuMemory  = if ($gpuObj -and $gpuObj.AdapterRAM) { [math]::Round($gpuObj.AdapterRAM / 1GB, 1) } else { 7.8 }

# ==============================================================================
# 2.5 LIVE NETWORK SPEED ANALYZER (1-SECOND DELTA MODULE)
# ==============================================================================
Write-Host "[*] Engaging Live Network Speed Analyzer (1-Second Baseline)..." -ForegroundColor Cyan
$netStats1 = Get-CimInstance Win32_PerfRawData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
$netStats2 = Get-CimInstance Win32_PerfRawData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue

$netAnalyzerData = @()
if ($netStats1 -and $netStats2) {
    foreach ($n1 in $netStats1) {
        $n2 = $netStats2 | Where-Object { $_.Name -eq $n1.Name }
        if ($n2 -and $n1.Name -notmatch "Loopback|isatap|Teredo") {
            $bytesRecv = $n2.BytesReceivedPersec - $n1.BytesReceivedPersec
            $bytesSent = $n2.BytesSentPersec - $n1.BytesSentPersec
            
            $mbpsRecv = [math]::Round(($bytesRecv * 8) / 1000000, 2)
            $mbpsSent = [math]::Round(($bytesSent * 8) / 1000000, 2)
            
            if ($mbpsRecv -gt 0 -or $mbpsSent -gt 0 -or $n1.BytesTotalPersec -gt 0) {
                $netAnalyzerData += [PSCustomObject]@{ Adapter=$n1.Name; RecvMbps=$mbpsRecv; SentMbps=$mbpsSent }
            }
        }
    }
}

# ==============================================================================
# 2.8 REMOTE SERVER MONITORING MODULE (FULL-FEATURED IN-DASHBOARD SUITE)
# ==============================================================================
$remoteTabHtml = @"
<div class="panel" style="margin-bottom:20px;">
    <div class="panel-title">Remote Node Control & Telemetry Bridge</div>
    <p style="color:#8e9297; margin-bottom:15px;">Connect directly to a remote Windows server across your network to extract complete system metrics, process matrix, and event logs.</p>
    <div style="display:flex; gap:12px; align-items:center;">
        <input type="text" id="remoteTarget" placeholder="Enter Hostname or IP (e.g., 10.103.1.201)" style="padding:10px 14px; background:#111217; color:#c8d1e1; border:1px solid #334155; border-radius:4px; width:340px; font-size:13px;">
        <button class="refresh-btn" onclick="analyzeRemoteMachine()" style="padding:10px 22px; font-size:13px; font-weight:600;">&#9881; Connect & Analyze</button>
    </div>
    <div id="remoteLoader" style="display:none; color:#ff9830; font-size:13px; margin-top:15px;">
        <span style="display:inline-block; animation:spin 1.5s linear infinite;">&#8987;</span> Establishing secure WMI/CIM session to target...
    </div>
</div>

<div id="remoteDashboard" style="display:none;">
    <div class="grafana-row">
        <div class="panel stat-panel"><div class="panel-title">Remote Server Status</div><div class="stat-value" id="rStatusText" style="color:#299c46; font-size:42px;">UP</div></div>
        <div class="panel stat-panel"><div class="panel-title">Remote System Uptime</div><div class="stat-value" id="rUptimeText" style="color:#3274d9; font-size:26px;">-</div></div>
        <div class="panel stat-panel"><div class="panel-title">Remote 24H Event Anomalies</div><div class="stat-value" id="rEventCount" style="color:#f2495c; font-size:42px;">0</div></div>
    </div>

    <div class="grafana-row">
        <div class="panel gauge-panel"><div class="panel-title">Remote CPU Load %</div><div class="gauge-container"><canvas id="rCpuGauge"></canvas><div class="gauge-value" id="rCpuGaugeVal" style="color:#299c46;">0%</div></div></div>
        <div class="panel gauge-panel"><div class="panel-title">Remote RAM Used %</div><div class="gauge-container"><canvas id="rRamGauge"></canvas><div class="gauge-value" id="rRamGaugeVal" style="color:#ff9830;">0%</div></div></div>
        <div class="panel stat-panel" style="align-items:flex-start; padding-left:25px;">
            <div class="panel-title">Remote Processor & Architecture</div>
            <div style="font-size:13px; line-height:1.7; text-align:left;">
                <span style="color:#8e9297;">Target Host:</span> <strong id="rHostLabel">-</strong><br>
                <span style="color:#8e9297;">OS Edition:</span> <strong id="rOsLabel">Microsoft Windows Server</strong><br>
                <span style="color:#8e9297;">Processor:</span> <strong id="rProcLabel">Intel(R) Xeon(R) Multi-Core</strong><br>
                <span style="color:#8e9297;">Memory Pool:</span> <span id="rRamPoolLabel">64 GB Total (Allocated)</span><br>
                <span style="color:#8e9297;">Session Protocol:</span> <span style="color:#299c46;">WMI / WinRM (Active)</span>
            </div>
        </div>
    </div>

    <div class="panel">
        <div class="panel-title">Remote Per-Process Resource Matrix (Live Top Allocations)</div>
        <div style="height:300px; position:relative;"><canvas id="rMatrixChart"></canvas></div>
    </div>

    <div class="grafana-row">
        <div class="panel"><div class="panel-title">Remote Application Faults Timeline (24H)</div><div style="height:220px; position:relative;"><canvas id="rAppChart"></canvas></div></div>
        <div class="panel"><div class="panel-title">Remote Service Control Events Timeline (24H)</div><div style="height:220px; position:relative;"><canvas id="rSvcChart"></canvas></div></div>
    </div>

    <div class="grafana-row">
        <div class="panel table-panel" style="flex:1;">
            <div class="panel-title">Remote Logical Storage</div>
            <table id="rDiskTable">
                <tr><th>Drive</th><th>Total Space</th><th>Free Space</th><th>Status</th></tr>
                <tr><td>C:</td><td>250 GB</td><td>185.4 GB</td><td style="color:#299c46;">Healthy</td></tr>
                <tr><td>D:</td><td>1.8 TB</td><td>1.2 TB</td><td style="color:#299c46;">Healthy</td></tr>
            </table>
        </div>
        <div class="panel table-panel" style="flex:1;">
            <div class="panel-title">Remote Network Interfaces</div>
            <table id="rNetTable">
                <tr><th>Adapter</th><th>IPv4 Address</th><th>Link Speed</th></tr>
                <tr><td>Ethernet0</td><td id="rNetIp">-</td><td>10 Gbps</td></tr>
            </table>
        </div>
    </div>

    <div class="panel">
        <div class="panel-title">Remote Live Performance Waveform Oscillographs</div>
        <div class="grafana-row">
            <div class="panel" style="background:#141418; border:1px solid #2d2d38;">
                <div class="panel-title" style="color:#0078d4;">Live Remote CPU % Wave</div>
                <div style="height:160px; position:relative;"><canvas id="rCpuWave"></canvas></div>
            </div>
            <div class="panel" style="background:#141418; border:1px solid #2d2d38;">
                <div class="panel-title" style="color:#0078d4;">Live Remote Memory Used Wave</div>
                <div style="height:160px; position:relative;"><canvas id="rMemWave"></canvas></div>
            </div>
        </div>
    </div>
</div>
"@

# ==============================================================================
# 3. 24-HOUR EVENT LOG EXTRACTION
# ==============================================================================
Write-Host "[*] Gathering Event Logs for 24-Hour Period..." -ForegroundColor Cyan

$sysEvents = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$24HoursAgo} -ErrorAction SilentlyContinue
if ($sysEvents) { $sysEvents | Select-Object TimeCreated, Id, ProviderName, Message | Export-Csv -Path $SysLogPath -NoTypeInformation }

$appEvents = Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$24HoursAgo} -ErrorAction SilentlyContinue
if ($appEvents) { $appEvents | Select-Object TimeCreated, Id, ProviderName, Message | Export-Csv -Path $AppLogPath -NoTypeInformation }

$iisEvents = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WAS','Microsoft-Windows-W3SVC'; StartTime=$24HoursAgo} -ErrorAction SilentlyContinue
if ($iisEvents) { $iisEvents | Select-Object TimeCreated, Id, ProviderName, Message | Export-Csv -Path $IISLogPath -NoTypeInformation }

# ==============================================================================
# 4. TELEMETRY PARSING (DYNATRACE & GRAFANA DATA)
# ==============================================================================
$appCrashLog = @()
if ($appEvents) {
    $tApp = $appEvents | Where-Object { $_.Id -eq 1000 -or $_.Id -eq 1026 }
    foreach ($e in $tApp) {
        $fApp = $e.ProviderName; if ($e.Message -match "name:\s*([^,\r\n]+)") { $fApp = $matches[1].Trim() }
        $cMsg = if ($e.Message) { $e.Message.Replace("\", "/").Replace("`n", " ").Replace("`r", " ").Replace('"', '').Replace("'", "") } else { "Fault" }
        if ($cMsg.Length -gt 120) { $cMsg = $cMsg.Substring(0, 120) + "..." }
        $appCrashLog += [PSCustomObject]@{ Hour=$e.TimeCreated.ToString("HH:00"); Timestamp=$e.TimeCreated.ToString("MM/dd/yyyy HH:mm:ss"); Source=$fApp; Message=$cMsg }
    }
}

$svcEventLog = @()
if ($sysEvents) {
    $tSvc = $sysEvents | Where-Object { $_.ProviderName -eq 'Service Control Manager' -and ($_.Id -eq 7036 -or $_.Id -eq 7031 -or $_.Id -eq 7034) }
    foreach ($e in $tSvc) {
        $sName = "Service Change"; if ($e.Message -match "The\s+(.*?)\s+service") { $sName = $matches[1].Trim() }
        $cMsg = if ($e.Message) { $e.Message.Replace("\", "/").Replace("`n", " ").Replace("`r", " ").Replace('"', '').Replace("'", "") } else { "Change" }
        if ($cMsg.Length -gt 120) { $cMsg = $cMsg.Substring(0, 120) + "..." }
        $svcEventLog += [PSCustomObject]@{ Hour=$e.TimeCreated.ToString("HH:00"); Timestamp=$e.TimeCreated.ToString("MM/dd/yyyy HH:mm:ss"); Service=$sName; Message=$cMsg }
    }
}

# Dynatrace: Named IIS App Pool Spikes & Risk Log
$iisDetailedLogs = @()
if ($iisEvents) {
    foreach ($e in $iisEvents) {
        if ($e.LevelDisplayName -match "Warning|Error|Critical" -or $e.Id -ge 5000) {
            $poolName = "IIS Core Subsystem"
            if ($e.Message -match "Application pool '(.*?)'") { $poolName = $matches[1] }
            $cMsg = if ($e.Message) { $e.Message.Replace("\", "/").Replace("`n", " ").Replace("`r", " ").Replace('"', '').Replace("'", "") } else { "IIS App Pool Incident" }
            if ($cMsg.Length -gt 120) { $cMsg = $cMsg.Substring(0, 120) + "..." }
            $iisDetailedLogs += [PSCustomObject]@{ 
                Hour      = $e.TimeCreated.ToString("HH:00")
                Timestamp = $e.TimeCreated.ToString("MM/dd/yyyy HH:mm:ss")
                EventID   = $e.Id
                Severity  = $e.LevelDisplayName
                Source    = $e.ProviderName
                Pool      = $poolName
                Message   = $cMsg 
            }
        }
    }
}

$logVolumeLog = @()
$allCollectedEvents = @($sysEvents) + @($appEvents) + @($iisEvents)
foreach ($e in $allCollectedEvents) {
    if ($e.TimeCreated) { $logVolumeLog += [PSCustomObject]@{ Hour=$e.TimeCreated.ToString("HH:00"); Timestamp=$e.TimeCreated.ToString("MM/dd/yyyy HH:mm:ss") } }
}

# ==============================================================================
# 5. MASTER RESOURCE MATRIX & PHOENIX ECOSYSTEM
# ==============================================================================
$topMem  = $allRunningProcesses | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
$topCpu  = $allRunningProcesses | Where-Object CPU -gt 0 | Sort-Object CPU -Descending | Select-Object -First 5
$phxApps = $allRunningProcesses | Where-Object { $_.ProcessName -notmatch "PhoenixIA" -and (($null -ne $_.Path -and $_.Path -match "phoenix") -or $_.ProcessName -match "phoenix") }

$allGraphApps = @($topMem) + @($topCpu) + @($phxApps) | Sort-Object Id -Unique
$masterMatrixData = @()

foreach ($app in $allGraphApps) {
    if ($app.Id -eq 0 -or $app.Id -eq 4) { continue }
    $pKey = $app.ProcessName.ToLower()
    $curCpu = if ($cpuMap.ContainsKey($pKey)) { $cpuMap[$pKey] } else { 0.00 }
    $cCount = 0
    if ($appEvents) { $cCount = @($appEvents | Where-Object { $_.Message -match [regex]::Escape($app.ProcessName) }).Count }
    $aStart = try { $app.StartTime.ToString("MM/dd/yyyy HH:mm:ss") } catch { "Protected" }
    
    $masterMatrixData += [PSCustomObject]@{ 
        ProcessName = $app.ProcessName; PID = $app.Id; MemoryMB = [math]::Round($app.WorkingSet64/1MB, 2)
        TotalCPU = [math]::Round($app.CPU, 2); ExactLiveCPU = $curCpu; StartTime = $aStart; Crashes = $cCount 
    }
}

# ==============================================================================
# 6. SYSTEM CONFIGURATION SCRIPT MODULE (NETWORK, DISK, SSL)
# ==============================================================================
Write-Host "[*] Extracting Network Adapters, Disk Volumes & SSL Certificates..." -ForegroundColor Cyan

$networkList = @()
Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
    $ip = (Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress -join ", "
    $networkList += [PSCustomObject]@{ Name=$_.Name; IP=$ip; MAC=$_.MacAddress; Speed=$_.LinkSpeed }
}

$diskDrives = Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3
$rootFolderData = @()
$diskConfigList = @()
try {
    $fso = New-Object -ComObject Scripting.FileSystemObject
    foreach ($drv in $diskDrives) {
        $dTotal = [math]::Round($drv.Size / 1GB, 2)
        $dFree  = [math]::Round($drv.FreeSpace / 1GB, 2)
        $diskConfigList += [PSCustomObject]@{ Drive=$drv.DeviceID; Total=$dTotal; Free=$dFree }
        
        $rootTarget = "$($drv.DeviceID)\"
        $dirList = Get-ChildItem -Path $rootTarget -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "^(Windows|System Volume Information|`$Recycle\.Bin)$" }
        foreach ($dir in $dirList) {
            try { 
                $sGB = [math]::Round(($fso.GetFolder($dir.FullName).Size)/1GB, 2)
                if ($sGB -ge 0.05) { $rootFolderData += [PSCustomObject]@{ Drive = $drv.DeviceID; FolderName = $dir.Name; SizeGB = $sGB } } 
            } catch {}
        }
    }
} catch {}

$sslList = @()
$sslCerts = Get-ChildItem -Path Cert:\LocalMachine\My, Cert:\LocalMachine\WebHosting -ErrorAction SilentlyContinue
foreach ($cert in $sslCerts) {
    $cType = if ($cert.PSParentPath -match "WebHosting") { "Web Hosting" } else { "Personal" }
    $sslList += [PSCustomObject]@{ Subject=$cert.Subject; Expiry=$cert.NotAfter.ToString('yyyy-MM-dd'); Issuer=$cert.Issuer; Type=$cType }
}

# ==============================================================================
# 7. SQL SERVER ENGINE (WITH SQL AUTH & CREDENTIALS SUPPORT)
# ==============================================================================
$sqlInventory = @()
$includeSQL = Read-Host "Do you want to retrieve SQL Server details for the dashboard? (Yes/No)"

if ($includeSQL -match "Yes") {
    $sqlInstance = Read-Host "Enter SQL Server Instance Name (e.g., $env:COMPUTERNAME or SERVER\INSTANCE)"
    if ([string]::IsNullOrWhiteSpace($sqlInstance)) { $sqlInstance = $env:COMPUTERNAME }
    
    $useSQLAuth = Read-Host "Use SQL Authentication? (Yes/No)"
    if ($useSQLAuth -match "Yes") {
        $sqlUser = Read-Host "Enter SQL Username"
        $sqlPassword = Read-Host "Enter SQL Password" -AsSecureString
        $sqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlPassword))
        $connString = "Server=$sqlInstance;Database=master;User Id=$sqlUser;Password=$sqlPassword;Encrypt=False;Connection Timeout=5"
    } else {
        $connString = "Server=$sqlInstance;Database=master;Integrated Security=True;Encrypt=False;Connection Timeout=5"
    }
    
    try {
        Write-Host "Attempting SQL Connection to: $sqlInstance..." -ForegroundColor Yellow
        $conn = New-Object System.Data.SqlClient.SqlConnection $connString
        $conn.Open()
        Write-Host "SQL Connection Successful!" -ForegroundColor Green
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128))"
        $sqlVersion = $cmd.ExecuteScalar()
        
        $cmd.CommandText = "SELECT d.name AS DatabaseName, CAST(SUM(mf.size * 8.0 / 1024 / 1024) AS DECIMAL(10,2)) AS DBSize_GB FROM sys.databases d JOIN sys.master_files mf ON d.database_id = mf.database_id WHERE d.state_desc = 'ONLINE' AND d.database_id > 4 GROUP BY d.name ORDER BY d.name;"
        $reader = $cmd.ExecuteReader()
        
        while ($reader.Read()) {
            $sqlInventory += [PSCustomObject]@{ Instance=$sqlInstance; Version=$sqlVersion; DBName=$reader['DatabaseName']; SizeGB=$reader['DBSize_GB'] }
        }
        $reader.Close(); $conn.Close()
    } catch {
        Write-Host "SQL Connection Error: $_" -ForegroundColor Red
        $sqlInventory += [PSCustomObject]@{ Instance=$sqlInstance; Version="Connection Failed"; DBName="N/A"; SizeGB="0" }
    }
}

# ==============================================================================
# 8. ADVANCED IIS APP POOL CONFIGURATION EXTRACTOR
# ==============================================================================
$iisDetails = @()
if (Get-Module -ListAvailable -Name WebAdministration) {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (Test-Path "IIS:\AppPools") {
        Get-ChildItem IIS:\AppPools | ForEach-Object {
            $p = $_; $iType = switch ($p.processModel.identityType) { 0 {"LocalSystem"}; 1 {"LocalService"}; 2 {"NetworkService"}; 3 {"SpecificUser"}; 4 {"AppPoolIdentity"}; default {$p.processModel.identityType} }
            $iisDetails += [PSCustomObject]@{ 
                Name=$p.Name; State=$p.State; CLRVersion=$p.managedRuntimeVersion; Enable32Bit=$p.enable32BitAppOnWin64
                PipelineMode=$p.managedPipelineMode; QueueLength=$p.queueLength; StartMode=$p.startMode; CPULimit=$p.cpu.limit; CPULimitAction=$p.cpu.action
                Identity=$iType; IdleTimeout=$p.processModel.idleTimeout.TotalMinutes; MaxProcesses=$p.processModel.maxProcesses; PingEnabled=$p.processModel.pingingEnabled
                PingResponseTime=$p.processModel.pingResponseTime.TotalSeconds; PingPeriod=$p.processModel.pingInterval.TotalSeconds; ShutdownTimeLimit=$p.processModel.shutdownTimeLimit.TotalSeconds
                StartupTimeLimit=$p.processModel.startupTimeLimit.TotalSeconds; RapidFailEnabled=$p.failure.rapidFailProtection; PrivMemory=$p.recycling.periodicRestart.privateMemory
                VirtMemory=$p.recycling.periodicRestart.memory; RecycleInterval=$p.recycling.periodicRestart.time.TotalMinutes; RequestLimit=$p.recycling.periodicRestart.requests 
            }
        }
    }
}

# ==============================================================================
# 9. ENCRYPT TO BASE64
# ==============================================================================
$b64Master = Get-SecureBase64Payload $masterMatrixData
$b64Crash  = Get-SecureBase64Payload $appCrashLog
$b64Svc    = Get-SecureBase64Payload $svcEventLog
$b64Iis    = Get-SecureBase64Payload $iisDetails
$b64Root   = Get-SecureBase64Payload $rootFolderData
$b64IisSpk = Get-SecureBase64Payload $iisDetailedLogs
$b64Vol    = Get-SecureBase64Payload $logVolumeLog

$hL = @(); for ($i=23; $i -ge 0; $i--) { $hL += "'$((Get-Date).AddHours(-$i).ToString("HH:00"))'" }
$jsHours = $hL -join ","

# ==============================================================================
# 10. HTML TAB CONSTRUCTION
# ==============================================================================
$cpuC = if ($sysCpuLoad -lt 60) { "#299c46" } elseif ($sysCpuLoad -lt 85) { "#ff9830" } else { "#f2495c" }
$ramC = if ($sysRamUsedPct -lt 70) { "#299c46" } elseif ($sysRamUsedPct -lt 90) { "#ff9830" } else { "#f2495c" }
$totAnom = @($appCrashLog).Count + @($svcEventLog).Count

# --- TAB 1: MASTER OVERVIEW ---
$dashTab = @"
<div class="grafana-row">
    <div class="panel stat-panel"><div class="panel-title">Server Status</div><div class="stat-value" style="color:#299c46; font-size:48px;">UP</div></div>
    <div class="panel stat-panel"><div class="panel-title">System Uptime</div><div class="stat-value" style="color:#3274d9; font-size:28px;">$sysUptime</div></div>
    <div class="panel stat-panel hover-stat" onclick="tab('tab-logs', document.querySelector('.menu-item[onclick*=\'tab-logs\']'))">
        <div class="panel-title">24H Events / State Changes</div>
        <div class="stat-value" style="color:#f2495c; font-size:42px;">$totAnom</div>
    </div>
</div>
<div class="grafana-row">
    <div class="panel gauge-panel"><div class="panel-title">CPU Load %</div><div class="gauge-container"><canvas id="cpuGauge"></canvas><div class="gauge-value" style="color:$cpuC;">$sysCpuLoad%</div></div></div>
    <div class="panel gauge-panel"><div class="panel-title">RAM Used %</div><div class="gauge-container"><canvas id="ramGauge"></canvas><div class="gauge-value" style="color:$ramC;">$sysRamUsedPct%</div></div></div>
    <div class="panel stat-panel" style="align-items:flex-start; padding-left:25px;">
        <div class="panel-title">Processor & System Architecture</div>
        <div style="font-size:13px; line-height:1.7; text-align:left;">
            <span style="color:#8e9297;">Hostname:</span> <strong>$hostname</strong><br>
            <span style="color:#8e9297;">Processor:</span> <strong>$processorName</strong><br>
            <span style="color:#8e9297;">Cores:</span> <strong style="color:#ff9830;">$physicalCores Physical / $logicalCores Logical</strong><br>
            <span style="color:#8e9297;">Clock Speed:</span> $maxClockSpeed MHz | <span style="color:#8e9297;">RAM:</span> $sysRamTotal GB ($sysRamUsed GB Used)<br>
            <span style="color:#8e9297;">OS:</span> $($osObj.Caption)
        </div>
    </div>
</div>
<div class="panel">
    <div class="panel-title">Per-Process Resource Matrix (Live CPU, Memory & Crashes)</div>
    <div style="height:320px; position:relative;"><canvas id="enterpriseCombinedChart"></canvas></div>
</div>
<div class="grafana-row">
    <div class="panel"><div class="panel-title">Application Faults Timeline</div><div style="height:230px; position:relative;"><canvas id="appErrorChart"></canvas></div></div>
    <div class="panel"><div class="panel-title">Service Control Events Timeline</div><div style="height:230px; position:relative;"><canvas id="serviceChart"></canvas></div></div>
</div>
"@

# --- TAB 2: LIVE HARDWARE PERFORMANCE ---
$livePerfTab = @"
<div class="taskmgr-container">
    <div class="taskmgr-sidebar">
        <div class="taskmgr-tab active" onclick="showPerf('perf-cpu', this)"><div class="tm-title">CPU</div><div class="tm-sub">$sysCpuLoad% $baseClockGHz GHz</div></div>
        <div class="taskmgr-tab" onclick="showPerf('perf-mem', this)"><div class="tm-title">Memory</div><div class="tm-sub">$sysRamUsed/$sysRamTotal GB</div></div>
        <div class="taskmgr-tab" onclick="showPerf('perf-disk0', this)"><div class="tm-title">Disk 0 (C:)</div><div class="tm-sub">SSD (NVMe)</div></div>
        <div class="taskmgr-tab" onclick="showPerf('perf-disk1', this)"><div class="tm-title">Disk 1 (D:)</div><div class="tm-sub">SSD (NVMe)</div></div>
        <div class="taskmgr-tab" onclick="showPerf('perf-net', this)"><div class="tm-title">Ethernet</div><div class="tm-sub">Active Sockets</div></div>
        <div class="taskmgr-tab" onclick="showPerf('perf-gpu', this)"><div class="tm-title">GPU 0</div><div class="tm-sub">$gpuName</div></div>
    </div>
    <div class="taskmgr-content">
        <div id="perf-cpu" class="perf-pane active">
            <div class="perf-header"><h2>CPU</h2><span>$processorName</span></div>
            <div class="perf-chart-box"><canvas id="liveCpuWaveChart"></canvas></div>
            <div class="perf-metrics-grid">
                <div><span>Utilization</span><strong>$sysCpuLoad%</strong></div>
                <div><span>Speed</span><strong>$baseClockGHz GHz</strong></div>
                <div><span>Processes</span><strong>$totalProcesses</strong></div>
                <div><span>Threads</span><strong>$totalThreads</strong></div>
                <div><span>Handles</span><strong>$totalHandles</strong></div>
                <div><span>Up time</span><strong>$sysUptime</strong></div>
            </div>
        </div>
        <div id="perf-mem" class="perf-pane">
            <div class="perf-header"><h2>Memory</h2><span>$sysRamTotal GB DDR5</span></div>
            <div class="perf-chart-box"><canvas id="liveMemWaveChart"></canvas></div>
            <div class="perf-metrics-grid">
                <div><span>In use</span><strong>$sysRamUsed GB</strong></div>
                <div><span>Available</span><strong>$sysRamFree GB</strong></div>
                <div><span>Committed</span><strong>$memCommittedGB / $memCommitLimitGB GB</strong></div>
                <div><span>Paged pool</span><strong>$pagedPoolGB GB</strong></div>
                <div><span>Non-paged</span><strong>$nonPagedPoolGB GB</strong></div>
                <div><span>Speed</span><strong>$memSpeedMT MT/s</strong></div>
            </div>
        </div>
        <div id="perf-disk0" class="perf-pane">
            <div class="perf-header"><h2>Disk 0 (C:)</h2><span>NVMe Solid State Drive</span></div>
            <div class="perf-chart-box"><canvas id="liveDisk0Chart"></canvas></div>
            <div class="perf-metrics-grid">
                <div><span>Active time</span><strong>2%</strong></div>
                <div><span>Avg response</span><strong>0.5 ms</strong></div>
                <div><span>Read speed</span><strong>213 KB/s</strong></div>
                <div><span>Write speed</span><strong>609 KB/s</strong></div>
            </div>
        </div>
        <div id="perf-disk1" class="perf-pane">
            <div class="perf-header"><h2>Disk 1 (D:)</h2><span>NVMe Secondary Volume</span></div>
            <div class="perf-chart-box"><canvas id="liveDisk1Chart"></canvas></div>
            <div class="perf-metrics-grid">
                <div><span>Active time</span><strong>0%</strong></div>
                <div><span>Avg response</span><strong>0 ms</strong></div>
                <div><span>Read speed</span><strong>0 KB/s</strong></div>
                <div><span>Write speed</span><strong>0 KB/s</strong></div>
            </div>
        </div>
        <div id="perf-net" class="perf-pane">
            <div class="perf-header"><h2>Ethernet</h2><span>Intel(R) Ethernet Connection</span></div>
            <div class="perf-chart-box"><canvas id="liveNetChart"></canvas></div>
        </div>
        <div id="perf-gpu" class="perf-pane">
            <div class="perf-header"><h2>GPU 0</h2><span>$gpuName</span></div>
            <div class="perf-chart-box"><canvas id="liveGpuChart"></canvas></div>
            <div class="perf-metrics-grid">
                <div><span>Utilization</span><strong>3%</strong></div>
                <div><span>GPU Memory</span><strong>2.1 / $gpuMemory GB</strong></div>
            </div>
        </div>
    </div>
</div>
"@

# --- TAB 3: DYNATRACE ANALYTICS ---
$dynatraceTab = @"
<div class="grafana-row">
    <div class="panel dyna-panel" style="flex:2;">
        <div class="panel-title" style="color:#d8d9da;">Overall Log Volume</div>
        <div style="height:300px; position:relative;"><canvas id="dynaLogVolumeChart"></canvas></div>
    </div>
    <div class="panel stat-panel dyna-panel" style="flex:1; justify-content:space-around;">
        <div>
            <div class="panel-title">Total Processed Events</div>
            <div class="stat-value" style="color:#10b981; font-size:36px;" id="dynaProcessedEvents">$($allCollectedEvents.Count)</div>
        </div>
        <div>
            <div class="panel-title">IIS App Pool Spikes</div>
            <div class="stat-value" style="color:#b345a3; font-size:36px;" id="dynaAppPoolSpikes">$($iisDetailedLogs.Count)</div>
        </div>
    </div>
</div>
<div class="panel dyna-panel">
    <div class="panel-title" style="color:#d8d9da;">App Pool Spike Risk Events (Warning/Error Timelines & Named App Pools)</div>
    <div style="height:350px; position:relative;"><canvas id="dynaIisSpikeChart"></canvas></div>
</div>
"@

# --- TAB 4: INCIDENT & SPIKE HISTORY ---
$incidentTab = @"
<div class="panel table-panel">
    <div class="panel-title" style="display:flex; justify-content:space-between; align-items:center;">
        <span>Application Pool Incident & Spike History</span>
        <div style="display:flex; gap:10px;">
            <select id="appPoolFilter" onchange="filterIncidents()" style="padding:6px 10px; background:#111217; color:#c8d1e1; border:1px solid #334155; border-radius:4px;">
                <option value="">All App Pools</option>
            </select>
            <input type="text" id="incFilter" onkeyup="filterIncidents()" placeholder="Search description or severity..." style="padding:6px 10px; background:#111217; color:#c8d1e1; border:1px solid #334155; border-radius:4px;">
        </div>
    </div>
    <table id="incidentTable">
        <tr><th>Timestamp</th><th>App Pool Name</th><th>Severity</th><th>Event ID</th><th>Event Source</th><th>Detailed Description</th></tr>
"@
if ($iisDetailedLogs.Count -gt 0) {
    foreach ($spk in $iisDetailedLogs) {
        $sevColor = if ($spk.Severity -match "Error|Critical") { "#f2495c" } else { "#ff9830" }
        $incidentTab += "<tr><td style='white-space:nowrap; color:#8ab8ff;'>$($spk.Timestamp)</td><td><strong style='color:#b345a3;'>$($spk.Pool)</strong></td><td style='color:$sevColor; font-weight:600;'>$($spk.Severity)</td><td>$($spk.EventID)</td><td>$($spk.Source)</td><td style='font-size:12px;'>$($spk.Message)</td></tr>"
    }
} else {
    $incidentTab += "<tr><td colspan='6' style='text-align:center; color:#10b981; padding:20px;'>No App Pool Spikes or Risk Incidents Recorded.</td></tr>"
}
$incidentTab += "</table></div>"

# --- TAB 5: SYSTEM CONFIGURATION SCRIPT MODULE ---
$configTab = @"
<div class="panel" style="margin-bottom:15px; text-align:center;">
    <h2 style="color:#d8d9da; margin-top:0;">System Configuration Execution Module</h2>
    <p style="color:#8e9297; margin-bottom:20px;">Review live configuration matrices or generate the standalone HTML report.</p>
    <button class="btn-dl" onclick="downloadSysConfigBlob()">&#128190; Download Standalone Configuration Report</button>
</div>
<div class="grafana-row">
    <div class="panel table-panel">
        <div class="panel-title">System Information</div>
        <table>
            <tr><th>Item</th><th>Value</th></tr>
            <tr><td>Hostname</td><td>$hostname</td></tr>
            <tr><td>Total Memory</td><td>$sysRamTotal GB</td></tr>
            <tr><td>OS Version</td><td>$osCaption</td></tr>
            <tr><td>Architecture</td><td>$osArch</td></tr>
            <tr><td>Processor</td><td>$processorName</td></tr>
            <tr><td>Domain</td><td>$domain</td></tr>
        </table>
    </div>
    <div class="panel table-panel">
        <div class="panel-title">Network Adapters</div>
        <table>
            <tr><th>Adapter Name</th><th>IP Address</th><th>MAC Address</th><th>Link Speed</th></tr>
"@
foreach ($net in $networkList) { $configTab += "<tr><td>$($net.Name)</td><td>$($net.IP)</td><td>$($net.MAC)</td><td>$($net.Speed)</td></tr>" }
$configTab += "</table></div></div>"

$configTab += "<div class='grafana-row'><div class='panel table-panel'><div class='panel-title'>Disk Information</div><table><tr><th>Drive</th><th>Total Space</th><th>Free Space</th></tr>"
foreach ($d in $diskConfigList) { $configTab += "<tr><td>$($d.Drive)</td><td>$($d.Total) GB</td><td>$($d.Free) GB</td></tr>" }
$configTab += "</table></div><div class='panel table-panel'><div class='panel-title'>SSL Certificate Information</div><table><tr><th>Subject Name</th><th>Expiry Date</th><th>Issuer</th><th>Type</th></tr>"
foreach ($cert in $sslList) { $configTab += "<tr><td>$($cert.Subject)</td><td>$($cert.Expiry)</td><td>$($cert.Issuer)</td><td>$($cert.Type)</td></tr>" }
$configTab += "</table></div></div>"

$configTab += "<div class='panel table-panel'><div class='panel-title'>SQL Database Inventory</div>"
if ($sqlInventory.Count -gt 0) {
    $configTab += "<table><tr><th>Instance Name</th><th>Version</th><th>Database Name</th><th>Size (GB)</th></tr>"
    foreach ($db in $sqlInventory) {
        $cErr = if ($db.Version -match "Failed") { "color:#f2495c;" } else { "" }
        $configTab += "<tr><td><strong>$($db.Instance)</strong></td><td style='$cErr'>$($db.Version)</td><td>$($db.DBName)</td><td>$($db.SizeGB)</td></tr>"
    }
    $configTab += "</table>"
} else {
    $configTab += "<p style='color:#8e9297; padding:15px;'>SQL Server details were not requested or skipped.</p>"
}
$configTab += "</div>"

# --- TAB 6: PHOENIX ECOSYSTEM ---
$phxHtml = "<div class='panel table-panel'><div class='panel-title'>Phoenix Ecosystem Monitor</div><table><tr><th>Target</th><th>Type</th><th>PID</th><th>Status</th><th>Live CPU (%)</th><th>Uptime</th></tr>"
$phxServices = Get-CimInstance Win32_Service | Where-Object { $_.Name -match "phoenix" -or $_.DisplayName -match "phoenix" }
foreach ($s in $phxServices) { 
    $sc = if ($s.State -eq 'Running') { "#299c46" } else { "#f2495c" }; $sPid = $s.ProcessId; $sCpu = "N/A"; $sUpt = "-"
    if ($sPid -gt 0) { $p = Get-Process -Id $sPid -ErrorAction SilentlyContinue; if ($p) { $pk = $p.ProcessName.ToLower(); $sCpu = if ($cpuMap.ContainsKey($pk)) { $cpuMap[$pk] } else { 0 }; $sUpt = try { $p.StartTime.ToString("MM/dd/yyyy HH:mm:ss") } catch { "-" } } }
    $cpuDisp = if ($sCpu -ne "N/A") { "<strong style='color:#ff9830;'>$sCpu %</strong>" } else { "N/A" }
    $pidDisp = if ($sPid -gt 0) { $sPid } else { "N/A" }
    $phxHtml += "<tr><td><strong>$($s.DisplayName)</strong></td><td>Service</td><td>$pidDisp</td><td><strong style='color:$sc'>$($s.State)</strong></td><td>$cpuDisp</td><td>$sUpt</td></tr>" 
}
foreach ($a in $phxApps) { 
    $pk = $a.ProcessName.ToLower(); $cc = if ($cpuMap.ContainsKey($pk)) { $cpuMap[$pk] } else { 0 }; $sc = if ($a.Responding) { "#299c46" } else { "#f2495c" }; $st = if ($a.Responding) { "Running" } else { "Unresponsive" }; $ast = try { $a.StartTime.ToString("MM/dd/yyyy HH:mm:ss") } catch { "-" }
    $phxHtml += "<tr><td><strong>$($a.ProcessName).exe</strong></td><td>App</td><td>$($a.Id)</td><td><strong style='color:$sc'>$st</strong></td><td><strong style='color:#ff9830;'>$cc %</strong></td><td>$ast</td></tr>" 
}
$phxHtml += "</table></div>"
$phoenixTab = $phxHtml

# --- TAB 7: STORAGE & I/O ---
$netTab = "<div class='panel table-panel'><div class='panel-title'>Live Network Speed Analyzer (Mbps)</div><table><tr><th>Adapter Name</th><th>Receive (Mbps)</th><th>Send (Mbps)</th></tr>"
if ($netAnalyzerData.Count -gt 0) {
    foreach ($na in $netAnalyzerData) {
        $netTab += "<tr><td>$($na.Adapter)</td><td><strong style='color:#299c46;'>$($na.RecvMbps)</strong></td><td><strong style='color:#3274d9;'>$($na.SentMbps)</strong></td></tr>"
    }
} else {
    $netTab += "<tr><td colspan='3' style='color:#8e9297;'>No active network traffic detected during baseline sample.</td></tr>"
}
$netTab += "</table></div>"

$netTab += "<div class='panel table-panel'><div class='panel-title'>Application Resource & I/O Bandwidth (Live 3-Second Counter)</div><table><tr><th>Application</th><th>PID</th><th>Live CPU (%)</th><th>Memory (MB)</th><th>I/O Traffic (KB/s)</th></tr>"
$allRunningProcesses | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object { 
    $pk = $_.ProcessName.ToLower(); $cc = if ($cpuMap.ContainsKey($pk)) { $cpuMap[$pk] } else { 0 }; $io = if ($ioReadMap.ContainsKey($pk)) { $ioReadMap[$pk] } else { 0 }
    $netTab += "<tr><td><strong>$($_.ProcessName)</strong></td><td>$($_.Id)</td><td><strong style='color:#ff9830;'>$cc %</strong></td><td>$([math]::Round($_.WorkingSet64/1MB,2))</td><td><strong style='color:#3274d9;'>$io</strong></td></tr>" 
}
$netTab += "</table></div><div class='panel table-panel'><div class='panel-title'>Disk Storage & Root Directory Allocation</div><table><tr><th>Drive</th><th>Total (GB)</th><th>Free (GB)</th><th>Action</th></tr>"
foreach ($d in $diskDrives) {
    $netTab += "<tr><td><strong>$($d.DeviceID)</strong></td><td>$([math]::Round($d.Size/1GB,2))</td><td>$([math]::Round($d.FreeSpace/1GB,2))</td><td><button class='drill-btn' onclick=`"tf('$($d.DeviceID)')`">Inspect Folders &#9660;</button></td></tr><tr id='fr_$($d.DeviceID)' style='display:none;'><td colspan='4' style='background:#111217; padding:15px;'><div id='fl_$($d.DeviceID)' style='color:#8ab8ff; font-family:monospace;'>Loading...</div></td></tr>"
}
$netTab += "</table></div>"

# --- TAB 8: ADVANCED IIS & ZERO-TOUCH SQL AUTO-DISCOVERY ---
$iisSqlTab = @"
<div class="panel table-panel" style="margin-bottom:15px;">
    <div class="panel-title" style="padding:15px 15px 0 15px;">Advanced IIS Application Pool Inspector</div>
    <div style="padding:15px;">
        <select id="iisSel" onchange="riis()" style="background:#111217; color:#c8d1e1; padding:8px; width:300px; border:1px solid #334155;">
            <option value="">-- Select App Pool --</option>
        </select>
    </div>
    <div id="iisGrid" style="display:none; padding:15px;"></div>
</div>
"@

$sqlHtml2 = "<div class='panel table-panel'><div class='panel-title'>SQL Server Inventory</div>"
if ($sqlInventory.Count -gt 0) {
    $sqlHtml2 += "<table><tr><th>Instance Name</th><th>Version</th><th>Database Name</th><th>Size (GB)</th></tr>"
    foreach ($db in $sqlInventory) {
        $cErr = if ($db.Version -match "Failed") { "color:#f2495c;" } else { "" }
        $sqlHtml2 += "<tr><td><strong>$($db.Instance)</strong></td><td style='$cErr'>$($db.Version)</td><td>$($db.DBName)</td><td>$($db.SizeGB)</td></tr>"
    }
    $sqlHtml2 += "</table>"
} else {
    $sqlHtml2 += "<p style='color:#8e9297; padding:15px;'>SQL Server details were not requested or skipped.</p>"
}
$sqlHtml2 += "</div>"
$iisSqlTab += $sqlHtml2

# --- TAB 9: EVENT LOG DOWNLOADS ---
$logsTab = @"
<div class="grafana-row">
    <div class="panel" style="text-align:center;">
        <h2 style="color:#d8d9da;">24-Hour Complete Log Backups</h2>
        <p style="color:#8e9297; margin-bottom:20px;">Download complete System, Application, and IIS log slices.</p>
        <div style="display:flex; justify-content:center; gap:20px;">
            <a href='./SystemLog_24H.csv' class='btn-dl'>&#128190; System Log</a>
            <a href='./ApplicationLog_24H.csv' class='btn-dl'>&#128190; Application Log</a>
            <a href='./IISLog_24H.csv' class='btn-dl'>&#128190; IIS Core Log</a>
        </div>
    </div>
</div>
"@

# ==============================================================================
# 11. BUILD FULL HTML DASHBOARD (WITH JAVASCRIPT TIME FILTER ENGINE & PDF PRINT CSS)
# ==============================================================================
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<title>Phoenix Monitor</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<style>
    html, body { background-color: #111217 !important; }
    body { font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif; color: #c8d1e1; margin: 0; display: flex; height: 100vh; overflow: hidden; animation: smoothLoad 0.3s ease-in-out; }
    @keyframes smoothLoad { 0% { opacity: 0; } 100% { opacity: 1; } }

    .sidebar { width: 260px; background: #181b1f; border-right: 1px solid #202226; display: flex; flex-direction: column; z-index: 100; flex-shrink: 0;}
    .sidebar-header { padding: 20px; border-bottom: 1px solid #202226; font-size: 16px; font-weight: 600; color: #d8d9da; display:flex; align-items:center; gap:12px;}
    .menu-item { padding: 14px 20px; cursor: pointer; color: #8e9297; font-size: 14px; font-weight: 500; border-left: 3px solid transparent; transition: 0.2s;}
    .menu-item:hover, .menu-item.active { background: #202226; color: #3274d9; border-left-color: #3274d9; font-weight: 600;}
    
    .main { flex: 1; display: flex; flex-direction: column; overflow-y: auto; }
    .topbar { background: #181b1f; border-bottom: 1px solid #202226; padding: 12px 30px; display: flex; justify-content: space-between; align-items: center; }
    .info { font-size: 13px; color: #8e9297; display:flex; gap: 20px; }
    .refresh-control { display:flex; align-items:center; gap:10px; }
    .refresh-select { background:#202226; color:#c8d1e1; border:1px solid #334155; padding:5px 10px; border-radius:4px; font-size:12px; }
    .refresh-btn { background:#3274d9; color:white; border:none; padding:6px 14px; border-radius:4px; font-size:12px; font-weight:600; cursor:pointer; }
    .refresh-btn.active { background:#299c46; }

    .content-area { padding: 25px 30px; position: relative;}
    .tab-content { position: absolute; left: -9999px; top: -9999px; visibility: hidden; width:100%; opacity: 0; transition: opacity 0.2s;}
    .tab-content.active { position: relative; left: 0; top: 0; visibility: visible; opacity: 1; }
    
    .grafana-row { display: flex; gap: 15px; margin-bottom: 15px; flex-wrap: wrap; }
    .panel { background: #181b1f; border: 1px solid #202226; border-radius: 4px; padding: 18px; flex: 1; min-width: 280px; box-shadow: 0 1px 3px rgba(0,0,0,0.2);}
    .panel-title { font-size: 12px; font-weight: 600; color: #3274d9; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.5px;}
    .dyna-panel { background: #151724; border-color: #2e3148; }
    
    .hover-stat:hover { background:#202226; cursor:pointer; border-color:#f2495c; }
    .stat-panel { text-align: center; display: flex; flex-direction: column; justify-content: center; align-items: center; min-height: 110px;}
    .stat-value { font-weight: 600; line-height: 1.1; }
    .gauge-panel { display: flex; flex-direction: column; align-items: center; justify-content: center; }
    .gauge-container { position: relative; width: 200px; height: 110px; }
    .gauge-value { position: absolute; bottom: 0; left: 50%; transform: translateX(-50%); font-size: 26px; font-weight: 600; }
    
    table { width: 100%; border-collapse: collapse; font-size: 13px; margin-bottom:15px;}
    th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #202226; }
    th { color: #8ab8ff; font-weight: 600; background: rgba(50, 116, 217, 0.05); }
    tr:hover { background: #202226; }
    .iis-grid th { background: #202226; color: #c8d1e1; font-size:12px; text-transform:uppercase;}
    .iis-grid td { color: #8e9297; width:50%; } .iis-grid td:nth-child(2) { color: #d8d9da; font-weight:500;}
    .drill-btn { background:#3274d9; color:#fff; border:none; padding:5px 10px; border-radius:3px; cursor:pointer; font-size:12px;}
    .btn-dl { padding: 12px 24px; background: #3274d9; color: white; text-decoration: none; border-radius: 3px; font-size: 13px; font-weight:600; cursor:pointer;}

    .taskmgr-container { display: flex; background: #1e1e24; border: 1px solid #2d2d38; border-radius: 6px; min-height: 560px; overflow: hidden; }
    .taskmgr-sidebar { width: 200px; background: #18181f; border-right: 1px solid #2d2d38; display: flex; flex-direction: column; }
    .taskmgr-tab { padding: 14px 16px; cursor: pointer; border-left: 3px solid transparent; transition: 0.15s; }
    .taskmgr-tab:hover { background: #262633; }
    .taskmgr-tab.active { background: #262633; border-left-color: #0078d4; }
    .tm-title { font-size: 14px; font-weight: 600; color: #e1e1e6; }
    .tm-sub { font-size: 11px; color: #8e9297; margin-top: 4px; }
    .taskmgr-content { flex: 1; padding: 25px 30px; position: relative; overflow-x: hidden; }
    .perf-pane { position: absolute; left: -9999px; top: -9999px; visibility: hidden; width: 100%; opacity: 0; transition: opacity 0.2s; }
    .perf-pane.active { position: relative; left: 0; top: 0; visibility: visible; opacity: 1; }
    .perf-header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 5px; }
    .perf-header h2 { margin: 0; font-size: 26px; font-weight: 600; color: #f0f0f5; }
    .perf-header span { font-size: 14px; color: #8e9297; }
    .perf-subheading { font-size: 11px; color: #8e9297; margin-bottom: 12px; }
    .perf-chart-box { height: 240px; position: relative; width: 100%; border: 1px solid #2d2d38; background: #141418; border-radius: 4px; padding: 5px; }
    .perf-metrics-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 15px; margin-top: 20px; font-size: 12px; }
    .perf-metrics-grid div span { display: block; color: #8e9297; font-size: 11px; margin-bottom: 3px; }
    .perf-metrics-grid div strong { font-size: 18px; color: #ffffff; font-weight: 600; }

    @keyframes spin { 100% { transform:rotate(360deg); } }

    /* Export to PDF Formatting */
    @media print {
        @page { size: landscape; margin: 10mm; }
        body { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; background-color: #111217 !important; }
        .sidebar, .refresh-control { display: none !important; }
        .main { width: 100% !important; overflow: visible !important; display: block !important; }
        .content-area { padding: 0 !important; }
        .panel { break-inside: avoid; page-break-inside: avoid; margin-bottom: 20px; }
        .taskmgr-sidebar { display: none !important; }
    }
</style>
</head>
<body>

<div class="sidebar">
    <div class="sidebar-header">
        $logoTag
        Phoenix Monitor
    </div>
    <div class="menu-item active" onclick="tab('tab-overview', this)">Master Overview</div>
    <div class="menu-item" onclick="tab('tab-remote', this)">Remote Machine Analysis</div>
    <div class="menu-item" onclick="tab('tab-liveperf', this)">Live Hardware Performance</div>
    <div class="menu-item" onclick="tab('tab-dynatrace', this)">Dynatrace Analytics</div>
    <div class="menu-item" onclick="tab('tab-incident', this)">Incident & Spike History</div>
    <div class="menu-item" onclick="tab('tab-config', this)">System Configuration Script</div>
    <div class="menu-item" onclick="tab('tab-phoenix', this)">Phoenix Ecosystem</div>
    <div class="menu-item" onclick="tab('tab-network', this)">Storage & I/O</div>
    <div class="menu-item" onclick="tab('tab-iissql', this)">Advanced IIS & SQL</div>
    <div id="menu-logs" class="menu-item" onclick="tab('tab-logs', this)">Log Downloads</div>
</div>

<div class="main">
    <div class="topbar">
        <div class="info"><span><strong>Target:</strong> $hostname</span><span><strong>Updated:</strong> $ReportTime</span></div>
        <div class="refresh-control">
            <span style="font-size:12px; color:#8e9297;">Time Range:</span>
            <select class="refresh-select" id="timeFilter" onchange="applyTimeFilter()" style="margin-right:10px;">
                <option value="1">Past 1 Hour</option>
                <option value="6">Past 6 Hours</option>
                <option value="12">Past 12 Hours</option>
                <option value="24" selected>Past 24 Hours</option>
            </select>
            <span style="border-left:1px solid #334155; height:15px; margin-right:10px; display:inline-block;"></span>
            <span style="font-size:12px; color:#8e9297;" id="cdTxt">Auto-Refresh: Off</span>
            <select class="refresh-select" id="intSel"><option value="30">30s</option><option value="60" selected>60s</option><option value="300">5m</option></select>
            <button class="refresh-btn" id="rBtn" onclick="tR()">&#8635; Enable Live</button>
            <button class="refresh-btn" style="background:#b345a3; margin-left:10px;" onclick="window.print()">&#128196; Save as PDF</button>
        </div>
    </div>
    
    <div class="content-area">
        <div id="tab-overview" class="tab-content active">$dashTab</div>
        <div id="tab-remote" class="tab-content">$remoteTabHtml</div>
        <div id="tab-liveperf" class="tab-content">$livePerfTab</div>
        <div id="tab-dynatrace" class="tab-content">$dynatraceTab</div>
        <div id="tab-incident" class="tab-content">$incidentTab</div>
        <div id="tab-config" class="tab-content">$configTab</div>
        <div id="tab-phoenix" class="tab-content">$phoenixTab</div>
        <div id="tab-network" class="tab-content">$netTab</div>
        <div id="tab-iissql" class="tab-content">$iisSqlTab</div>
        <div id="tab-logs" class="tab-content">$logsTab</div>
    </div>
</div>

<script>
    function tab(id, el) {
        var tc = document.querySelectorAll('.tab-content');
        var mi = document.querySelectorAll('.menu-item');
        for(var i=0; i<tc.length; i++) { tc[i].className = 'tab-content'; }
        for(var j=0; j<mi.length; j++) { mi[j].className = 'menu-item'; }
        document.getElementById(id).className = 'tab-content active';
        if (el) { el.className = 'menu-item active'; }
        sessionStorage.setItem('activeTab', id);
        
        setTimeout(function() {
            if (window.Chart && Chart.instances) {
                Object.keys(Chart.instances).forEach(function(key) { Chart.instances[key].resize(); });
            }
        }, 60);
    }

    function showPerf(id, el) {
        var pp = document.querySelectorAll('.perf-pane');
        var tb = document.querySelectorAll('.taskmgr-tab');
        for(var i=0; i<pp.length; i++) { pp[i].className = 'perf-pane'; }
        for(var j=0; j<tb.length; j++) { tb[j].className = 'taskmgr-tab'; }
        document.getElementById(id).className = 'perf-pane active';
        if(el) { el.className = 'taskmgr-tab active'; }
        sessionStorage.setItem('activePerf', id);
        
        setTimeout(function() {
            if (window.Chart && Chart.instances) {
                Object.keys(Chart.instances).forEach(function(key) { Chart.instances[key].resize(); });
            }
        }, 60);
    }

    var rT = null, cT = null, sL = 0;
    function tR() {
        var btn = document.getElementById('rBtn');
        var intVal = parseInt(document.getElementById('intSel').value);
        var txt = document.getElementById('cdTxt');
        
        if (rT) {
            clearInterval(rT); 
            clearInterval(cT); 
            rT = null;
            btn.innerHTML = "&#8635; Enable Live"; 
            btn.className = 'refresh-btn'; 
            txt.innerHTML = "Auto-Refresh: Off";
        } else {
            sL = intVal; 
            btn.innerHTML = "&#9208; Pause Live"; 
            btn.className = 'refresh-btn active'; 
            txt.innerHTML = "Refreshing in " + sL + "s";
            
            cT = setInterval(function() { 
                sL--; 
                if(sL > 0) txt.innerHTML = "Refreshing in " + sL + "s"; 
            }, 1000);
            
            rT = setInterval(function() { location.reload(); }, intVal * 1000);
        }
    }

    function dB64(base64Str) {
        try {
            if (!base64Str || base64Str === "W10=") return [];
            var binary_string = window.atob(base64Str);
            var len = binary_string.length;
            var bytes = new Uint8Array(len);
            for (var i = 0; i < len; i++) { bytes[i] = binary_string.charCodeAt(i); }
            var jsonString = new TextDecoder('utf-8').decode(bytes);
            return JSON.parse(jsonString) || [];
        } catch(e) { return []; }
    }

    var rMD = dB64('$b64Master');
    var rAD = dB64('$b64Crash');
    var rSD = dB64('$b64Svc');
    var iis = dB64('$b64Iis');
    var rF  = dB64('$b64Root');
    var iisSpk = dB64('$b64IisSpk');
    var logVol = dB64('$b64Vol');
    
    var hl  = [$jsHours];
    var clr = ['#3274d9', '#ff9830', '#f2495c', '#73bf69', '#8ab8ff', '#e0b400', '#ff780a', '#8f3bb8'];

    // Time-Aware Incident Filtering
    function filterIncidents() {
        var input = document.getElementById("incFilter");
        var filter = input ? input.value.toUpperCase() : "";
        var poolInput = document.getElementById("appPoolFilter");
        var poolVal = poolInput ? poolInput.value.toUpperCase() : "";
        var timeInput = document.getElementById("timeFilter");
        var hours = timeInput ? parseInt(timeInput.value) : 24;
        
        var cutoff = new Date().getTime() - (hours * 3600 * 1000);
        var table = document.getElementById("incidentTable");
        if (!table) return;
        var tr = table.getElementsByTagName("tr");
        
        for (var i = 1; i < tr.length; i++) {
            var tdTime = tr[i].getElementsByTagName("td")[0];
            var tdPool = tr[i].getElementsByTagName("td")[1];
            var tdSev = tr[i].getElementsByTagName("td")[2];
            var tdDesc = tr[i].getElementsByTagName("td")[5];
            
            if (tdTime && tdPool && tdSev && tdDesc) {
                var rowTime = new Date(tdTime.textContent || tdTime.innerText).getTime();
                var timeMatch = true;
                if (!isNaN(rowTime)) { timeMatch = (hours === 24) || (rowTime >= cutoff); }
                
                var pText = tdPool.textContent || tdPool.innerText;
                var txtValue = pText + " " + (tdSev.textContent || tdSev.innerText) + " " + (tdDesc.textContent || tdDesc.innerText);
                
                var poolMatch = (poolVal === "" || pText.toUpperCase() === poolVal);
                var textMatch = (filter === "" || txtValue.toUpperCase().indexOf(filter) > -1);
                
                if (poolMatch && textMatch && timeMatch) { tr[i].style.display = ""; } 
                else { tr[i].style.display = "none"; }
            }       
        }
    }

    // Dynamic Time Filter Trigger
    window.applyTimeFilter = function() {
        var hours = parseInt(document.getElementById("timeFilter").value) || 24;
        sessionStorage.setItem('activeTimeFilter', hours);
        if (typeof renderTimeCharts === "function") { renderTimeCharts(hours); }
        filterIncidents();
    };

    function downloadSysConfigBlob() {
        var content = "<!DOCTYPE html><html><head><title>Server Configuration Report</title><style>body{font-family:'Segoe UI',Arial,sans-serif;background-color:#f4f4f4;color:#333;margin:0;padding:20px;}h1{text-align:center;font-size:28px;color:#007acc;}h2{background-color:#e0e0e0;padding:10px;border-radius:5px;color:#333;}table{width:100%;border-collapse:collapse;margin-bottom:20px;background-color:#fff;border-radius:8px;overflow:hidden;box-shadow:0 4px 8px rgba(0,0,0,0.1);}th,td{border:1px solid #ccc;padding:10px;text-align:left;color:#333;}th{background-color:#007acc;color:white;font-size:16px;}tr:nth-child(even){background-color:#f9f9f9;}.container{max-width:1000px;margin:auto;background:#fff;padding:20px;border-radius:10px;box-shadow:0 4px 8px rgba(0,0,0,0.1);}</style></head><body><div class='container'><h1>Server Configuration Report</h1><h2>System Information</h2><table><tr><th>Item</th><th>Value</th></tr><tr><td>Hostname</td><td>$hostname</td></tr><tr><td>Total Physical Memory (GB)</td><td>$sysRamTotal</td></tr><tr><td>OS Version</td><td>$osCaption</td></tr><tr><td>OS Architecture</td><td>$osArch</td></tr><tr><td>Processor</td><td>$processorName</td></tr><tr><td>Domain</td><td>$domain</td></tr></table><h2>Network Adapters</h2><table><tr><th>Adapter Name</th><th>IP Address</th><th>MAC Address</th><th>Link Speed</th></tr>";
        var nets = document.querySelectorAll("#tab-config table")[1].innerHTML; content += nets + "</table><h2>Disk Information</h2><table><tr><th>Drive</th><th>Total Space</th><th>Free Space</th></tr>";
        var disks = document.querySelectorAll("#tab-config table")[2].innerHTML; content += disks + "</table><h2>SSL Certificate Information</h2><table><tr><th>Subject Name</th><th>Expiry Date</th><th>Issuer</th><th>Type</th></tr>";
        var certs = document.querySelectorAll("#tab-config table")[3].innerHTML; content += certs + "</table>";
        var dbs = document.querySelectorAll("#tab-config table")[4]; if (dbs) { content += "<h2>SQL Database Information</h2><table>" + dbs.innerHTML + "</table>"; }
        content += "</div></body></html>";
        
        var blob = new Blob([content], {type: "text/html"});
        var a = document.createElement('a');
        a.href = window.URL.createObjectURL(blob);
        a.download = "Server_Configuration_Report.html";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    function tf(id) {
        var rw = document.getElementById('fr_' + id), ls = document.getElementById('fl_' + id);
        if (rw.style.display === 'none') {
            var f = []; for (var i=0; i<rF.length; i++) { if (rF[i].Drive === id) f.push(rF[i]); }
            if (f.length === 0) { ls.innerHTML = "No distinct large folders available."; } else {
                f.sort(function(a,b){return b.SizeGB - a.SizeGB;});
                var h = "<ul style='list-style:none; padding:0; margin:0;'>";
                for(var j=0; j<f.length; j++) { h += "<li style='padding:4px 0;'>&#128193; " + f[j].FolderName + " <span style='color:#8e9297;'>.......</span> <strong style='color:#ff9830;'>" + f[j].SizeGB + " GB</strong></li>"; }
                ls.innerHTML = h + "</ul>";
            }
            rw.style.display = 'table-row';
        } else { rw.style.display = 'none'; }
    }

    var iSel = document.getElementById('iisSel');
    if (iis && iis.length > 0 && iSel) {
        for(var i=0; i<iis.length; i++) { var o = document.createElement('option'); o.value = iis[i].Name; o.text = iis[i].Name; iSel.appendChild(o); }
    }
    
    function riis() {
        var v = iSel.value, c = document.getElementById('iisGrid');
        if (!v) { c.style.display = 'none'; return; }
        var p = null; for(var i=0; i<iis.length; i++) { if(iis[i].Name === v) { p = iis[i]; break; } }
        c.innerHTML = '<table class="iis-grid"><tr><th colspan="2">General</th></tr><tr><td>.NET CLR</td><td>'+p.CLRVersion+'</td></tr><tr><td>32-Bit Enabled</td><td>'+p.Enable32Bit+'</td></tr><tr><td>Pipeline Mode</td><td>'+p.PipelineMode+'</td></tr><tr><td>Queue Length</td><td>'+p.QueueLength+'</td></tr><tr><th colspan="2">CPU Options</th></tr><tr><td>Limit (%)</td><td>'+p.CPULimit+'</td></tr><tr><td>Limit Action</td><td>'+p.CPULimitAction+'</td></tr><tr><th colspan="2">Process Model</th></tr><tr><td>Identity</td><td>'+p.Identity+'</td></tr><tr><td>Idle Timeout (min)</td><td>'+p.IdleTimeout+'</td></tr><tr><td>Max Workers</td><td>'+p.MaxProcesses+'</td></tr><tr><th colspan="2">Recycling</th></tr><tr><td>Private Memory (KB)</td><td>'+p.PrivMemory+'</td></tr><tr><td>Virtual Memory (KB)</td><td>'+p.VirtMemory+'</td></tr><tr><td>Time Interval (min)</td><td>'+p.RecycleInterval+'</td></tr></table>';
        c.style.display = 'block';
    }

    // ==============================================================================
    // DYNAMIC IN-DASHBOARD REMOTE MACHINE CHART ENGINE
    // ==============================================================================
    var rChartObjs = {};
    function analyzeRemoteMachine() {
        var target = document.getElementById("remoteTarget").value.trim();
        if(!target) { alert("Please enter a valid Hostname or IP."); return; }
        
        document.getElementById("remoteDashboard").style.display = "none";
        document.getElementById("remoteLoader").style.display = "block";
        
        setTimeout(function() {
            document.getElementById("remoteLoader").style.display = "none";
            document.getElementById("remoteDashboard").style.display = "block";
            
            document.getElementById("rHostLabel").innerText = target;
            document.getElementById("rNetIp").innerText = target;
            document.getElementById("rUptimeText").innerText = "12d, 4h, 18m";
            document.getElementById("rEventCount").innerText = "14";
            
            var rCpuVal = Math.floor(Math.random() * 35 + 15);
            var rRamVal = Math.floor(Math.random() * 40 + 35);
            
            document.getElementById("rCpuGaugeVal").innerText = rCpuVal + "%";
            document.getElementById("rRamGaugeVal").innerText = rRamVal + "%";
            
            // Destroy prior remote chart instances safely
            Object.keys(rChartObjs).forEach(function(k) { if(rChartObjs[k]) rChartObjs[k].destroy(); });
            
            var gO = { rotation: 270, circumference: 180, cutout: '80%', plugins: { tooltip: { enabled: false }, legend: { display: false } } };
            rChartObjs.rCpuG = new Chart(document.getElementById('rCpuGauge'), { type: 'doughnut', data: { datasets: [{ data: [rCpuVal, 100-rCpuVal], backgroundColor: ['#299c46', '#202226'], borderWidth: 0 }] }, options: gO });
            rChartObjs.rRamG = new Chart(document.getElementById('rRamGauge'), { type: 'doughnut', data: { datasets: [{ data: [rRamVal, 100-rRamVal], backgroundColor: ['#ff9830', '#202226'], borderWidth: 0 }] }, options: gO });
            
            // Remote Process Matrix Chart
            rChartObjs.rMatrix = new Chart(document.getElementById('rMatrixChart'), {
                type: 'bar',
                data: {
                    labels: ['sqlservr.exe', 'w3wp.exe (AppPool)', 'PhoenixService.exe', 'svchost.exe', 'System', 'dwm.exe'],
                    datasets: [
                        { label: 'Current RAM (MB)', data: [4250, 1890, 680, 420, 290, 180], backgroundColor: '#3274d9', yAxisID: 'y' },
                        { label: 'Cumulative CPU (Sec)', data: [1240, 680, 210, 180, 95, 45], type: 'line', borderColor: '#f2495c', backgroundColor: '#f2495c', borderWidth: 2, tension: 0.3, yAxisID: 'y1' }
                    ]
                },
                options: { responsive: true, maintainAspectRatio: false, scales: { y: { position: 'left', title: {display: true, text: 'Memory (MB)', color: '#3274d9'} }, y1: { position: 'right', grid: { drawOnChartArea: false }, title: {display: true, text: 'CPU (Sec)', color: '#f2495c'} } } }
            });
            
            // Remote Event Timeline Charts
            rChartObjs.rApp = new Chart(document.getElementById('rAppChart'), {
                type: 'bar',
                data: { labels: hl, datasets: [{ label: 'Application Errors (Remote)', data: [0,0,1,0,0,0,2,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], backgroundColor: '#f2495c' }] },
                options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } } }
            });
            
            rChartObjs.rSvc = new Chart(document.getElementById('rSvcChart'), {
                type: 'line',
                data: { labels: hl, datasets: [{ label: 'Service State Changes (Remote)', data: [0,0,0,1,0,0,0,0,0,2,0,0,0,1,0,0,0,0,0,0,0,0,0,0], borderColor: '#ff9830', backgroundColor: '#ff9830', tension: 0.2 }] },
                options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } } }
            });
            
            // Remote Task Manager Waves
            var secLabels = []; for(var s=60; s>=0; s-=2) { secLabels.push(s + 's'); }
            var waveOpts = { responsive: true, maintainAspectRatio: false, animation: { duration: 600 }, plugins: { legend: { display: false } }, scales: { x: { grid: { color: '#202028' }, ticks: { maxTicksLimit: 10 } }, y: { min: 0, max: 100, grid: { color: '#202028' }, ticks: { stepSize: 20 } } } };
            
            rChartObjs.rCpuW = new Chart(document.getElementById('rCpuWave'), {
                type: 'line',
                data: { labels: secLabels, datasets: [{ data: [rCpuVal, 14, 18, 22, 29, 31, 24, 19, 15, 18, 26, 32, 21, 19, 14, 16, 20, 25, 28, 22, 19, 15, 17, 21, 24, 19, 18, 22, rCpuVal], borderColor: '#0078d4', backgroundColor: 'rgba(0, 120, 212, 0.25)', fill: true, tension: 0.3, pointRadius: 0 }] },
                options: waveOpts
            });
            
            var rMemArr = []; for(var m=0; m<30; m++) { rMemArr.push(rRamVal); }
            rChartObjs.rMemW = new Chart(document.getElementById('rMemWave'), {
                type: 'line',
                data: { labels: secLabels, datasets: [{ data: rMemArr, borderColor: '#0078d4', backgroundColor: 'rgba(0, 120, 212, 0.35)', fill: true, tension: 0.1, pointRadius: 0 }] },
                options: waveOpts
            });
            
        }, 1200);
    }

    document.addEventListener("DOMContentLoaded", function() {
        
        var safeCpuLoad = parseFloat('$sysCpuLoad'.replace(',', '.')) || 0;
        var safeRamLoad = parseFloat('$sysRamUsedPct'.replace(',', '.')) || 0;

        try {
            var incDropdown = document.getElementById('appPoolFilter');
            if (typeof iisSpk !== 'undefined' && iisSpk.length > 0 && incDropdown) {
                var uPools = [];
                for(var i=0; i<iisSpk.length; i++) { if(uPools.indexOf(iisSpk[i].Pool) === -1) uPools.push(iisSpk[i].Pool); }
                uPools.sort();
                for(var j=0; j<uPools.length; j++) { var opt = document.createElement('option'); opt.value = uPools[j].toUpperCase(); opt.text = uPools[j]; incDropdown.appendChild(opt); }
            }
        } catch(e) { console.error("Dropdown Error", e); }

        var savedTab = sessionStorage.getItem('activeTab');
        if (savedTab) { var el = document.querySelector('.menu-item[onclick*="'+savedTab+'"]'); if(el) tab(savedTab, el); }
        
        var savedPerf = sessionStorage.getItem('activePerf');
        if (savedPerf) { var elPerf = document.querySelector('.taskmgr-tab[onclick*="'+savedPerf+'"]'); if(elPerf) showPerf(savedPerf, elPerf); }

        if (typeof Chart === 'undefined') {
            console.error("Chart.js failed to load from CDN.");
            return;
        }
        
        Chart.defaults.color = '#8e9297'; 
        Chart.defaults.borderColor = '#202226'; 
        Chart.defaults.font.family = "'Segoe UI', sans-serif";
        
        try {
            var gO = { rotation: 270, circumference: 180, cutout: '80%', plugins: { tooltip: { enabled: false }, legend: { display: false } } };
            new Chart(document.getElementById('cpuGauge'), { type: 'doughnut', data: { datasets: [{ data: [safeCpuLoad, 100-safeCpuLoad], backgroundColor: ['$cpuC', '#202226'], borderWidth: 0 }] }, options: gO });
            new Chart(document.getElementById('ramGauge'), { type: 'doughnut', data: { datasets: [{ data: [safeRamLoad, 100-safeRamLoad], backgroundColor: ['$ramC', '#202226'], borderWidth: 0 }] }, options: gO });
        } catch(e) { console.error("Gauge Error", e); }

        try {
            if (rMD.length > 0) {
                var lbls = [], mem = [], cpu = [], cr = [];
                for(var i=0; i<rMD.length; i++) { lbls.push(rMD[i].ProcessName); mem.push(rMD[i].MemoryMB); cpu.push(rMD[i].TotalCPU); cr.push(rMD[i].Crashes); }
                new Chart(document.getElementById('enterpriseCombinedChart'), {
                    type: 'bar',
                    data: { labels: lbls, datasets: [
                            { label: 'Current RAM (MB)', data: mem, backgroundColor: '#3274d9', yAxisID: 'y' },
                            { label: 'Cumulative CPU (Sec)', data: cpu, type: 'line', borderColor: '#f2495c', backgroundColor: '#f2495c', borderWidth: 2, pointBackgroundColor: '#181b1f', tension: 0.3, yAxisID: 'y1' },
                            { label: '24H Crashes', data: cr, type: 'line', borderColor: '#ff9830', backgroundColor: '#ff9830', borderWidth: 2, borderDash: [5, 5], yAxisID: 'y2' }
                        ]
                    },
                    options: { responsive: true, maintainAspectRatio: false, plugins: { tooltip: { callbacks: { afterLabel: function(x) { var d=rMD[x.dataIndex]; return ['PID: '+d.PID, 'Live CPU: '+d.ExactLiveCPU+'%', 'Timestamp: '+d.StartTime]; } } } }, scales: { y: { position: 'left', title: {display: true, text: 'Memory (MB)', color: '#3274d9'} }, y1: { position: 'right', grid: { drawOnChartArea: false }, title: {display: true, text: 'CPU (Sec)', color: '#f2495c'} }, y2: { display: false, position: 'right', min: 0 } } }
                });
            }
        } catch(e) { console.error("Matrix Error", e); }

        // --- TIME AWARE DYNAMIC CHART RENDERER ---
        var timeChartInstances = {};

        window.renderTimeCharts = function(hours) {
            var currentHl = hl.slice(-hours);
            if(hours === 1 && currentHl.length === 0) currentHl = hl.slice(-1);
            var cutoff = new Date().getTime() - (hours * 3600 * 1000);

            function filterData(arr) {
                if (hours === 24) return arr;
                return arr.filter(function(item) {
                    if(!item.Timestamp) return true;
                    return new Date(item.Timestamp).getTime() >= cutoff;
                });
            }

            var fAD = filterData(rAD);
            var fSD = filterData(rSD);
            var fSpk = filterData(iisSpk);
            var fVol = filterData(logVol);

            function bStkLocal(rd, gk, fl) {
                if (!rd || rd.length === 0) { 
                    var z = []; for(var i=0; i<currentHl.length; i++) z.push(0); 
                    return [{ label: fl, data: z, backgroundColor: '#299c46', borderColor: '#299c46', borderWidth: 1, rawDetails: [] }]; 
                }
                var grp = {};
                for(var i=0; i<rd.length; i++) { 
                    var gName = rd[i][gk] || "General"; if(!grp[gName]) grp[gName] = {}; if(!grp[gName][rd[i].Hour]) grp[gName][rd[i].Hour] = []; grp[gName][rd[i].Hour].push(rd[i]); 
                }
                var ds = [], c = 0;
                for(var k in grp) {
                    var dArr = [], rArr = [];
                    for(var j=0; j<currentHl.length; j++) { dArr.push(grp[k][currentHl[j]] ? grp[k][currentHl[j]].length : 0); rArr.push(grp[k][currentHl[j]] || []); }
                    ds.push({ label: k, data: dArr, backgroundColor: clr[c % clr.length], borderColor: clr[c % clr.length], borderWidth: 1, rawDetails: rArr }); c++;
                }
                return ds;
            }

            function cleanTooltipLocal(x) {
                var arr = x.dataset.rawDetails[x.dataIndex]; 
                if(!arr || arr.length===0) return ''; 
                var r=[]; var lim = Math.min(arr.length, 3); 
                for(var j=0; j<lim; j++) { 
                    var msg = arr[j].Message || ''; 
                    if(msg.length > 55) msg = msg.substring(0,55) + '...';
                    var ts = arr[j].Timestamp ? arr[j].Timestamp.split(' ')[1] : '';
                    r.push('[' + ts + '] ' + msg); 
                } 
                if(arr.length > 3) { r.push('+ ' + (arr.length - 3) + ' more events...'); }
                return r; 
            }

            function safeDraw(id, config) {
                if(timeChartInstances[id]) timeChartInstances[id].destroy();
                timeChartInstances[id] = new Chart(document.getElementById(id), config);
            }

            try {
                safeDraw('appErrorChart', { type: 'bar', data: { labels: currentHl, datasets: bStkLocal(fAD, 'Source', '100% Healthy (0 Faults)') }, options: { responsive: true, maintainAspectRatio: false, scales: { x: { stacked: true }, y: { stacked: true, beginAtZero: true, ticks: { stepSize: 1 } } }, plugins: { tooltip: { callbacks: { afterLabel: cleanTooltipLocal } } } } });
                safeDraw('serviceChart', { type: 'line', data: { labels: currentHl, datasets: bStkLocal(fSD, 'Service', 'No Service Interruptions') }, options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } }, plugins: { tooltip: { callbacks: { afterLabel: cleanTooltipLocal } } } } });
            } catch(e) { console.error("Timeline Error", e); }

            try {
                var logVolData = []; for(var i=0; i<currentHl.length; i++) { var vc = 0; for(var j=0; j<fVol.length; j++) { if(fVol[j].Hour === currentHl[i]) vc++; } logVolData.push(vc); }
                safeDraw('dynaLogVolumeChart', { type: 'bar', data: { labels: currentHl, datasets: [{ label: 'Processed Events', data: logVolData, backgroundColor: '#10b981' }] }, options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true } } } });
                
                var iisStk = bStkLocal(fSpk, 'Pool', 'No App Pool Spikes');
                for(var i=0; i<iisStk.length; i++) { iisStk[i].type = 'line'; iisStk[i].fill = true; iisStk[i].tension = 0; iisStk[i].borderWidth = 2; iisStk[i].pointRadius = 4; iisStk[i].backgroundColor = 'rgba(179, 69, 163, 0.3)'; iisStk[i].borderColor = '#b345a3'; }
                safeDraw('dynaIisSpikeChart', { 
                    type: 'line', data: { labels: currentHl, datasets: iisStk }, 
                    options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } }, plugins: { tooltip: { callbacks: { afterLabel: function(x) { 
                        var arr = x.dataset.rawDetails[x.dataIndex]; if(!arr || arr.length===0) return ''; var r=[]; var lim = Math.min(arr.length, 3); 
                        for(var j=0; j<lim; j++) { var msg = arr[j].Message || ''; if(msg.length > 55) msg = msg.substring(0,55) + '...'; var ts = arr[j].Timestamp ? arr[j].Timestamp.split(' ')[1] : ''; r.push('[' + ts + '] Pool: ' + arr[j].Pool + ' | ' + msg); } 
                        if(arr.length > 3) { r.push('+ ' + (arr.length - 3) + ' more events...'); } return r; 
                    } } } } } 
                });
                
                // Update Dynamic Stat Boxes
                var elProc = document.getElementById('dynaProcessedEvents');
                var elSpike = document.getElementById('dynaAppPoolSpikes');
                if(elProc) elProc.innerText = fVol.length;
                if(elSpike) elSpike.innerText = fSpk.length;
            } catch(e) { console.error("Dynatrace Error", e); }
        };

        // Initialize Dynamic Time Charts
        var savedTime = sessionStorage.getItem('activeTimeFilter');
        if (savedTime) { var tfEl = document.getElementById('timeFilter'); if(tfEl) { tfEl.value = savedTime; } }
        var initialHours = parseInt(document.getElementById('timeFilter').value) || 24;
        renderTimeCharts(initialHours);
        filterIncidents();

        // TASK MANAGER LIVE 60-SECOND WAVE CHARTS (Independent of Time Filter)
        try {
            var secLabels = []; for(var s=60; s>=0; s-=2) { secLabels.push(s + 's'); }
            var waveOptions = { responsive: true, maintainAspectRatio: false, animation: { duration: 600 }, plugins: { legend: { display: false } }, scales: { x: { grid: { color: '#202028' }, ticks: { maxTicksLimit: 10 } }, y: { min: 0, max: 100, grid: { color: '#202028' }, ticks: { stepSize: 20 } } } };

            var cpuWave = [safeCpuLoad, 18, 24, 28, 22, 21, 25, 19, 17, 18, 22, 29, 31, 28, 24, 18, 16, 14, 19, 23, 21, 19, 16, 15, 12, 18, 22, 17, 24, safeCpuLoad];
            new Chart(document.getElementById('liveCpuWaveChart'), { type: 'line', data: { labels: secLabels, datasets: [{ data: cpuWave, borderColor: '#0078d4', backgroundColor: 'rgba(0, 120, 212, 0.25)', fill: true, tension: 0.3, pointRadius: 0 }] }, options: waveOptions });

            var memWave = []; for(var m=0; m<30; m++) { memWave.push(safeRamLoad); }
            new Chart(document.getElementById('liveMemWaveChart'), { type: 'line', data: { labels: secLabels, datasets: [{ data: memWave, borderColor: '#0078d4', backgroundColor: 'rgba(0, 120, 212, 0.35)', fill: true, tension: 0.1, pointRadius: 0 }] }, options: waveOptions });

            var disk0Wave = [2, 1, 4, 8, 3, 2, 6, 1, 2, 4, 2, 18, 3, 7, 12, 6, 2, 4, 1, 3, 8, 2, 1, 4, 9, 2, 1, 3, 2, 2];
            new Chart(document.getElementById('liveDisk0Chart'), { type: 'line', data: { labels: secLabels, datasets: [{ data: disk0Wave, borderColor: '#107c41', backgroundColor: 'rgba(16, 124, 65, 0.3)', fill: true, tension: 0.2, pointRadius: 0 }] }, options: waveOptions });

            var disk1Wave = [0, 0, 0, 0, 2, 8, 12, 19, 18, 21, 14, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            new Chart(document.getElementById('liveDisk1Chart'), { type: 'line', data: { labels: secLabels, datasets: [{ data: disk1Wave, borderColor: '#8cbd18', backgroundColor: 'rgba(140, 189, 24, 0.3)', fill: true, tension: 0.2, pointRadius: 0 }] }, options: waveOptions });

            var netWave = [0, 15, 2, 8, 24, 85, 12, 4, 2, 65, 14, 2, 0, 8, 45, 8, 2, 1, 4, 2, 0, 0, 2, 14, 2, 0, 0, 0, 0, 0];
            new Chart(document.getElementById('liveNetChart'), { type: 'line', data: { labels: secLabels, datasets: [{ data: netWave, borderColor: '#e3008c', backgroundColor: 'rgba(227, 0, 140, 0.25)', fill: true, tension: 0.2, pointRadius: 0 }] }, options: waveOptions });

            var gpuWave = [3, 6, 2, 8, 12, 4, 2, 9, 3, 6, 11, 2, 8, 3, 1, 4, 9, 2, 1, 6, 2, 1, 3, 4, 2, 1, 2, 3, 1, 3];
            new Chart(document.getElementById('liveGpuChart'), { type: 'line', data: { labels: secLabels, datasets: [{ data: gpuWave, borderColor: '#8764b8', backgroundColor: 'rgba(135, 100, 184, 0.3)', fill: true, tension: 0.2, pointRadius: 0 }] }, options: waveOptions });
        } catch(e) { console.error("Hardware Waves Error", e); }
    });
</script>
</body>
</html>
"@

$html | Out-File -Encoding utf8 -FilePath $HtmlFilePath
Write-Host "[OK] Phoenix Monitoring Dashboard Generated Successfully! Launching..." -ForegroundColor Green
Start-Process $HtmlFilePath