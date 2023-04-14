@{
    ModuleVersion        = '0.1.0'
    CompatiblePSEditions = @('Core')
    GUID                 = '64b7d8e0-d5ce-4390-baa2-ea72f86eacc0'
    Author               = 'Takuya Shibata'
    CompanyName          = 'Takuya Shibata'
    Copyright            = '(c) Takuya Shibata. All rights reserved.'
    Description          = 'Remote Desktop Utility for Amazon EC2'
    PowerShellVersion    = '7.0.0'
    NestedModules        = @('PSEC2RDP.psm1')
    FunctionsToExport    = @('Start-SSMSessionEx', 'Start-EC2RDPClient', 'Start-SSMRDPClient')
    PrivateData          = @{
        PSData = @{
            ExternalModuleDependencies = @('AWS.Tools.EC2', 'AWS.Tools.SimpleSystemsManagement')
            LicenseUri                 = 'https://github.com/stknohg/PSEC2RDP/blob/main/LICENSE'
            ProjectUri                 = 'https://github.com/stknohg/PSEC2RDP'
            Tags                       = @('AWS', 'EC2', 'AWS Systems Manager', 'Remote Desktop')
        } 
    } 
}
