Param (
    [Parameter(Mandatory=$false)] [string] $VmAdminUsername = 'SqlServerAdmin',
    [Parameter(Mandatory=$true)] [string] $VmAdminPassword,
    [Parameter(Mandatory=$true)] [string] $SqlLoginUsername,
    [Parameter(Mandatory=$true)] [string] $SqlLoginPassword,
    [Parameter(Mandatory=$false)] [string] $SqlClientIpAddress = (Invoke-RestMethod -Uri 'http://ipinfo.io/json' | Select-Object -ExpandProperty 'ip')
)

Import-Module -Name 'AzureRM'

# Create resource group
$resourceGroup = New-AzureRmResourceGroup -Name 'sqlserver' -Location 'UK South'

# Create network, subnet and public IP address
$subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name 'sqlserver-subnet' -AddressPrefix '192.168.1.0/24'
$vnet = $resourceGroup | New-AzureRmVirtualNetwork -Name 'sqlserver-vnet' -AddressPrefix '192.168.0.0/16' -Subnet $subnetConfig
$pip = $resourceGroup | New-AzureRmPublicIpAddress -AllocationMethod Static -IdleTimeoutInMinutes 4 -Name 'sqlserver-pip'

# Create network security policy
$sqlRule = New-AzureRmNetworkSecurityRuleConfig -Name 'sqlrule' -Protocol 'Tcp' -Direction Inbound -Priority 1000 `
    -SourceAddressPrefix $SqlClientIpAddress -SourcePortRange 1433 -DestinationAddressPrefix * -DestinationPortRange 1433 -Access 'Allow'
$nsg = $resourceGroup | New-AzureRmNetworkSecurityGroup -Name $NsgName -SecurityRules @($sqlRule)

# Create network interface
$nic = $resourceGroup | New-AzureRmNetworkInterface -Name 'sqlserver-nic' -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id `
   -NetworkSecurityGroupId $nsg.Id

# Create storage account and upload SQL Server configuration script to blob storage
$storageAccount = $resourceGroup | New-AzureRmStorageAccount -AccountName "anchorloopsqlvm" -SkuName 'Standard_LRS' -Kind 'Storage'
$storageAccountKey = ($storageAccount | Get-AzureRmStorageAccountKey).Value[0]
$storageContext = $storageAccount | New-AzureStorageContext -StorageAccountKey $storageAccountKey
$storageContainer = $storageContext | New-AzureStorageContainer -Name 'sqlserver' -Permission 'Blob'
$customScript = 'Set-SqlServerConfig.ps1'
Set-AzureStorageBlobContent -File "./$customScript" -Container $storageContainer -Blob $customScript -Context $storageContext

# Create admin credential
$securePassword = ConvertTo-SecureString -String $VmAdminPassword -AsPlainText -Force
$credential = New-Object -TypeName 'System.Management.Automation.PSCredential' -ArgumentList $VmAdminUsername, $securePassword

# Create virtual machine configuration
$vmConfig = New-AzureRmVMConfig -VMName 'sqlserver' -VMSize 'Standard_D2' | `
   Set-AzureRmVMOperatingSystem -Windows -ComputerName 'sqlserver' -Credential $credential -ProvisionVMAgent -EnableAutoUpdate | `
   Set-AzureRmVMSourceImage -PublisherName "MicrosoftSQLServer" -Offer "SQL2017-WS2016" -Skus "SQLDEV" -Version "latest" | `
   Add-AzureRmVMNetworkInterface -Id $nic.Id

# Create the virtual machine
$vm = $resourceGroup | New-AzureRmVM -VM $vmConfig

# Set VM custom script extension to configure SQL Server
Set-AzureRmVMCustomScriptExtension -VM $vm -StorageAccountName $storageAccount -ContainerName $storageContainer `
    -FileName $customScript -Run $customScript | Update-AzureRmVM