#Requires -Modules AWS.Tools.EC2

function Get-EC2HostName () {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InstanceId,
        [Parameter(Mandatory = $false)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [object]$Region
    )

    $instance = Get-EC2Instance -InstanceId $InstanceId -Select Reservations.Instances -ProfileName $ProfileName -Region $Region
    if (-not $?) {
        return [PSCustomObject]@{
            Success  = $false
            Message  = 'Failed to get Instance information.'
            HostName = ''
        }
    }
    # Get Public hostname
    $hostName = $instance.PublicDnsName
    if ([string]::IsNullOrEmpty($hostName)) {
        $hostName = $instance.PublicIpAddress
    }
    if ([string]::IsNullOrEmpty($hostName)) {
        return [PSCustomObject]@{
            Success  = $false
            Message  = 'Failed to get Instance public DNS name and public IP address.'
            HostName = ''
        }
    }
    return [PSCustomObject]@{
        Success  = $true
        Message  = ''
        HostName = $hostName
    }
}

<#
    Public function
#>
function Start-EC2RDPClient () {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InstanceId,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$PemFile,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$Port = 3389,
        [Parameter(Mandatory = $false)]
        [switch]$NoWait,
        [Parameter(Mandatory = $false)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [object]$Region
    )
    if (-not (Test-Path -LiteralPath $PemFile)) {
        Write-Warning ('-PemFile {0} not found.' -f $PemFile)
        return
    }
    if (-not $InstanceId) {
        $InstanceId = Read-Host "Enter EC2 Instance ID"
    }
    if ([string]::IsNullOrEmpty($InstanceId)) {
        return
    }
    
    # Get EC2 Public hostname
    $result = Get-EC2HostName -InstanceId $InstanceId -ProfileName $ProfileName -Region $Region
    if (-not $result.Success) {
        Write-Error $result.Message
        return
    }
    $hostName = $result.Hostname

    # Test TCP port
    if (-not (Test-TCPPort -HostName $hostName -Port $Port)) {
        Write-Error ('Failed to test TCP connection. (Port={0})' -f $Port)
        return
    }
    Write-Host ('Remote host {0} port {1} is open' -f $hostName, $Port)

    # Get Administrtor password
    $result = Get-EC2AdministratorPassword -InstanceId $InstanceId -PemFile $PemFile -ProfileName $ProfileName -Region $Region
    if (-not $result.Success) {
        Write-Error $result.Message
        return
    }
    $adminCredential = $result.Credential
    Write-Host 'Administrator password acquisition completed'

    # Start RDP client
    $beginBlock, $mainBlock, $endBlock = if ($IsWindows) { Get-DefaultMSTSCScriptBlocks } else { Get-DefaultMacOSScriptBlocks }
    try {
        # Invoke begin scriptblock
        $beginBlock.Invoke($hostName, $Port, $adminCredential)

        # Invoke main scriptblock
        $mainBlock.Invoke($hostName, $Port, $adminCredential, -not $NoWait)
    } finally {
        # Invoke end scriptblock
        $endBlock.Invoke($hostName, $Port, $adminCredential)
    }
}
