# PowerShell User Management Script

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Active Directory](https://img.shields.io/badge/Active%20Directory-Required-orange.svg)](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/active-directory-domain-services)

A comprehensive PowerShell script for automated bulk user creation and management in Active Directory environments. This tool streamlines the process of onboarding multiple users while maintaining consistency and security best practices.

## 🚀 Features

- **Bulk User Creation**: Create multiple Active Directory user accounts from CSV input
- **Automatic OU Management**: Creates department-based Organizational Units automatically
- **Group Assignment**: Assigns users to appropriate security groups based on department
- **Comprehensive Logging**: Detailed logging with timestamps and color-coded console output
- **Error Handling**: Robust error handling with detailed error reporting
- **Validation**: CSV structure validation before processing
- **WhatIf Mode**: Preview changes before execution
- **Summary Reports**: Generates detailed summary reports after execution

## 📋 Prerequisites

- Windows Server with Active Directory Domain Services
- PowerShell 5.1 or later
- Active Directory PowerShell module (RSAT)
- Domain Administrator privileges (for user creation)

## 🛠️ Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/powershell-user-management.git
   cd powershell-user-management
   ```

2. Ensure the Active Directory module is available:
   ```powershell
   Import-Module ActiveDirectory
   ```

## 📝 Usage

### Basic Usage

```powershell
.\New-BulkUsers.ps1 -CsvPath ".\users.csv"
```

### Advanced Usage

```powershell
# Preview changes without making them
.\New-BulkUsers.ps1 -CsvPath ".\users.csv" -WhatIf

# Specify custom log path and default password
.\New-BulkUsers.ps1 -CsvPath ".\users.csv" -LogPath "C:\Logs\UserCreation.log" -DefaultPassword "Welcome2024!"
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-CsvPath` | String | Yes | Path to the CSV file containing user data |
| `-LogPath` | String | No | Custom path for log file (default: current directory with timestamp) |
| `-DefaultPassword` | String | No | Default password for new users (default: "TempPass123!") |
| `-WhatIf` | Switch | No | Preview mode - shows what would be done without making changes |

## 📊 CSV File Format

The script requires a CSV file with the following columns:

| Column | Description | Example |
|--------|-------------|---------|
| FirstName | User's first name | John |
| LastName | User's last name | Smith |
| Username | SAM Account Name | jsmith |
| Department | Department/OU name | IT |
| JobTitle | User's job title | System Administrator |
| Email | Email address | john.smith@company.local |

### Sample CSV

```csv
FirstName,LastName,Username,Department,JobTitle,Email
John,Smith,jsmith,IT,System Administrator,john.smith@company.local
Sarah,Johnson,sjohnson,HR,HR Manager,sarah.johnson@company.local
```

A complete sample file is included: [`sample_users.csv`](sample_users.csv)

## 🏗️ What the Script Does

1. **Validates** the CSV file structure and required columns
2. **Creates** department-based Organizational Units if they don't exist
3. **Checks** for existing users to prevent duplicates
4. **Creates** user accounts with proper attributes
5. **Assigns** users to department-appropriate security groups
6. **Logs** all activities with detailed timestamps
7. **Generates** summary reports for audit purposes

## 📁 File Structure

```
powershell-user-management/
├── New-BulkUsers.ps1          # Main script
├── sample_users.csv           # Sample CSV file
├── README.md                  # This file
├── LICENSE                    # MIT License
└── docs/
    ├── CHANGELOG.md          # Version history
    └── screenshots/          # Demo screenshots
```

## 🔧 Customization

### Department Groups

The script automatically assigns users to groups based on their department. You can customize the group assignments by modifying the `$departmentGroups` hashtable in the script:

```powershell
$departmentGroups = @{
    "IT" = @("Domain Users", "IT Staff", "VPN Users")
    "HR" = @("Domain Users", "HR Staff")
    "Finance" = @("Domain Users", "Finance Staff")
    # Add your custom departments here
}
```

### Domain Configuration

Update the domain settings in the script:

```powershell
# Change these to match your domain
$ouPath = "OU=$Department,DC=yourcompany,DC=com"
$userPrincipalName = "$username@yourcompany.com"
```

## 📋 Example Output

```
[2025-06-09 10:30:15] [INFO] Starting User Management Script
[2025-06-09 10:30:15] [SUCCESS] CSV structure validation passed
[2025-06-09 10:30:16] [INFO] Loaded 10 users from CSV
[2025-06-09 10:30:17] [SUCCESS] Successfully created user: jsmith
[2025-06-09 10:30:18] [SUCCESS] Added jsmith to group: Domain Users
[2025-06-09 10:30:19] [SUCCESS] Added jsmith to group: IT Staff
[2025-06-09 10:30:20] [INFO] User creation completed
[2025-06-09 10:30:20] [SUCCESS] Successful: 10
[2025-06-09 10:30:20] [INFO] Failed: 0
```

## 🛡️ Security Considerations

- **Default Passwords**: All users are created with a default password and must change it at first logon
- **Permissions**: Script requires Domain Administrator privileges
- **Logging**: All activities are logged for audit purposes
- **Validation**: Input validation prevents common errors

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/yourusername/powershell-user-management/issues) page
2. Create a new issue with detailed information
3. Include relevant log files and error messages

## 🏆 Acknowledgments

- Microsoft Active Directory Documentation
- PowerShell Community
- IT Support professionals who provided feedback

## 📈 Future Enhancements

- [ ] GUI interface for easier use
- [ ] Support for user modification and deletion
- [ ] Integration with Azure AD
- [ ] Email notifications for new user accounts
- [ ] Automated home directory creation
- [ ] Group-based permissions assignment

---

**Created as part of IT Support Portfolio Development**

*This project demonstrates practical PowerShell scripting skills, Active Directory management, and automation capabilities relevant to IT Support roles.*