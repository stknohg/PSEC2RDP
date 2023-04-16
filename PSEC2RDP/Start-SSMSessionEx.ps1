#Requires -Modules AWS.Tools.SimpleSystemsManagement

<#
    Public function
#>
function Start-SSMSessionEx () {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$DocumentName,
        [Parameter(Mandatory = $false)]
        [hashtable]$Parameter,
        [Parameter(Mandatory = $false)]
        [string]$Reason,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [Parameter(Mandatory = $false)]
        [switch]$PassThru,
        [Parameter(Mandatory = $false)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [object]$Region
    )
    
    if (-not (Get-Command 'session-manager-plugin' -Type Application -ErrorAction Ignore)) {
        $message = @'
SessionManagerPlugin (session-manager-plugin) is not found.
Please refer to SessionManager Documentation here:
https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
'@
        Write-Error $message
        return
    }

    $session = $null
    try {
        $params = @{
            Parameter   = $Parameter
            Target      = $Target
            ProfileName = $ProfileName
            Region      = $Region
        }
        if (-not [string]::IsNullOrEmpty($DocumentName)) {
            $params['DocumentName'] = $DocumentName
        }
        if (-not [string]::IsNullOrEmpty($Reason)) {
            $params['Reason'] = $Reason
        }
        $session = Start-SSMSession @params
    } catch {
        Write-Error $_
        return
    }
    if ($null -eq $session) {
        Write-Error 'Failed to get SSM session.'
        return
    }

    # Start SSM Session manager plugin
    if ([string]::IsNullOrEmpty($ProfileName)) {
        $ProfileName = $StoredAWSCredentials
    }
    if ([string]::IsNullOrEmpty($Region)) {
        $Region = (Get-DefaultAWSRegion).Region
    }
    # Setup arguments
    $arguments = @()
    # arg1 : session json
    $arguments += "`"$((($session | ConvertTo-Json -Compress) -replace '"', '\"'))`""
    # arg2 : region name
    $arguments += $Region
    # arg3 : StartSession
    $arguments += 'StartSession'
    # arg4 : shared credentials file profile name
    $arguments += $ProfileName
    # arg5 : parameter json
    $arg5hash = @{ Target = $Target; }
    if (-not [string]::IsNullOrEmpty($DocumentName)) {
        $arg5hash['DocumentName'] = $DocumentName
    }
    if ($null -ne $Parameter) {
        $arg5hash['Parameter'] = $Parameter
    }
    if (-not [string]::IsNullOrEmpty($Reason)) {
        $arg5hash['Reason'] = $Reason
    }
    $arguments += "`"$(($arg5hash | ConvertTo-Json -Compress) -replace '"', '\"')`""
    # arg 6 : SSM endpoint URL
    $arguments += "https://ssm.$($region).amazonaws.com"
    Write-Verbose 'session-manager-plugin arguments'
    for ($i = 0; $i -lt $arguments.Count; $i++) {
        Write-Verbose "  arg$($i + 1) : $($arguments[$i])"
    }
    # start session-manager-plugin
    if ($PassThru) {
        # PassThru
        $proc = if ($IsWindows) {
            Start-Process -FilePath 'session-manager-plugin' -ArgumentList $arguments -PassThru -WindowStyle Hidden
        } else {
            # -WindowStyle parameter is not supported in non-Windows environment
            Start-Process -FilePath 'session-manager-plugin' -ArgumentList $arguments -PassThru
        }
        Write-Host ('Starting session with SessionId: {0}' -f $session.SessionId)
        Write-Host ('Start session-manager-plugin process ({0})' -f $proc.Id)
        return [PSCustomObject]@{
            Session = $session
            Process = $proc
        }
    } else {
        # Wait
        Start-Process -FilePath 'session-manager-plugin' -ArgumentList $arguments -Wait -NoNewWindow
    }
}
