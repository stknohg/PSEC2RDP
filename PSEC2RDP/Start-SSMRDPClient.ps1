#Requires -Modules AWS.Tools.EC2, AWS.Tools.SimpleSystemsManagement

function Test-SSMInstanceStatus () {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InstanceId,
        [Parameter(Mandatory = $false)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [object]$Region
    )
    
    $pingStatus = Get-SSMInstanceInformation -InstanceInformationFilterList @{ Key = 'InstanceIds'; ValueSet = $InstanceId } -Select InstanceInformationList.PingStatus -ProfileName $ProfileName -Region $Region
    if (-not $?) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'Failed to get Instance information.'
        }
    }
    if ($pingStatus -ne 'Online') {
        return [PSCustomObject]@{
            Success = $false
            Message = ('Instance {0} is not online. (SSM PingStatus : {1})' -f $InstanceId, $pingStatus)
        }
    }
    return [PSCustomObject]@{
        Success = $true
        Message = ('Instance {0} is online. (SSM PingStatus : {1})' -f $InstanceId, $pingStatus)
    }
}

function Get-RDPLocalPort () {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$StartPort = 33389
    )

    $p = $StartPort
    while ($p -le 65535) {
        $result = if ($IsWindows) {
            Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction Ignore
        } else {
            lsof -iTCP:$p | grep 'LISTEN'
        }
        if ($null -eq $result) {
            break
        }
        $p += 1
    }
    if ($p -gt 65535) {
        return 65535
    }
    return $p
}

function Wait-SSMSessionStatus () {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SessionId,
        [Parameter(Mandatory = $false)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [object]$Region
    )

    do {
        Start-Sleep -Milliseconds 500
        $status = Get-SSMSession -State Active -Filter @{ Key = 'SessionId'; Value = $SessionId } -Select Sessions.Status -ProfileName $ProfileName -Region $Region
        if ($status -in ('None', 'Failed', 'Disconnected', 'Terminating', 'Terminated')) {
            Write-Error ('Failed to get SSM Session status. ({0})' -f $status)
            return
        }
        Write-Host ('Session {0} status : {1}' -f $ssmSessionId, $status)
    } until ($status -eq 'Connected')
}

<#
    Public function
#>
function Start-SSMRDPClient () {
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

    # Check if the instance is online
    $result = Test-SSMInstanceStatus -InstanceId $InstanceId -ProfileName $ProfileName -Region $Region
    if (-not $result.Success) {
        Write-Error $result.Message
        return
    }
    
    # Get local proxy port
    $hostName = 'localhost'
    $localPort = Get-RDPLocalPort

    # Start SSM session with session-manager-plugin 
    $params = @{
        Target       = $InstanceId
        DocumentName = 'AWS-StartPortForwardingSession'
        Parameter    = @{ portNumber = @("$Port"); localPortNumber = @("$localPort") }
        Reason       = 'PSEC2RDP.Start-SSMRDPClient'
        PassThru     = $true
        ProfileName  = $ProfileName
        Region       = $Region
    }
    $result = Start-SSMSessionEx @params
    if (-not $?) {
        Write-Error 'Failed to start SSM session.'
        return
    }
    $ssmSessionId = $result.Session.SessionId
    $ssmProcessId = $result.Process.Id

    # Check SSM sessoin status
    Wait-SSMSessionStatus -SessionId $ssmSessionId -ProfileName $ProfileName -Region $Region
    Write-Host ('Start listening {0}:{1}' -f $hostName, $localPort)

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
        $beginBlock.Invoke($hostName, $localPort, $adminCredential)

        # Invoke main scriptblock : always wait for exit. 
        $mainBlock.Invoke($hostName, $localPort, $adminCredential, $true)
    } finally {
        # Invoke end scriptblock
        $endBlock.Invoke($hostName, $localPort, $adminCredential)
        
        # Terminate SSM Session
        Write-Host ('Terminate session {0}' -f $ssmSessionId)
        Stop-SSMSession -SessionId $ssmSessionId -ProfileName $ProfileName -Region $Region > $null
        # Terminate session-manager-plugin process
        Write-Host ('Terminate session-manager-plugin process ({0})' -f $ssmProcessId)
        Stop-Process -Id $ssmProcessId -Force -ErrorAction Ignore > $null
    }
}
