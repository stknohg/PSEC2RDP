#Requires -Modules AWS.Tools.EC2

function Get-EC2AdministratorPassword {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InstanceId,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$PemFile,
        [Parameter(Mandatory = $false)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [object]$Region
    )

    try {
        $plainPassword = Get-EC2PasswordData -InstanceId $InstanceId -PemFile $PemFile -Decrypt -ProfileName $ProfileName -Region $Region
        return [PSCustomObject]@{
            Success    = $true
            Message    = ''
            Credential = [System.Management.Automation.PSCredential]::new('Administrator', (ConvertTo-SecureString $plainPassword -AsPlainText -Force))
        }
    } catch {
        Write-Error $_
        return [PSCustomObject]@{
            Success    = $false
            Message    = 'Failed to get Administrator password.'
            Credential = $null
        }
    }
}

function Test-TCPPort ([string]$HostName, [int]$Port) {
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $result = $client.ConnectAsync($HostName, $Port).Wait(1000)
        if (-not $result) {
            return $false
        }
        $client.Close()
        return $true
    } catch {
        Write-Error $_
        return $false
    } finally {
        $client.Dispose()
    }
}

function Get-DefaultMSTSCScriptBlocks () {
    # Return 3 scriptblocks (begin block, main block, end block)
    return ( {
            param ([string]$HostName, [int]$Port, [PSCredential]$Credential)

            # Save credential temporary
            Write-Verbose "Invoke cmdkey.exe /generic:TERMSRV/$HostName /user:$($Credential.UserName) /pass:********"
            cmdkey.exe /generic:TERMSRV/$HostName /user:$($Credential.UserName) /pass:$($Credential.GetNetworkCredential().Password) > $null
            if ($?) {
                Write-Host "Save credential TERMSRV/$HostName to Credential Manager"
            }
        }, {
            param ([string]$HostName, [int]$Port, [PSCredential]$Credential, [bool]$Wait)

            # Start mstsc.exe
            Write-Host ('Start RDP client')
            Write-Host ('Conneting to {0}:{1}' -f $HostName, $Port)
            Start-Process -FilePath 'mstsc.exe' -ArgumentList ("/v:${HostName}:$Port", '/f') -Wait:$Wait
            if (-not $Wait) {
                Start-Sleep -Seconds 3
            }
        } , {
            param ([string]$HostName, [int]$Port, [PSCredential]$Credential)
        
            # Remove saved credential
            Write-Verbose "Invoke cmdkey.exe /delete:TERMSRV/$HostName"
            cmdkey.exe /delete:TERMSRV/$HostName > $null
            if ($?) {
                Write-Host "Delete credential TERMSRV/$HostName to Credential Manager"
            }
        })
}

<#
#
# WIP
#
function Get-DefaultParrallesClientScriptBlocks () {
    return ( {
            param ([string]$HostName, [int]$Port, [PSCredential]$Credential)
            # do nothing
        }, {
            param ([string]$HostName, [int]$Port, [PSCredential]$Credential, [bool]$Wait)

            # Start Parallels client
            Write-Host ('Conneting to {0}:{1}' -f $HostName, $Port)
            $params = @{
                FilePath         = Join-Path $env:ProgramFiles 'Parallels\Client\TSClient.exe'
                WorkingDirectory = Join-Path $env:ProgramFiles 'Parallels\Client\'
                # m!='4' : direct RDP mode
                # q!= : plain password... e!= seems to be hashed password, but the specification is unknown.
                ArgumentList     = @("m!='4'", "s!='$HostName'", "b!=''", "t!='$Port'", "d!=''", "u!='$($Credential.UserName)'", "q!='$($Credential.GetNetworkCredential().Password)'")
                Wait             = $Wait
            }
            Start-Process @params
        } , {
            param ([string]$HostName, [int]$Port, [PSCredential]$Credential)
            # do nothing
        })
}
#>