Param (
    [Parameter(Mandatory=$true)] [string] $VmAdminUsername,
    [Parameter(Mandatory=$true)] [string] $VmAdminPassword,
    [Parameter(Mandatory=$true)] [string] $SqlLoginUsername,
    [Parameter(Mandatory=$true)] [string] $SqlLoginPassword,
    [Parameter(Mandatory=$true)] [string] $SqlClientIpAddress
)

Install-PackageProvider -Name 'NuGet' -RequiredVersion '2.8.5.201' -Force
Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted'
Install-Module -Name 'SqlServer' -AllowClobber -Force

# This script will be executed by the custom script extension in the SYSTEM user context. We need to talk to
# SQL Server with the VM administrator account, which is the default SQL administrator in the marketplace image.
# This PSCredential will allow us to act as the VM administrator.
$secureVmAdminPassword = ConvertTo-SecureString -String $VmAdminPassword -AsPlainText -Force
$vmAdminCredential = New-Object -TypeName 'PSCredential' -ArgumentList "$env:ComputerName\$VmAdminUsername", $secureVmAdminPassword

# Enable mixed mode authentication (service restart required). By default the marketplace image is Windows
# authentication only. We need to do this in the execution context of the VM administrator.
Invoke-Command -ComputerName 'localhost' -Credential $vmAdminCredential -ArgumentList @($SqlLoginUsername, $SqlLoginPassword) -ScriptBlock {
    Param (
        [Parameter(Mandatory=$true)] [string] $SqlLoginUsername,
        [Parameter(Mandatory=$true)] [string] $SqlLoginPassword
    )
    Invoke-Sqlcmd -ServerInstance 'localhost' -Database 'master' `
        -Query "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"
    Restart-Service -Name 'MSSQLServer'

    # Add SQL login
    $secureSqlLoginPassword = ConvertTo-SecureString -String $SqlLoginPassword -AsPlainText -Force
    $sqlLoginCredential = New-Object -TypeName 'PSCredential' -ArgumentList $SqlLoginUsername, $secureSqlLoginPassword
    Add-SqlLogin -ServerInstance 'localhost' -LoginName $SqlLoginUsername -LoginType 'SqlLogin' -Enable -GrantConnectSql `
        -LoginPSCredential $sqlLoginCredential
}

# Configure Windows firewall rules. These only allow traffic from the specified client IP address.
New-NetFirewallRule -DisplayName 'SQL Server' -Direction 'Inbound' -Protocol 'TCP' -LocalPort 1433 `
    -RemoteAddress @($SqlClientIpAddress) -Action 'Allow'
New-NetFirewallRule -DisplayName 'SQL Admin Connection' -Direction 'Inbound' -Protocol 'TCP' -LocalPort 1434 `
    -RemoteAddress @($SqlClientIpAddress) -Action 'Allow'
New-NetFirewallRule -DisplayName 'SQL Database Management' -Direction 'Inbound' -Protocol 'UDP' -LocalPort 1434 `
    -RemoteAddress @($SqlClientIpAddress) -Action 'Allow'
New-NetFirewallRule -DisplayName 'SQL Service Broker' -Direction 'Inbound' -Protocol 'TCP' -LocalPort 4022 `
    -RemoteAddress @($SqlClientIpAddress) -Action 'Allow'
New-NetFirewallRule -DisplayName 'SQL Debugger/RPC' -Direction 'Inbound' -Protocol 'TCP' -LocalPort 135 `
    -RemoteAddress @($SqlClientIpAddress) -Action 'Allow'
New-NetFirewallRule -DisplayName 'SQL Analysis Services' -Direction 'Inbound' -Protocol 'TCP' -LocalPort 2383 `
    -RemoteAddress @($SqlClientIpAddress) -Action 'Allow'
New-NetFirewallRule -DisplayName 'SQL Browser' -Direction 'Inbound' -Protocol 'TCP' -LocalPort 2382 `
    -RemoteAddress @($SqlClientIpAddress) -Action 'Allow'
