configuration ConfigureSPVM
{
    param
    (
        [Parameter(Mandatory)] [String]$DNSServer,
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [String]$DCName,
        [Parameter(Mandatory)] [String]$SQLName,
        [Parameter(Mandatory)] [String]$SQLAlias,
        [Parameter(Mandatory)] [String]$SharePointVersion,
        [Parameter(Mandatory)] [Boolean]$EnableAnalysis,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$DomainAdminCreds,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$SPSetupCreds,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$SPFarmCreds,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$SPAppPoolCreds,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$SPPassphraseCreds
    )

    Import-DscResource -ModuleName ComputerManagementDsc, NetworkingDsc, ActiveDirectoryDsc, xCredSSP, xWebAdministration, SharePointDsc, xPSDesiredStateConfiguration, xDnsServer, CertificateDsc, SqlServerDsc, cChoco

    [String] $DomainNetbiosName = (Get-NetBIOSName -DomainFQDN $DomainFQDN)
    $Interface = Get-NetAdapter| Where-Object Name -Like "Ethernet*"| Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)
    [System.Management.Automation.PSCredential] $DomainAdminCredsQualified = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($DomainAdminCreds.UserName)", $DomainAdminCreds.Password)
    [System.Management.Automation.PSCredential] $SPSetupCredsQualified = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($SPSetupCreds.UserName)", $SPSetupCreds.Password)
    [System.Management.Automation.PSCredential] $SPFarmCredsQualified = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($SPFarmCreds.UserName)", $SPFarmCreds.Password)
    [System.Management.Automation.PSCredential] $SPAppPoolCredsQualified = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($SPAppPoolCreds.UserName)", $SPAppPoolCreds.Password)
    [String] $SPDBPrefix = "SP$($SharePointVersion)_"
    [String] $SPTrustedSitesName = "spsites$SharePointVersion"
    [String] $ComputerName = Get-Content env:computername
    #[String] $ServiceAppPoolName = "SharePoint Service Applications"
    [String] $SetupPath = "C:\Setup"
    [String] $DCSetupPath = "\\$DCName\C$\Setup"
    [String] $TrustedIdChar = "e"
    [String] $SPTeamSiteTemplate = "STS#3"
    if ([String]::Equals($SharePointVersion, "2013") -or [String]::Equals($SharePointVersion, "2016")) {
        $SPTeamSiteTemplate = "STS#0"
    }
    [String] $AdfsOidcIdentifier = "fae5bd07-be63-4a64-a28c-7931a4ebf62b"

    Node localhost
    {
        LocalConfigurationManager
        {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        #**********************************************************
        # Initialization of VM - Do as much work as possible before waiting on AD domain to be available
        #**********************************************************
        WindowsFeature AddADTools             { Name = "RSAT-AD-Tools";      Ensure = "Present"; }
        WindowsFeature AddADPowerShell        { Name = "RSAT-AD-PowerShell"; Ensure = "Present"; }
        WindowsFeature AddDnsTools            { Name = "RSAT-DNS-Server";    Ensure = "Present"; }
        DnsServerAddress SetDNS { Address = $DNSServer; InterfaceAlias = $InterfaceAlias; AddressFamily  = 'IPv4' }

        #**********************************************************
        # Join AD forest
        #**********************************************************
        # If WaitForADDomain does not find the domain whtin "WaitTimeout" secs, it will signar a restart to DSC engine "RestartCount" times
        WaitForADDomain WaitForDCReady
        {
            DomainName              = $DomainFQDN
            WaitTimeout             = 1800
            RestartCount            = 2
            WaitForValidCredentials = $True
            Credential              = $DomainAdminCredsQualified
            DependsOn               = "[DnsServerAddress]SetDNS"
        }

        # WaitForADDomain sets reboot signal only if WaitForADDomain did not find domain within "WaitTimeout" secs
        PendingReboot RebootOnSignalFromWaitForDCReady
        {
            Name             = "RebootOnSignalFromWaitForDCReady"
            SkipCcmClientSDK = $true
            DependsOn        = "[WaitForADDomain]WaitForDCReady"
        }

        Computer JoinDomain
        {
            Name       = $ComputerName
            DomainName = $DomainFQDN
            Credential = $DomainAdminCredsQualified
            DependsOn  = "[PendingReboot]RebootOnSignalFromWaitForDCReady"
        }

        PendingReboot RebootOnSignalFromJoinDomain
        {
            Name             = "RebootOnSignalFromJoinDomain"
            SkipCcmClientSDK = $true
            DependsOn        = "[Computer]JoinDomain"
        }

    },


<#
# Azure DSC extension logging: C:\WindowsAzure\Logs\Plugins\Microsoft.Powershell.DSC\2.83.1.0
# Azure DSC extension configuration: C:\Packages\Plugins\Microsoft.Powershell.DSC\2.83.1.0\DSCWork

Install-Module -Name PendingReboot
help ConfigureSPVM

$DomainAdminCreds = Get-Credential -Credential "tjsp.sp"
$SPSetupCreds = Get-Credential -Credential "spsetup"
$SPFarmCreds = Get-Credential -Credential "spfarm"
$SPAppPoolCreds = Get-Credential -Credential "spapppool"
$SPPassphraseCreds = Get-Credential -Credential "Passphrase"
$DNSServer = "10.0.0.4"
$DomainFQDN = "redetjsp.local"
$DCName = "redetjsp.local"
$SQLName = "SQL"
$SQLAlias = "SQLAlias"
$SharePointVersion = "Subscription"
$ConfigureADFS = $false
$EnableAnalysis = $true

$outputPath = "C:\Packages\Plugins\Microsoft.Powershell.DSC\2.83.2.0\DSCWork\ConfigureSPVM.0\ConfigureSPVM"
ConfigureSPVM -DomainAdminCreds $DomainAdminCreds -SPSetupCreds $SPSetupCreds -SPFarmCreds $SPFarmCreds -SPAppPoolCreds $SPAppPoolCreds -SPPassphraseCreds $SPPassphraseCreds -DNSServer $DNSServer -DomainFQDN $DomainFQDN -DCName $DCName -SQLName $SQLName -SQLAlias $SQLAlias -SharePointVersion $SharePointVersion -ConfigureADFS $ConfigureADFS -EnableAnalysis $EnableAnalysis -ConfigurationData @{AllNodes=@(@{ NodeName="localhost"; PSDscAllowPlainTextPassword=$true })} -OutputPath $outputPath
Set-DscLocalConfigurationManager -Path $outputPath
Start-DscConfiguration -Path $outputPath -Wait -Verbose -Force

#>
