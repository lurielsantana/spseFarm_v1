configuration ConfigureSPVM
{
    param
    (
        [Parameter(Mandatory)] [String]$DNSServer,
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$DomainAdminCreds,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$SqlSvcCreds,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$SPSetupCreds
    )

    Import-DscResource -ModuleName ComputerManagementDsc, NetworkingDsc, ActiveDirectoryDsc, SqlServerDsc, xPSDesiredStateConfiguration

    WaitForSqlSetup
    [String] $DomainNetbiosName = (Get-NetBIOSName -DomainFQDN $DomainFQDN)
    $Interface = Get-NetAdapter| Where-Object Name -Like "Ethernet*"| Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)
    [PSCredential] $DomainAdminCredsQualified = New-Object PSCredential ("${DomainNetbiosName}\$($DomainAdminCreds.UserName)", $DomainAdminCreds.Password)
    [PSCredential] $SPSetupCredsQualified = New-Object PSCredential ("${DomainNetbiosName}\$($SPSetupCreds.UserName)", $SPSetupCreds.Password)
    [PSCredential] $SQLCredsQualified = New-Object PSCredential ("${DomainNetbiosName}\$($SqlSvcCreds.UserName)", $SqlSvcCreds.Password)
    $ComputerName = Get-Content env:computername

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
        WindowsFeature AddADTools      { Name = "RSAT-AD-Tools";      Ensure = "Present"; }
        WindowsFeature AddADPowerShell { Name = "RSAT-AD-PowerShell"; Ensure = "Present"; }
        
        DnsServerAddress SetDNS { Address = $DNSServer; InterfaceAlias = $InterfaceAlias; AddressFamily  = 'IPv4' }
        
        SqlMaxDop ConfigureMaxDOP { ServerName = $ComputerName; InstanceName = "MSSQLSERVER"; MaxDop = 1; }

        xScript EnableFileSharing
        {
            TestScript = {
                # Test if firewall rules for file sharing already exist
                $rulesSet = Get-NetFirewallRule -DisplayGroup "File And Printer Sharing" -Enabled True -ErrorAction SilentlyContinue | Where-Object{$_.Profile -eq "Domain"}
                if ($null -eq $rulesSet) {
                    return $false   # Run SetScript
                } else {
                    return $true    # Rules already set
                }
            }
            SetScript = {
                Set-NetFirewallRule -DisplayGroup "File And Printer Sharing" -Enabled True -Profile Domain -Confirm:$false
            }
            GetScript = { }
        }

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
