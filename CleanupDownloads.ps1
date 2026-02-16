if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Warning "This script requires Administrator privileges to register system-wide tasks."
    break
}

# Logging
$LogDir = "C:\Data\Maintenance-Logs"

# Create directory if it doesn't exist
if (!(Test-Path -Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$DateString = Get-Date -Format "yyyyMMdd-HHmm"
$LogFile = "$LogDir\CleanupDownloads_$DateString.txt"

Start-Transcript -Path $LogFile -Append

# Configure Variables
$TaskName = "CleanupDownloadsFolders"
$TaskDesc = "Deletes contents of all users' Downloads folders daily at 5:00 PM."
$ExecuteTime = "17:00"

# --- The Cleanup Command ---

# We embed this command directly into the task so no external script file is needed later.
# Adds an event log to Event Viewer > Windows Logs > Application
$CleanupCommand = "Get-ChildItem -Path 'C:\Users' -Directory | ForEach-Object { 
    `$targetPath = Join-Path -Path `$_.FullName -ChildPath 'Downloads';
    if (Test-Path `$targetPath) { 
        Get-ChildItem -Path `$targetPath -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue 
    }
};
if (`$?) { New-EventLog -Source 'DailyCleanup' -LogName Application -ErrorAction SilentlyContinue; Write-EventLog -LogName Application -Source 'DailyCleanup' -EventID 1001 -EntryType Information -Message 'Daily Downloads Cleanup completed successfully.' }"

# Encode the command to avoid complex quoting issues inside the Task Scheduler arguments
$Bytes = [System.Text.Encoding]::Unicode.GetBytes($CleanupCommand)
$EncodedCommand = [Convert]::ToBase64String($Bytes)

# --- Create Task Objects ---

# 1. Action: Launch PowerShell with the encoded command
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $EncodedCommand"

# 2. Trigger: Daily at 5:00 PM
$Trigger = New-ScheduledTaskTrigger -Daily -At $ExecuteTime

# 3. Principal: Run as SYSTEM (NT AUTHORITY\SYSTEM) to ensure access to all user folders
#    LogonType 'ServiceAccount' allows it to run whether users are logged in or not.
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# 4. Settings: Allow the task to start if on battery (optional, but good for laptops), don't stop if running long
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

# --- Register the Task ---
try {
    # Unregister existing task if it exists to allow updates
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    # Register the new task
    Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -TaskName $TaskName -Description $TaskDesc -ErrorAction Stop
    
    Write-Host "Success: Task '$TaskName' has been created." -ForegroundColor Green
}
catch {
    Write-Error "Failed to register task. Error details: $_"
}


Stop-Transcript
