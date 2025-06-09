# PowerShell User Management Suite
# Author: [Your Name]
# Date: June 2025
# Version: 2.0
# Purpose: Complete user lifecycle management for Active Directory environments

param(
    [Parameter(Mandatory=$true, ParameterSetName="Create")]
    [Parameter(Mandatory=$true, ParameterSetName="Modify")]
    [Parameter(Mandatory=$true, ParameterSetName="Delete")]
    [string]$CsvPath,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "Modify", "Delete", "Report")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\UserManagement_Log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt",
    
    [Parameter(Mandatory=$false)]
    [string]$DefaultPassword = "TempPass123!",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory=$false)]
    [switch]$SendEmail,
    
    [Parameter(Mandatory=$false)]
    [string]$SmtpServer = "mail.company.local",
    
    [Parameter(Mandatory=$false)]
    [string]$EmailFrom = "it-support@company.local",
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateHomeDirectory,
    
    [Parameter(Mandatory=$false)]
    [string]$HomeDirectoryBase = "\\fileserver\users$",
    
    [Parameter(Mandatory=$false)]
    [switch]$GenerateReport
)

# Import required modules
$requiredModules = @("ActiveDirectory")
foreach ($module in $requiredModules) {
    try {
        Import-Module $module -ErrorAction Stop
        Write-Host "✓ $module module loaded successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to load $module module. Please ensure it's installed."
        exit 1
    }
}

# Global variables for tracking
$script:SuccessCount = 0
$script:FailureCount = 0
$script:WarningCount = 0
$script:ProcessedUsers = @()

# Enhanced logging function with levels
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console with color coding unless suppressed
    if (-not $NoConsole) {
        switch ($Level) {
            "ERROR" { Write-Host $logEntry -ForegroundColor Red }
            "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
            "INFO" { Write-Host $logEntry -ForegroundColor Cyan }
            default { Write-Host $logEntry -ForegroundColor White }
        }
    }
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logEntry
}

