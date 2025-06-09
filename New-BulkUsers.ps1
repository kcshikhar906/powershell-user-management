# PowerShell User Management Script
# Author: Shikhar KC
# Date: June 2025
# Purpose: Bulk user creation and management for Active Directory environments

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\UserManagement_Log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt",
    
    [Parameter(Mandatory=$false)]
    [string]$DefaultPassword = "TempPass123!",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Import required modules
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Active Directory module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load Active Directory module. Please ensure RSAT is installed."
    exit 1
}

# Function to write to log file
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console with color coding
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry -ForegroundColor White }
    }
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logEntry
}

# Function to validate CSV structure
function Test-CsvStructure {
    param([string]$CsvPath)
    
    if (-not (Test-Path $CsvPath)) {
        Write-Log "CSV file not found: $CsvPath" "ERROR"
        return $false
    }
    
    try {
        $csvData = Import-Csv $CsvPath
        $requiredColumns = @("FirstName", "LastName", "Username", "Department", "JobTitle", "Email")
        
        $csvColumns = $csvData[0].PSObject.Properties.Name
        $missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }
        
        if ($missingColumns.Count -gt 0) {
            Write-Log "Missing required columns: $($missingColumns -join ', ')" "ERROR"
            return $false
        }
        
        Write-Log "CSV structure validation passed" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Error reading CSV file: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to create organizational unit if it doesn't exist
function New-DepartmentOU {
    param([string]$Department)
    
    $ouPath = "OU=$Department,DC=company,DC=local"
    
    try {
        Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop
        Write-Log "OU already exists: $ouPath" "INFO"
    }
    catch {
        if (-not $WhatIf) {
            try {
                New-ADOrganizationalUnit -Name $Department -Path "DC=company,DC=local" -ErrorAction Stop
                Write-Log "Created OU: $ouPath" "SUCCESS"
            }
            catch {
                Write-Log "Failed to create OU: $ouPath - $($_.Exception.Message)" "ERROR"
            }
        }
        else {
            Write-Log "WHATIF: Would create OU: $ouPath" "INFO"
        }
    }
}

# Function to create user account
function New-UserAccount {
    param($UserData)
    
    $username = $UserData.Username
    $displayName = "$($UserData.FirstName) $($UserData.LastName)"
    $userPrincipalName = "$username@company.local"
    $ouPath = "OU=$($UserData.Department),DC=company,DC=local"
    
    # Check if user already exists
    try {
        Get-ADUser -Identity $username -ErrorAction Stop
        Write-Log "User already exists: $username" "WARNING"
        return $false
    }
    catch {
        # User doesn't exist, proceed with creation
    }
    
    # Create the user account
    $userParams = @{
        Name = $displayName
        SamAccountName = $username
        UserPrincipalName = $userPrincipalName
        GivenName = $UserData.FirstName
        Surname = $UserData.LastName
        DisplayName = $displayName
        EmailAddress = $UserData.Email
        Department = $UserData.Department
        Title = $UserData.JobTitle
        Path = $ouPath
        AccountPassword = (ConvertTo-SecureString $DefaultPassword -AsPlainText -Force)
        Enabled = $true
        ChangePasswordAtLogon = $true
    }
    
    if (-not $WhatIf) {
        try {
            New-ADUser @userParams -ErrorAction Stop
            Write-Log "Successfully created user: $username" "SUCCESS"
            return $true
        }
        catch {
            Write-Log "Failed to create user: $username - $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
    else {
        Write-Log "WHATIF: Would create user: $username in $ouPath" "INFO"
        return $true
    }
}

# Function to add user to groups
function Add-UserToGroups {
    param(
        [string]$Username,
        [string]$Department
    )
    
    # Default groups based on department
    $departmentGroups = @{
        "IT" = @("Domain Users", "IT Staff", "VPN Users")
        "HR" = @("Domain Users", "HR Staff")
        "Finance" = @("Domain Users", "Finance Staff")
        "Sales" = @("Domain Users", "Sales Staff")
        "Marketing" = @("Domain Users", "Marketing Staff")
    }
    
    $groups = $departmentGroups[$Department]
    if (-not $groups) {
        $groups = @("Domain Users")
    }
    
    foreach ($group in $groups) {
        if (-not $WhatIf) {
            try {
                Add-ADGroupMember -Identity $group -Members $Username -ErrorAction Stop
                Write-Log "Added $Username to group: $group" "SUCCESS"
            }
            catch {
                Write-Log "Failed to add $Username to group: $group - $($_.Exception.Message)" "WARNING"
            }
        }
        else {
            Write-Log "WHATIF: Would add $Username to group: $group" "INFO"
        }
    }
}

# Main execution
Write-Log "Starting User Management Script" "INFO"
Write-Log "CSV Path: $CsvPath" "INFO"
Write-Log "Log Path: $LogPath" "INFO"

if ($WhatIf) {
    Write-Log "Running in WHATIF mode - no changes will be made" "INFO"
}

# Validate CSV structure
if (-not (Test-CsvStructure -CsvPath $CsvPath)) {
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

# Process each user
$successCount = 0
$failureCount = 0

foreach ($user in $userData) {
    Write-Log "Processing user: $($user.Username)" "INFO"
    
    # Create department OU if needed
    New-DepartmentOU -Department $user.Department
    
    # Create user account
    if (New-UserAccount -UserData $user) {
        # Add user to groups
        Add-UserToGroups -Username $user.Username -Department $user.Department
        $successCount++
    }
    else {
        $failureCount++
    }
}

# Summary
Write-Log "User creation completed" "INFO"
Write-Log "Successful: $successCount" "SUCCESS"
Write-Log "Failed: $failureCount" $(if ($failureCount -gt 0) { "ERROR" } else { "INFO" })
Write-Log "Log file saved to: $LogPath" "INFO"

# Generate summary report
$summaryReport = @"
User Management Script Summary Report
Generated: $(Get-Date)
CSV File: $CsvPath
Total Users Processed: $($userData.Count)
Successful Creations: $successCount
Failed Creations: $failureCount
Log File: $LogPath
"@

$reportPath = ".\UserManagement_Summary_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
$summaryReport | Out-File -FilePath $reportPath
Write-Log "Summary report saved to: $reportPath" "INFO"