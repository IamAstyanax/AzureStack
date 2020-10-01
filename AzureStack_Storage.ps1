# Deploys AzureStack Storage platform using infrastructure as code using PowerShell and C#
#Use for Azurestack on premise storage deployment for distributed storage clustering
#See software defined networking for switch embedded teaming over ROCE/iWARP

# install the roles for each of the cluster nodes
Install-WindowsFeature -Name "Hyper-V", "Failover-Clustering", "Data-Center-Bridging", "RSAT-Clustering-PowerShell", "Hyper-V-PowerShell", "FS-FileServer"


# Fill in these variables with your values - This will install on all nodes for IAC type deployment
$ServerList = $servers
$FeatureList = "Hyper-V", "Failover-Clustering", "Data-Center-Bridging", "RSAT-Clustering-PowerShell", "Hyper-V-PowerShell", "FS-FileServer"

# This part runs the Install-WindowsFeature cmdlet on all servers in $ServerList, passing the list of features into the scriptblock with the "Using" scope modifier so you don't have to hard-code them here.
Invoke-Command ($ServerList) {
    Install-WindowsFeature -Name $Using:Featurelist
}




# Fill in these variables with your values - pools together disks, zaps disks, and forms to ready for S2D clustering
$ServerList = $servers

Invoke-Command ($ServerList) {
    Update-StorageProviderCache
    Get-StoragePool | ? IsPrimordial -eq $false | Set-StoragePool -IsReadOnly:$false -ErrorAction SilentlyContinue
    Get-StoragePool | ? IsPrimordial -eq $false | Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false -ErrorAction SilentlyContinue
    Get-StoragePool | ? IsPrimordial -eq $false | Remove-StoragePool -Confirm:$false -ErrorAction SilentlyContinue
    Get-PhysicalDisk | Reset-PhysicalDisk -ErrorAction SilentlyContinue
    Get-Disk | ? Number -ne $null | ? IsBoot -ne $true | ? IsSystem -ne $true | ? PartitionStyle -ne RAW | % {
        $_ | Set-Disk -isoffline:$false
        $_ | Set-Disk -isreadonly:$false
        $_ | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
        $_ | Set-Disk -isreadonly:$true
        $_ | Set-Disk -isoffline:$true
    }
    Get-Disk | Where Number -Ne $Null | Where IsBoot -Ne $True | Where IsSystem -Ne $True | Where PartitionStyle -Eq RAW | Group -NoElement -Property FriendlyName
} | Sort -Property PsComputerName, Count

#Validate the cluster to make sure all tests pass - it saves an html file in c:\users\$username\appdata\temp\etc\etc\etc
Test-Cluster –Node $servers –Include "Storage Spaces Direct", "Inventory", "Network", "System Configuration"

#Create the cluster with a unique name and IP
New-Cluster –Name storagespaces –Node <$nodes> –NoStorage -staticaddress $addressingforazurecluster

#Create the volume within the storage pool
New-Volume -FriendlyName $volume -FileSystem CSVFS_ReFS -StoragePoolFriendlyName S2D* -Size 14.53TB

#Create cluster failure domain

New-ClusterFaultDomain -Name N4 -Type Rack -Location "$location"
New-ClusterFaultDomain -Name N2 -Type Rack -Location "$location"
New-ClusterFaultDomain -Name N1 -Type Rack -Location "$location"
# set rules for failure domain
Set-ClusterFaultDomain -Name $node -Parent N2
Set-ClusterFaultDomain -Name $node -Parent N1
Set-ClusterFaultDomain -Name $node -Parent N4

#verify rules
get-clusterfaultdomain