# Enhanced CSV validation with detailed feedback
function Test-CsvStructure {
    param(
        [string]$CsvPath,
        [string]$Action
    )
    
    if (-not (Test-Path $CsvPath)) {
        Write-Log "CSV file not found: $CsvPath" "ERROR"
        return $false
    }
    
    try {
        $csvData = Import-Csv $CsvPath
        if ($csvData.Count -eq 0) {
            Write-Log "CSV file is empty" "ERROR"
            return $false
        }
        
        # Define required columns based on action
        $requiredColumns = switch ($Action) {
            "Create" { @("FirstName", "LastName", "Username", "Department", "JobTitle", "Email") }
            "Modify" { @("Username", "FirstName", "LastName", "Department", "JobTitle", "Email") }
            "Delete" { @("Username") }
            default { @("Username") }
        }
        
        $csvColumns = $csvData[0].PSObject.Properties.Name
        $missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }
        
        if ($missingColumns.Count -gt 0) {
            Write-Log "Missing required columns for action '$Action': $($missingColumns -join ', ')" "ERROR"
            Write-Log "Available columns: $($csvColumns -join ', ')" "INFO"
            return $false
        }
        
        # Validate data quality
        $issues = @()
        foreach ($row in $csvData) {
            if ([string]::IsNullOrWhiteSpace($row.Username)) {
                $issues += "Empty username found in row"
            }
            if ($Action -eq "Create" -and [string]::IsNullOrWhiteSpace($row.Email)) {
                $issues += "Empty email found for user: $($row.Username)"
            }
        }
        
        if ($issues.Count -gt 0) {
            Write-Log "Data quality issues found:" "WARNING"
            $issues | ForEach-Object { Write-Log "  - $_" "WARNING" }
            $script:WarningCount += $issues.Count
        }
        
        Write-Log "CSV structure validation passed for action: $Action" "SUCCESS"
        Write-Log "Found $($csvData.Count) records to process" "INFO"
        return $true
    }
    catch {
        Write-Log "Error reading CSV file: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Enhanced password generation
function New-SecurePassword {
    param([int]$Length = 12)
    
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*"
    $password = ""
    
    for ($i = 0; $i -lt $Length; $i++) {
        $password += $chars[(Get-Random -Maximum $chars.Length)]
    }
    
    return $password
}

# Create home directory function
function New-HomeDirectory {
    param(
        [string]$Username,
        [string]$BasePath = $HomeDirectoryBase
    )
    
    $homePath = Join-Path $BasePath $Username
    
    if (-not $WhatIf) {
        try {
            if (-not (Test-Path $homePath)) {
                New-Item -Path $homePath -ItemType Directory -Force | Out-Null
                
                # Set permissions
                $acl = Get-Acl $homePath
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Username, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                $acl.SetAccessRule($accessRule)
                Set-Acl -Path $homePath -AclObject $acl
                
                Write-Log "Created home directory: $homePath" "SUCCESS"
                return $homePath
            }
            else {
                Write-Log "Home directory already exists: $homePath" "WARNING"
                return $homePath
            }
        }
        catch {
            Write-Log "Failed to create home directory for $Username : $($_.Exception.Message)" "ERROR"
            return $null
        }
    }
    else {
        Write-Log "WHATIF: Would create home directory: $homePath" "INFO"
        return $homePath
    }
}

# Enhanced OU creation with description
function New-DepartmentOU {
    param(
        [string]$Department,
        [string]$Description = "Organizational Unit for $Department department"
    )
    
    $ouPath = "OU=$Department,DC=company,DC=local"
    
    try {
        Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop
        Write-Log "OU already exists: $ouPath" "INFO"
        return $ouPath
    }
    catch {
        if (-not $WhatIf) {
            try {
                New-ADOrganizationalUnit -Name $Department -Path "DC=company,DC=local" -Description $Description -ErrorAction Stop
                Write-Log "Created OU: $ouPath" "SUCCESS"
                return $ouPath
            }
            catch {
                Write-Log "Failed to create OU: $ouPath - $($_.Exception.Message)" "ERROR"
                return $null
            }
        }
        else {
            Write-Log "WHATIF: Would create OU: $ouPath" "INFO"
            return $ouPath
        }
    }
}

# Enhanced user creation function
function New-UserAccount {
    param($UserData)
    
    $username = $UserData.Username.Trim()
    $displayName = "$($UserData.FirstName.Trim()) $($UserData.LastName.Trim())"
    $userPrincipalName = "$username@company.local"
    $ouPath = "OU=$($UserData.Department.Trim()),DC=company,DC=local"
    
    # Generate secure password if not provided
    $password = if ($DefaultPassword -eq "TempPass123!") { New-SecurePassword } else { $DefaultPassword }
    
    # Check if user already exists
    try {
        $existingUser = Get-ADUser -Identity $username -ErrorAction Stop
        Write-Log "User already exists: $username" "WARNING"
        $script:WarningCount++
        return $false
    }
    catch {
        # User doesn't exist, proceed with creation
    }
    
    # Create the user account with enhanced attributes
    $userParams = @{
        Name = $displayName
        SamAccountName = $username
        UserPrincipalName = $userPrincipalName
        GivenName = $UserData.FirstName.Trim()
        Surname = $UserData.LastName.Trim()
        DisplayName = $displayName
        EmailAddress = $UserData.Email.Trim()
        Department = $UserData.Department.Trim()
        Title = $UserData.JobTitle.Trim()
        Path = $ouPath
        AccountPassword = (ConvertTo-SecureString $password -AsPlainText -Force)
        Enabled = $true
        ChangePasswordAtLogon = $true
        PasswordNeverExpires = $false
        CannotChangePassword = $false
    }
    
    # Add home directory if requested
    if ($CreateHomeDirectory) {
        $homeDir = New-HomeDirectory -Username $username
        if ($homeDir) {
            $userParams.HomeDirectory = $homeDir
            $userParams.HomeDrive = "H:"
        }
    }
    
    if (-not $WhatIf) {
        try {
            New-ADUser @userParams -ErrorAction Stop
            Write-Log "Successfully created user: $username" "SUCCESS"
            
            # Store user info for reporting
            $script:ProcessedUsers += [PSCustomObject]@{
                Username = $username
                DisplayName = $displayName
                Email = $UserData.Email
                Department = $UserData.Department
                Action = "Created"
                Status = "Success"
                Password = $password
                HomeDirectory = if ($CreateHomeDirectory) { $homeDir } else { "N/A" }
            }
            
            $script:SuccessCount++
            return $true
        }
        catch {
            Write-Log "Failed to create user: $username - $($_.Exception.Message)" "ERROR"
            $script:ProcessedUsers += [PSCustomObject]@{
                Username = $username
                DisplayName = $displayName
                Email = $UserData.Email
                Department = $UserData.Department
                Action = "Create Failed"
                Status = "Error"
                Error = $_.Exception.Message
            }
            $script:FailureCount++
            return $false
        }
    }
    else {
        Write-Log "WHATIF: Would create user: $username in $ouPath" "INFO"
        return $true
    }
}

# Enhanced group assignment function
function Add-UserToGroups {
    param(
        [string]$Username,
        [string]$Department
    )
    
    # Enhanced department groups with role-based access
    $departmentGroups = @{
        "IT" = @("Domain Users", "IT Staff", "VPN Users", "Server Operators")
        "HR" = @("Domain Users", "HR Staff", "Confidential Access")
        "Finance" = @("Domain Users", "Finance Staff", "Accounting Systems")
        "Sales" = @("Domain Users", "Sales Staff", "CRM Users")
        "Marketing" = @("Domain Users", "Marketing Staff", "Creative Tools")
        "Management" = @("Domain Users", "Management", "VPN Users", "Report Viewers")
    }
    
    $groups = $departmentGroups[$Department]
    if (-not $groups) {
        $groups = @("Domain Users")
    }
    
    foreach ($group in $groups) {
        if (-not $WhatIf) {
            try {
                # Check if group exists first
                Get-ADGroup -Identity $group -ErrorAction Stop | Out-Null
                Add-ADGroupMember -Identity $group -Members $Username -ErrorAction Stop
                Write-Log "Added $Username to group: $group" "SUCCESS"
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                Write-Log "Group not found: $group - Skipping" "WARNING"
                $script:WarningCount++
            }
            catch {
                Write-Log "Failed to add $Username to group: $group - $($_.Exception.Message)" "WARNING"
                $script:WarningCount++
            }
        }
        else {
            Write-Log "WHATIF: Would add $Username to group: $group" "INFO"
        }
    }
}

# User modification function
function Update-UserAccount {
    param($UserData)
    
    $username = $UserData.Username.Trim()
    
    try {
        $user = Get-ADUser -Identity $username -Properties * -ErrorAction Stop
        
        $updateParams = @{}
        
        # Update properties if they differ
        if ($UserData.FirstName -and $user.GivenName -ne $UserData.FirstName.Trim()) {
            $updateParams.GivenName = $UserData.FirstName.Trim()
        }
        if ($UserData.LastName -and $user.Surname -ne $UserData.LastName.Trim()) {
            $updateParams.Surname = $UserData.LastName.Trim()
        }
        if ($UserData.Email -and $user.EmailAddress -ne $UserData.Email.Trim()) {
            $updateParams.EmailAddress = $UserData.Email.Trim()
        }
        if ($UserData.Department -and $user.Department -ne $UserData.Department.Trim()) {
            $updateParams.Department = $UserData.Department.Trim()
        }
        if ($UserData.JobTitle -and $user.Title -ne $UserData.JobTitle.Trim()) {
            $updateParams.Title = $UserData.JobTitle.Trim()
        }
        
        if ($updateParams.Count -gt 0) {
            if (-not $WhatIf) {
                Set-ADUser -Identity $username @updateParams -ErrorAction Stop
                Write-Log "Successfully updated user: $username" "SUCCESS"
                $script:SuccessCount++
            }
            else {
                Write-Log "WHATIF: Would update user: $username" "INFO"
            }
        }
        else {
            Write-Log "No changes needed for user: $username" "INFO"
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to update user: $username - $($_.Exception.Message)" "ERROR"
        $script:FailureCount++
        return $false
    }
}

# User deletion function
function Remove-UserAccount {
    param($UserData)
    
    $username = $UserData.Username.Trim()
    
    try {
        $user = Get-ADUser -Identity $username -ErrorAction Stop
        
        if (-not $WhatIf) {
            # Disable first, then remove
            Disable-ADAccount -Identity $username -ErrorAction Stop
            Remove-ADUser -Identity $username -Confirm:$false -ErrorAction Stop
            Write-Log "Successfully removed user: $username" "SUCCESS"
            $script:SuccessCount++
        }
        else {
            Write-Log "WHATIF: Would remove user: $username" "INFO"
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to remove user: $username - $($_.Exception.Message)" "ERROR"
        $script:FailureCount++
        return $false
    }
}

# Email notification function
function Send-NotificationEmail {
    param(
        [string]$To,
        [string]$Username,
        [string]$Password,
        [string]$Department
    )
    
    $subject = "New Account Created - $Username"
    $body = @"
Dear User,

Your new account has been created with the following details:

Username: $Username
Temporary Password: $Password
Department: $Department

Please log in and change your password at your earliest convenience.

Important: You will be required to change your password on first login.

If you have any questions, please contact IT Support.

Best regards,
IT Support Team
"@

    if (-not $WhatIf) {
        try {
            Send-MailMessage -SmtpServer $SmtpServer -From $EmailFrom -To $To -Subject $subject -Body $body -ErrorAction Stop
            Write-Log "Email notification sent to: $To" "SUCCESS"
        }
        catch {
            Write-Log "Failed to send email to: $To - $($_.Exception.Message)" "WARNING"
            $script:WarningCount++
        }
    }
    else {
        Write-Log "WHATIF: Would send email to: $To" "INFO"
    }
}

# Generate comprehensive report
function New-DetailedReport {
    $reportPath = ".\UserManagement_Report_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>User Management Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #4472C4; color: white; padding: 20px; border-radius: 5px; }
        .summary { background-color: #E7F3FF; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .success { color: #008000; }
        .error { color: #FF0000; }
        .warning { color: #FF8C00; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4472C4; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>User Management Report</h1>
        <p>Generated: $(Get-Date)</p>
        <p>Action: $Action</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Records Processed:</strong> $($script:ProcessedUsers.Count)</p>
        <p class="success"><strong>Successful Operations:</strong> $script:SuccessCount</p>
        <p class="error"><strong>Failed Operations:</strong> $script:FailureCount</p>
        <p class="warning"><strong>Warnings:</strong> $script:WarningCount</p>
    </div>
    
    <h2>Detailed Results</h2>
    <table>
        <tr>
            <th>Username</th>
            <th>Display Name</th>
            <th>Email</th>
            <th>Department</th>
            <th>Action</th>
            <th>Status</th>
        </tr>
"@

    foreach ($user in $script:ProcessedUsers) {
        $statusClass = switch ($user.Status) {
            "Success" { "success" }
            "Error" { "error" }
            default { "warning" }
        }
        
        $html += @"
        <tr>
            <td>$($user.Username)</td>
            <td>$($user.DisplayName)</td>
            <td>$($user.Email)</td>
            <td>$($user.Department)</td>
            <td>$($user.Action)</td>
            <td class="$statusClass">$($user.Status)</td>
        </tr>
"@
    }
    
    $html += @"
    </table>
    
    <div class="summary">
        <h3>Log File Location</h3>
        <p>$LogPath</p>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "Detailed HTML report generated: $reportPath" "SUCCESS"
    return $reportPath
}

# Main execution function
function Invoke-UserManagement {
    Write-Log "=== Starting User Management Suite v2.0 ===" "INFO"
    Write-Log "Action: $Action" "INFO"
    Write-Log "CSV Path: $CsvPath" "INFO"
    Write-Log "Log Path: $LogPath" "INFO"
    
    if ($WhatIf) {
        Write-Log "Running in WHATIF mode - no changes will be made" "INFO"
    }
    
    # Handle report-only action
    if ($Action -eq "Report") {
        Write-Log "Generating AD user report..." "INFO"
        $users = Get-ADUser -Filter * -Properties Department, Title, EmailAddress, LastLogonDate
        foreach ($user in $users) {
            $script:ProcessedUsers += [PSCustomObject]@{
                Username = $user.SamAccountName
                DisplayName = $user.DisplayName
                Email = $user.EmailAddress
                Department = $user.Department
                Action = "Report"
                Status = "Active"
            }
        }
        $reportPath = New-DetailedReport
        Write-Log "Report completed: $reportPath" "SUCCESS"
        return
    }
    
    # Validate CSV for other actions
    if (-not (Test-CsvStructure -CsvPath $CsvPath -Action $Action)) {
        Write-Log "CSV validation failed. Exiting." "ERROR"
        exit 1
    }
    
    # Import user data
    try {
        $userData = Import-Csv $CsvPath
        Write-Log "Loaded $($userData.Count) users from CSV" "INFO"
    }
    catch {
        Write-Log "Failed to import CSV data: $($_.Exception.Message)" "ERROR"
        exit 1
    }
    
    # Process each user based on action
    foreach ($user in $userData) {
        Write-Log "Processing user: $($user.Username)" "INFO"
        
        switch ($Action) {
            "Create" {
                New-DepartmentOU -Department $user.Department
                if (New-UserAccount -UserData $user) {
                    Add-UserToGroups -Username $user.Username -Department $user.Department
                    if ($SendEmail -and $user.Email) {
                        Send-NotificationEmail -To $user.Email -Username $user.Username -Password $DefaultPassword -Department $user.Department
                    }
                }
            }
            "Modify" {
                Update-UserAccount -UserData $user
            }
            "Delete" {
                Remove-UserAccount -UserData $user
            }
        }
    }
    
    # Generate summary and reports
    Write-Log "=== Operation Completed ===" "INFO"
    Write-Log "Successful operations: $script:SuccessCount" "SUCCESS"
    Write-Log "Failed operations: $script:FailureCount" $(if ($script:FailureCount -gt 0) { "ERROR" } else { "INFO" })
    Write-Log "Warnings: $script:WarningCount" $(if ($script:WarningCount -gt 0) { "WARNING" } else { "INFO" })
    
    if ($GenerateReport -or $script:ProcessedUsers.Count -gt 0) {
        $reportPath = New-DetailedReport
        Write-Log "Detailed report saved: $reportPath" "INFO"
    }
}

# Script entry point
try {
    Invoke-UserManagement
}
catch {
    Write-Log "Critical error occurred: $($_.Exception.Message)" "ERROR"
    exit 1
}

Write-Log "Script execution completed" "INFO"