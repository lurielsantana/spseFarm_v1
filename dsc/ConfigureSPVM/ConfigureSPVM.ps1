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
    [System.Management.Automation.PSCredential] $DomainAdminCredsQualified = New-Object System.Management.Automation.PSCredential ("$DomainAdminCreds.UserName", $DomainAdminCreds.Password)
    [System.Management.Automation.PSCredential] $SPSetupCredsQualified = New-Object System.Management.Automation.PSCredential ("$SPSetupCreds.UserName)", $SPSetupCreds.Password)
    [System.Management.Automation.PSCredential] $SPFarmCredsQualified = New-Object System.Management.Automation.PSCredential ("$SPFarmCreds.UserName)", $SPFarmCreds.Password)
    [System.Management.Automation.PSCredential] $SPAppPoolCredsQualified = New-Object System.Management.Automation.PSCredential ("$SPAppPoolCreds.UserName)", $SPAppPoolCreds.Password)
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

        # xCredSSP is required forSharePointDsc resources SPUserProfileServiceApp and SPDistributedCacheService
        xCredSSP CredSSPServer { Ensure = "Present"; Role = "Server"; DependsOn = "[DnsServerAddress]SetDNS" }
        xCredSSP CredSSPClient { Ensure = "Present"; Role = "Client"; DelegateComputers = "*.$DomainFQDN", "localhost"; DependsOn = "[xCredSSP]CredSSPServer" }

        # IIS cleanup
        xWebAppPool RemoveDotNet2Pool         { Name = ".NET v2.0";            Ensure = "Absent"; }
        xWebAppPool RemoveDotNet2ClassicPool  { Name = ".NET v2.0 Classic";    Ensure = "Absent"; }
        xWebAppPool RemoveDotNet45Pool        { Name = ".NET v4.5";            Ensure = "Absent"; }
        xWebAppPool RemoveDotNet45ClassicPool { Name = ".NET v4.5 Classic";    Ensure = "Absent"; }
        xWebAppPool RemoveClassicDotNetPool   { Name = "Classic .NET AppPool"; Ensure = "Absent"; }
        xWebAppPool RemoveDefaultAppPool      { Name = "DefaultAppPool";       Ensure = "Absent"; }
        xWebSite    RemoveDefaultWebSite      { Name = "Default Web Site";     Ensure = "Absent"; PhysicalPath = "C:\inetpub\wwwroot"; }

        # Allow NTLM on HTTPS sites when site host name is different than the machine name - https://docs.microsoft.com/en-US/troubleshoot/windows-server/networking/accessing-server-locally-with-fqdn-cname-alias-denied
        Registry DisableLoopBackCheck { Key = "HKLM:\System\CurrentControlSet\Control\Lsa"; ValueName = "DisableLoopbackCheck"; ValueData = "1"; ValueType = "Dword"; Ensure = "Present" }

        # Enable TLS 1.2 - https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/application-proxy-add-on-premises-application#tls-requirements
        # It's a best practice, and mandatory with Windows 2012 R2 (SharePoint 2013) to allow xRemoteFile to download releases from GitHub: https://github.com/PowerShell/xPSDesiredStateConfiguration/issues/405           
        Registry EnableTLS12RegKey1 { Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'; ValueName = 'DisabledByDefault'; ValueType = 'Dword'; ValueData = '0'; Ensure = 'Present' }
        Registry EnableTLS12RegKey2 { Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'; ValueName = 'Enabled';           ValueType = 'Dword'; ValueData = '1'; Ensure = 'Present' }
        Registry EnableTLS12RegKey3 { Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'; ValueName = 'DisabledByDefault'; ValueType = 'Dword'; ValueData = '0'; Ensure = 'Present' }
        Registry EnableTLS12RegKey4 { Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'; ValueName = 'Enabled';           ValueType = 'Dword'; ValueData = '1'; Ensure = 'Present' }

        # Enable strong crypto by default for .NET Framework 4 applications - https://docs.microsoft.com/en-us/dotnet/framework/network-programming/tls#configuring-security-via-the-windows-registry
        Registry SchUseStrongCrypto         { Key = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319';             ValueName = 'SchUseStrongCrypto';       ValueType = 'Dword'; ValueData = '1'; Ensure = 'Present' }
        Registry SchUseStrongCrypto32       { Key = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'; ValueName = 'SchUseStrongCrypto';       ValueType = 'Dword'; ValueData = '1'; Ensure = 'Present' }
        Registry SystemDefaultTlsVersions   { Key = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319';             ValueName = 'SystemDefaultTlsVersions'; ValueType = 'Dword'; ValueData = '1'; Ensure = 'Present' }
        Registry SystemDefaultTlsVersions32 { Key = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'; ValueName = 'SystemDefaultTlsVersions'; ValueType = 'Dword'; ValueData = '1'; Ensure = 'Present' }

        SqlAlias AddSqlAlias { Ensure = "Present"; Name = $SQLAlias; ServerName = $SQLName; Protocol = "TCP"; TcpPort= 1433 }

        xScript DisableIESecurity
        {
            TestScript = {
                return $false   # If TestScript returns $false, DSC executes the SetScript to bring the node back to the desired state
            }
            SetScript = {
                # Source: https://stackoverflow.com/questions/9368305/disable-ie-security-on-windows-server-via-powershell
                $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
                #$UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
                Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
                #Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0

                if ($false -eq (Test-Path -Path "HKLM:\Software\Policies\Microsoft\Internet Explorer")) {
                    New-Item -Path "HKLM:\Software\Policies\Microsoft" -Name "Internet Explorer"
                }

                # Disable the first run wizard of IE
                $ieFirstRunKey = "HKLM:\Software\Policies\Microsoft\Internet Explorer\Main"
                if ($false -eq (Test-Path -Path $ieFirstRunKey)) {
                    New-Item -Path "HKLM:\Software\Policies\Microsoft\Internet Explorer" -Name "Main"
                }
                Set-ItemProperty -Path $ieFirstRunKey -Name "DisableFirstRunCustomize" -Value 1
                
                # Set new tabs to open "about:blank" in IE
                $ieNewTabKey = "HKLM:\Software\Policies\Microsoft\Internet Explorer\TabbedBrowsing"
                if ($false -eq (Test-Path -Path $ieNewTabKey)) {
                    New-Item -Path "HKLM:\Software\Policies\Microsoft\Internet Explorer" -Name "TabbedBrowsing"
                }
                Set-ItemProperty -Path $ieNewTabKey -Name "NewTabPageShow" -Value 0
            }
            GetScript = { }
        }

        Script EnableLongPath
        {
            GetScript = { }
            TestScript = {
                return $false   # If TestScript returns $false, DSC executes the SetScript to bring the node back to the desired state
            }
            SetScript = 
            {
                $longPathEnabled = Get-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\ -Name LongPathsEnabled
                if (-not $longPathEnabled) {
                    New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\ -Name LongPathsEnabled -Value 1 -PropertyType DWord
                }
                else {
                    Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\ -Name LongPathsEnabled -Value 1
                }
            }
        }

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

        # Create the rules in the firewall required for the distributed cache
        xScript CreateFirewallRulesForDistributedCache
        {
            TestScript = {
                # Test if firewall rules already exist
                $icmpRuleName = "File and Printer Sharing (Echo Request - ICMPv4-In)"
                $icmpFirewallRule = Get-NetFirewallRule -DisplayName $icmpRuleName -ErrorAction SilentlyContinue
                $spRuleName = "SharePoint Distributed Cache"
                $firewallRule = Get-NetFirewallRule -DisplayName $spRuleName -ErrorAction SilentlyContinue
                if ($null -eq $icmpFirewallRule -or $null -eq $firewallRule) {
                    return $false   # Run SetScript
                } else {
                    return $true    # Rules already set
                }
            }
            SetScript = {
                $icmpRuleName = "File and Printer Sharing (Echo Request - ICMPv4-In)"
                $icmpFirewallRule = Get-NetFirewallRule -DisplayName $icmpRuleName -ErrorAction SilentlyContinue
                if ($null -eq $icmpFirewallRule) {
                    New-NetFirewallRule -Name Allow_Ping -DisplayName $icmpRuleName `
                        -Description "Allow ICMPv4 ping" `
                        -Protocol ICMPv4 `
                        -IcmpType 8 `
                        -Enabled True `
                        -Profile Any `
                        -Action Allow
                }
                Enable-NetFirewallRule -DisplayName $icmpRuleName

                $spRuleName = "SharePoint Distributed Cache"
                $firewallRule = Get-NetFirewallRule -DisplayName $spRuleName -ErrorAction SilentlyContinue
                if ($null -eq $firewallRule) {
                    New-NetFirewallRule -Name "SPDistCache" `
                        -DisplayName $spRuleName `
                        -Protocol TCP `
                        -LocalPort 22233-22236 `
                        -Group "SharePoint"
                }                
                Enable-NetFirewallRule -DisplayName $spRuleName
            }
            GetScript = { }
        }

        #**********************************************************
        # Install applications using Chocolatey
        #**********************************************************
        cChocoInstaller InstallChoco
        {
            InstallDir = "C:\Choco"
        }

        cChocoPackageInstaller InstallEdge
        {
            Name                 = "microsoft-edge"
            Ensure               = "Present"
            DependsOn            = "[cChocoInstaller]InstallChoco"
        }

        cChocoPackageInstaller InstallNotepadpp
        {
            Name                 = "notepadplusplus.install"
            Ensure               = "Present"
            DependsOn            = "[cChocoInstaller]InstallChoco"
        }

        cChocoPackageInstaller Install7zip
        {
            Name                 = "7zip.install"
            Ensure               = "Present"
            DependsOn            = "[cChocoInstaller]InstallChoco"
        }

        cChocoPackageInstaller InstallVscode
        {
            Name                 = "vscode.portable"
            Ensure               = "Present"
            DependsOn            = "[cChocoInstaller]InstallChoco"
        }

        if ($SharePointVersion -eq "Subscription") {
            #**********************************************************
            # Download and install for SharePoint
            #**********************************************************
            Script DownloadSharePoint
            {
                SetScript = {
                    $count = 0
                    $maxCount = 10
                    $spIsoUrl = "https://go.microsoft.com/fwlink/?linkid=2171943"
                    $dstFolder = Join-Path -Path $env:windir -ChildPath "Temp"
                    $dstFile = Join-Path -Path $dstFolder -ChildPath "OfficeServer.iso"
                    $spInstallFolder = Join-Path -Path $dstFolder -ChildPath "OfficeServer"
                    $setupFile =  Join-Path -Path $spInstallFolder -ChildPath "setup.exe"
                    while (($count -lt $maxCount) -and (-not(Test-Path $setupFile)))
                    {
                        try {
                        # donwload the installation package
                        Start-BitsTransfer -Source $spIsoUrl -Destination $dstFile
                
                        # mount the image file and copy to C:\windows\TEMP\OfficeServer folder
                        $mountedIso = Mount-DiskImage -ImagePath $dstFile -PassThru
                        $driverLetter =  (Get-Volume -DiskImage $mountedIso).DriveLetter
                        Copy-Item -Path "${driverLetter}:\" -Destination $spInstallFolder -Recurse -Force -ErrorAction SilentlyContinue
                        Dismount-DiskImage -DevicePath $mountedIso.DevicePath -ErrorAction SilentlyContinue
                        
                        (Get-ChildItem -Path $spInstallFolder -Recurse -File).FullName | Foreach-Object {Unblock-File $_}
                        $count++
                        }
                        catch {
                        $count++
                        }
                    }

                    if (-not(Test-Path $setupFile)) {
                        Write-Error -Message "Failed to download SharePoint installation package" 
                    }
                }
                TestScript = { Test-Path "${env:windir}\Temp\OfficeServer\setup.exe" }
                GetScript = { return @{ "Result" = "false" } } # This block must return a hashtable. The hashtable must only contain one key Result and the value must be of type String.
            }

            SPInstallPrereqs InstallPrerequisites
            {
                IsSingleInstance  = "Yes"
                InstallerPath     = "${env:windir}\Temp\OfficeServer\Prerequisiteinstaller.exe"
                OnlineMode        = $true
                DependsOn         = "[Script]DownloadSharePoint"
            }

            SPInstall InstallBinaries
            {
                IsSingleInstance = "Yes"
                BinaryDir        = "${env:windir}\Temp\OfficeServer"
                ProductKey       = "VW2FM-FN9FT-H22J4-WV9GT-H8VKF"
                DependsOn        = "[SPInstallPrereqs]InstallPrerequisites"
            }
        }

        #**********************************************************
        # Join AD forest
        #**********************************************************
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

        # This script is still needed
        xScript CreateWSManSPNsIfNeeded
        {
            SetScript =
            {
                # A few times, deployment failed because of this error:
                # "The WinRM client cannot process the request. A computer policy does not allow the delegation of the user credentials to the target computer because the computer is not trusted."
                # The root cause was that SPNs WSMAN/SP and WSMAN/sp.contoso.local were missing in computer account contoso\SP
                # Those SPNs are created by WSMan when it (re)starts
                # Restarting service causes an error, so creates SPNs manually instead
                # Restart-Service winrm

                # Create SPNs WSMAN/SP and WSMAN/sp.contoso.local
                $domainFQDN = $using:DomainFQDN
                $computerName = $using:ComputerName
                Write-Verbose -Message "Adding SPNs 'WSMAN/$computerName' and 'WSMAN/$computerName.$domainFQDN' to computer '$computerName'"
                setspn.exe -S "WSMAN/$computerName" "$computerName"
                setspn.exe -S "WSMAN/$computerName.$domainFQDN" "$computerName"
            }
            GetScript = { }
            # If the TestScript returns $false, DSC executes the SetScript to bring the node back to the desired state
            TestScript = 
            {
                $computerName = $using:ComputerName
                $samAccountName = "$computerName$"
                if ((Get-ADComputer -Filter {(SamAccountName -eq $samAccountName)} -Property serviceprincipalname | Select-Object serviceprincipalname | Where-Object {$_.ServicePrincipalName -like "WSMAN/$computerName"}) -ne $null) {
                    # SPN is present
                    return $true
                }
                else {
                    # SPN is missing and must be created
                    return $false
                }
            }
            DependsOn = "[PendingReboot]RebootOnSignalFromJoinDomain"
        }

        #**********************************************************
        # Do SharePoint pre-reqs that require membership in AD domain
        #**********************************************************
        # Create DNS entries used by SharePoint
        xDnsRecord AddTrustedSiteDNS
        {
            Name                 = $SPTrustedSitesName
            Zone                 = $DomainFQDN
            DnsServer            = $DCName
            Target               = "$ComputerName.$DomainFQDN"
            Type                 = "CName"
            Ensure               = "Present"
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn            = "[PendingReboot]RebootOnSignalFromJoinDomain"
        }

        #**********************************************************
        # Provision required accounts for SharePoint
        #**********************************************************
        ADUser CreateSPSetupAccount
        {
            DomainName                    = $DomainFQDN
            UserName                      = $SPSetupCreds.UserName
            Password                      = $SPSetupCreds
            UserPrincipalName             = "$($SPSetupCreds.UserName)@$DomainFQDN"
            PasswordNeverExpires          = $true
            Ensure                        = "Present"
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn                     = "[PendingReboot]RebootOnSignalFromJoinDomain"
        }        

        ADUser CreateSParmAccount
        {
            DomainName                    = $DomainFQDN
            UserName                      = $SPFarmCreds.UserName
            UserPrincipalName             = "$($SPFarmCreds.UserName)@$DomainFQDN"
            Password                      = $SPFarmCreds
            PasswordNeverExpires          = $true
            Ensure                        = "Present"
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn                     = "[PendingReboot]RebootOnSignalFromJoinDomain"
        }

        Group AddSPSetupAccountToAdminGroup
        {
            GroupName            = "Administrators"
            Ensure               = "Present"
            MembersToInclude     = @("$($SPSetupCredsQualified.UserName)")
            Credential           = $DomainAdminCredsQualified
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn            = "[ADUser]CreateSPSetupAccount"
        }

        ADUser CreateSPAppPoolAccount
        {
            DomainName                    = $DomainFQDN
            UserName                      = $SPAppPoolCreds.UserName
            UserPrincipalName             = "$($SPAppPoolCreds.UserName)@$DomainFQDN"
            Password                      = $SPAppPoolCreds
            PasswordNeverExpires          = $true
            Ensure                        = "Present"
            PsDscRunAsCredential          = $DomainAdminCredsQualified
            DependsOn                     = "[PendingReboot]RebootOnSignalFromJoinDomain"
        }

        # Since this DSC may run on multiple SP servers, each with a diferent SPN (spsites201x), SPN cannot be set in ADUser.ServicePrincipalNames because each config removes the SPNs of the previous one
        ADServicePrincipalName SetSPAppPoolSPN1
        {
            ServicePrincipalName = "HTTP/$SPTrustedSitesName.$DomainFQDN"
            Account              = $SPAppPoolCreds.UserName
            Ensure               = "Present"
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn            = "[ADUser]CreateSPAppPoolAccount"
        }

        ADServicePrincipalName SetSPAppPoolSPN2
        {
            ServicePrincipalName = "HTTP/$SPTrustedSitesName"
            Account              = $SPAppPoolCreds.UserName
            Ensure               = "Present"
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn            = "[ADUser]CreateSPAppPoolAccount"
        }

        File AccountsProvisioned
        {
            DestinationPath      = "C:\Logs\DSC1.txt"
            Contents             = "AccountsProvisioned"
            Type                 = "File"
            Force                = $true
            PsDscRunAsCredential = $SPSetupCredential
            DependsOn            = "[Group]AddSPSetupAccountToAdminGroup", "[ADUser]CreateSParmAccount", "[ADUser]CreateSPAppPoolAccount", "[xScript]CreateWSManSPNsIfNeeded"
        }

        # Fiddler must be installed as $DomainAdminCredsQualified because it's a per-user installation
        cChocoPackageInstaller InstallFiddler
        {
            Name                 = "fiddler"
            Version              =  5.0.20204.45441
            Ensure               = "Present"
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn            = "[cChocoInstaller]InstallChoco", "[PendingReboot]RebootOnSignalFromJoinDomain"
        }

        # Install ULSViewer as $DomainAdminCredsQualified to ensure that the shortcut is visible on the desktop
        cChocoPackageInstaller InstallUlsViewer
        {
            Name                 = "ulsviewer"
            Ensure               = "Present"
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn            = "[cChocoInstaller]InstallChoco"
        }

        xScript WaitForSQL
        {
            SetScript =
            {
                $retrySleep = 30
                $server = $using:SQLAlias
                $db = "master"
                $retry = $true
                while ($retry) {
                    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection "Data Source=$server;Initial Catalog=$db;Integrated Security=True;Enlist=False;Connect Timeout=3"
                    try {
                        $sqlConnection.Open()
                        Write-Verbose "Connection to SQL Server $server succeeded"
                        $sqlConnection.Close()
                        $retry = $false
                    }
                    catch {
                        Write-Verbose "SQL connection to $server failed, retry in $retrySleep secs..."
                        Start-Sleep -s $retrySleep
                    }
                }
            }
            GetScript            = { return @{ "Result" = "false" } } # This block must return a hashtable. The hashtable must only contain one key Result and the value must be of type String.
            TestScript           = { return $false } # If the TestScript returns $false, DSC executes the SetScript to bring the node back to the desired state
            PsDscRunAsCredential = $DomainAdminCredsQualified
            DependsOn            = "[SqlAlias]AddSqlAlias", "[File]AccountsProvisioned"
        }

        #**********************************************************
        # Create SharePoint farm
        #**********************************************************
        SPFarm CreateSPFarm
        {
            DatabaseServer            = $SQLAlias
            FarmConfigDatabaseName    = $SPDBPrefix + "Config"
            Passphrase                = $SPPassphraseCreds
            FarmAccount               = $SPFarmCredsQualified
            PsDscRunAsCredential      = $SPSetupCredsQualified
            AdminContentDatabaseName  = $SPDBPrefix + "AdminContent"
            CentralAdministrationPort = 5000
            # If RunCentralAdmin is false and configdb does not exist, SPFarm checks during 30 mins if configdb got created and joins the farm
            RunCentralAdmin           = $true
            IsSingleInstance          = "Yes"
            SkipRegisterAsDistributedCacheHost = $false
            Ensure                    = "Present"
            DependsOn                 = "[xScript]WaitForSQL"
        }

        # Distributed Cache is now enabled directly by the SPFarm resource
        # SPDistributedCacheService EnableDistributedCache
        # {
        #     Name                 = "AppFabricCachingService"
        #     CacheSizeInMB        = 1000 # Default size is 819MB on a server with 16GB of RAM (5%)
        #     CreateFirewallRules  = $true
        #     ServiceAccount       = $SPFarmCredsQualified.UserName
        #     InstallAccount       = $SPSetupCredsQualified
        #     Ensure               = "Present"
        #     DependsOn            = "[SPFarm]CreateSPFarm"
        # }

        SPManagedAccount CreateSPAppPoolManagedAccount
        {
            AccountName          = $SPAppPoolCredsQualified.UserName
            Account              = $SPAppPoolCredsQualified
            PsDscRunAsCredential = $SPSetupCredsQualified
            DependsOn            = "[SPFarm]CreateSPFarm"
        }

        SPWebApplication CreateMainWebApp
        {
            Name                   = "SharePoint - 80"
            ApplicationPool        = "SharePoint - 80"
            ApplicationPoolAccount = $SPAppPoolCredsQualified.UserName
            AllowAnonymous         = $false
            DatabaseName           = $SPDBPrefix + "Content_80"
            WebAppUrl              = "http://$SPTrustedSitesName/"
            Port                   = 80
            Ensure                 = "Present"
            PsDscRunAsCredential   = $SPSetupCredsQualified
            DependsOn              = "[SPFarm]CreateSPFarm"
        }

        if ($ConfigureADFS -eq $true) {
            # Delay this operation significantly, so that DC has time to generate and copy the certificates
            File CopyCertificatesFromDC
            {
                Ensure          = "Present"
                Type            = "Directory"
                Recurse         = $true
                SourcePath      = "$DCSetupPath"
                DestinationPath = "$SetupPath\Certificates"
                Credential      = $DomainAdminCredsQualified
                DependsOn       = "[PendingReboot]RebootOnSignalFromJoinDomain"
            }

            SPTrustedRootAuthority TrustRootCA
            {
                Name                 = "$DomainFQDN root CA"
                CertificateFilePath  = "$SetupPath\Certificates\ADFS Signing issuer.cer"
                Ensure               = "Present"
                PsDscRunAsCredential = $SPSetupCredsQualified
                DependsOn            = "[SPFarm]CreateSPFarm"
            }

            if ($SharePointVersion -eq "Subscription") {
                $apppoolUserName = $SPAppPoolCredsQualified.UserName
                xScript SetOidcCertificate
                {
                    SetScript = 
                    {
                        $apppoolUserName = $using:apppoolUserName
                        # Import-Module SharePointServer | Out-Null
                        # Setup farm properties to work with OIDC
                        # Create a self-signed certificate in one SharePoint Server in the farm
                        $cert = New-SelfSignedCertificate -CertStoreLocation Cert:\LocalMachine\My -Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider' -Subject "CN=SharePoint Cookie Cert"
    
                        # Grant access to the certificate private key.
                        $rsaCert = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                        $fileName = $rsaCert.key.UniqueName
                        $path = "$env:ALLUSERSPROFILE\Microsoft\Crypto\RSA\MachineKeys\$fileName"
                        $permissions = Get-Acl -Path $path
                        $access_rule = New-Object System.Security.AccessControl.FileSystemAccessRule($apppoolUserName, 'Read', 'None', 'None', 'Allow')
                        $permissions.AddAccessRule($access_rule)
                        Set-Acl -Path $path -AclObject $permissions
    
                        # Set farm properties
                        $f = Get-SPFarm
                        $f.Farm.Properties['SP-NonceCookieCertificateThumbprint']=$cert.Thumbprint
                        $f.Farm.Properties['SP-NonceCookieHMACSecretKey']='seed'
                        $f.Farm.Update()
                    }
                    GetScript =  
                    {
                        # This block must return a hashtable. The hashtable must only contain one key Result and the value must be of type String.
                        return @{ "Result" = "false" }
                    }
                    TestScript = 
                    {
                        # If it returns $false, the SetScript block will run. If it returns $true, the SetScript block will not run.
                        # Import-Module SharePointServer | Out-Null
                        # $f = Get-SPFarm
                        # if ($f.Farm.Properties.ContainsKey('SP-NonceCookieCertificateThumbprint') -eq $false) {
                        if ((Get-ChildItem -Path "cert:\LocalMachine\My\"| Where-Object{$_.Subject -eq "CN=SharePoint Cookie Cert"}) -eq $null) {
                            return $false
                        }
                        else {
                            return $true
                        }
                    }
                    DependsOn            = "[SPFarm]CreateSPFarm"
                    PsDscRunAsCredential = $SPSetupCredsQualified
                }        
    
                SPTrustedIdentityTokenIssuer CreateSPTrust
                {
                    Name                         = $DomainFQDN
                    Description                  = "Federation with $DomainFQDN"
                    RegisteredIssuerName         = "https://adfs.$DomainFQDN/adfs"
                    AuthorizationEndPointUri     = "https://adfs.$DomainFQDN/adfs/oauth2/authorize"
                    SignOutUrl                   = "https://adfs.$DomainFQDN/adfs/oauth2/logout"
                    DefaultClientIdentifier      = $AdfsOidcIdentifier
                    IdentifierClaim              = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"
                    ClaimsMappings               = @(
                        MSFT_SPClaimTypeMapping{
                            Name = "upn"
                            IncomingClaimType = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"
                        }
                        MSFT_SPClaimTypeMapping{
                            Name = "role"
                            IncomingClaimType = "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"
                        }
                    )
                    SigningCertificateFilePath   = "$SetupPath\Certificates\ADFS Signing.cer"
                    UseWReplyParameter           = $true
                    Ensure                       = "Present" 
                    DependsOn                    = "[xScript]SetOidcCertificate"
                    PsDscRunAsCredential         = $SPSetupCredsQualified
                }
            } else {
                SPTrustedIdentityTokenIssuer CreateSPTrust
                {
                    Name                         = $DomainFQDN
                    Description                  = "Federation with $DomainFQDN"
                    Realm                        = "urn:sharepoint:spsites"
                    SignInUrl                    = "https://adfs.$DomainFQDN/adfs/ls/"
                    IdentifierClaim              = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"
                    ClaimsMappings               = @(
                        MSFT_SPClaimTypeMapping{
                            Name = "upn"
                            IncomingClaimType = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"
                        }
                        MSFT_SPClaimTypeMapping{
                            Name = "Role"
                            IncomingClaimType = "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"
                        }
                    )
                    SigningCertificateFilePath   = "$SetupPath\Certificates\ADFS Signing.cer"
                    #ClaimProviderName           = "" # Should not be set if there is none
                    ProviderSignOutUri          = "https://adfs.$DomainFQDN/adfs/ls/"
                    UseWReplyParameter           = $true
                    Ensure                       = "Present"
                    DependsOn                    = "[SPFarm]CreateSPFarm"
                    PsDscRunAsCredential         = $SPSetupCredsQualified
                }
            }

            # Update GPO to ensure the root certificate of the CA is present in "cert:\LocalMachine\Root\", otherwise certificate request will fail
            xScript UpdateGPOToTrustRootCACert
            {
                SetScript =
                {
                    gpupdate.exe /force
                }
                GetScript            = { }
                TestScript           = 
                {
                    $domainNetbiosName = $using:DomainNetbiosName
                    $dcName = $using:DCName
                    $rootCAName = "$domainNetbiosName-$dcName-CA"
                    $cert = Get-ChildItem -Path "cert:\LocalMachine\Root\" -DnsName "$rootCAName"
                    
                    if ($null -eq $cert) {
                        return $false   # Run SetScript
                    } else {
                        return $true    # Root CA already present
                    }
                }
                DependsOn            = "[PendingReboot]RebootOnSignalFromJoinDomain"
                PsDscRunAsCredential = $DomainAdminCredsQualified
            }

            CertReq GenerateMainWebAppCertificate
            {
                CARootName             = "$DomainNetbiosName-$DCName-CA"
                CAServerFQDN           = "$DCName.$DomainFQDN"
                Subject                = "$SPTrustedSitesName.$DomainFQDN"
                SubjectAltName         = "dns=*.$DomainFQDN"
                KeyLength              = '2048'
                Exportable             = $true
                ProviderName           = '"Microsoft RSA SChannel Cryptographic Provider"'
                OID                    = '1.3.6.1.5.5.7.3.1'
                KeyUsage               = '0xa0'
                CertificateTemplate    = 'WebServer'
                AutoRenew              = $true
                Credential             = $DomainAdminCredsQualified
                DependsOn              = '[xScript]UpdateGPOToTrustRootCACert'
            }

            SPWebApplicationExtension ExtendMainWebApp
            {
                WebAppUrl              = "http://$SPTrustedSitesName/"
                Name                   = "SharePoint - 443"
                AllowAnonymous         = $false
                Url                    = "https://$SPTrustedSitesName.$DomainFQDN"
                Zone                   = "Intranet"
                Port                   = 443
                Ensure                 = "Present"
                PsDscRunAsCredential   = $SPSetupCredsQualified
                DependsOn              = "[CertReq]GenerateMainWebAppCertificate", "[SPWebApplication]CreateMainWebApp"
            }

            SPWebAppAuthentication ConfigureMainWebAppAuthentication
            {
                WebAppUrl = "http://$SPTrustedSitesName/"
                Default = @(
                    MSFT_SPWebAppAuthenticationMode {
                        AuthenticationMethod = "WindowsAuthentication"
                        WindowsAuthMethod    = "NTLM"
                    }
                )
                Intranet = @(
                    MSFT_SPWebAppAuthenticationMode {
                        AuthenticationMethod = "Federated"
                        AuthenticationProvider = $DomainFQDN
                    }
                )
                PsDscRunAsCredential = $SPSetupCredsQualified
                DependsOn            = "[SPWebApplicationExtension]ExtendMainWebApp"
            }

            xWebsite SetHTTPSCertificate
            {
                Name                 = "SharePoint - 443"
                BindingInfo          = MSFT_xWebBindingInformation
                {
                    Protocol             = "HTTPS"
                    Port                 = 443
                    CertificateStoreName = "My"
                    CertificateSubject   = "$SPTrustedSitesName.$DomainFQDN"
                }
                Ensure               = "Present"
                PsDscRunAsCredential = $DomainAdminCredsQualified
                DependsOn            = "[SPWebAppAuthentication]ConfigureMainWebAppAuthentication"
            }

            SPSite CreateRootSite
            {
                Url                  = "http://$SPTrustedSitesName/"
                OwnerAlias           = "i:0#.w|$DomainNetbiosName\$($DomainAdminCreds.UserName)"
                SecondaryOwnerAlias  = "i:0$TrustedIdChar.t|$DomainFQDN|$($DomainAdminCreds.UserName)@$DomainFQDN"
                Name                 = "Team site"
                Template             = $SPTeamSiteTemplate
                CreateDefaultGroups  = $true
                PsDscRunAsCredential = $SPSetupCredsQualified
                DependsOn            = "[SPWebApplication]CreateMainWebApp"
            }
        }
        else {
            SPWebAppAuthentication ConfigureMainWebAppAuthentication
            {
                WebAppUrl = "http://$SPTrustedSitesName/"
                Default = @(
                    MSFT_SPWebAppAuthenticationMode {
                        AuthenticationMethod = "WindowsAuthentication"
                        WindowsAuthMethod    = "NTLM"
                    }
                )
                PsDscRunAsCredential = $SPSetupCredsQualified
                DependsOn            = "[SPWebApplication]CreateMainWebApp"
            }

            SPSite CreateRootSite
            {
                Url                  = "http://$SPTrustedSitesName/"
                OwnerAlias           = "i:0#.w|$DomainNetbiosName\$($DomainAdminCreds.UserName)"
                Name                 = "Team site"
                Template             = $SPTeamSiteTemplate
                CreateDefaultGroups  = $true
                PsDscRunAsCredential = $SPSetupCredsQualified
                DependsOn            = "[SPWebApplication]CreateMainWebApp"
            }
        }

        # if ($EnableAnalysis) {
        #     # This resource is for analysis of dsc logs only and totally optionnal
        #     xScript parseDscLogs
        #     {
        #         TestScript = { return $false }
        #         SetScript = {
        #             $setupPath = $using:SetupPath
        #             $localScriptPath = "$setupPath\parse-dsc-logs.py"
        #             New-Item -ItemType Directory -Force -Path $setupPath

        #             $url = "https://gist.githubusercontent.com/Yvand/777a2e97c5d07198b926d7bb4f12ab04/raw/parse-dsc-logs.py"
        #             $downloader = New-Object -TypeName System.Net.WebClient
        #             $downloader.DownloadFile($url, $localScriptPath)

        #             $dscExtensionPath = "C:\WindowsAzure\Logs\Plugins\Microsoft.Powershell.DSC"
        #             $folderWithMaxVersionNumber = Get-ChildItem -Directory -Path $dscExtensionPath | Where-Object { $_.Name -match "^[\d\.]+$"} | Sort-Object -Descending -Property Name | Select-Object -First 1
        #             $fullPathToDscLogs = [System.IO.Path]::Combine($dscExtensionPath, $folderWithMaxVersionNumber)
                    
        #             python $localScriptPath "$fullPathToDscLogs"
        #         }
        #         GetScript = { }
        #         DependsOn            = "[cChocoPackageInstaller]InstallPython"
        #         PsDscRunAsCredential = $DomainAdminCredsQualified
        #     }
        # }
    }
}

function Get-NetBIOSName
{
    [OutputType([string])]
    param(
        [string]$DomainFQDN
    )

    if ($DomainFQDN.Contains('.')) {
        $length=$DomainFQDN.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainFQDN.Substring(0,$length)
    }
    else {
        if ($DomainFQDN.Length -gt 15) {
            return $DomainFQDN.Substring(0,15)
        }
        else {
            return $DomainFQDN
        }
    }
}

<#
# Azure DSC extension logging: C:\WindowsAzure\Logs\Plugins\Microsoft.Powershell.DSC\2.83.1.0
# Azure DSC extension configuration: C:\Packages\Plugins\Microsoft.Powershell.DSC\2.83.1.0\DSCWork

Install-Module -Name PendingReboot
help ConfigureSPVM

$DomainAdminCreds = Get-Credential -Credential "yvand"
$SPSetupCreds = Get-Credential -Credential "spsetup"
$SPFarmCreds = Get-Credential -Credential "spfarm"
$SPAppPoolCreds = Get-Credential -Credential "spapppool"
$SPPassphraseCreds = Get-Credential -Credential "Passphrase"
$DNSServer = "10.1.1.4"
$DomainFQDN = "contoso.local"
$DCName = "DC"
$SQLName = "SQL"
$SQLAlias = "SQLAlias"
$SharePointVersion = "2019"
$ConfigureADFS = $false
$EnableAnalysis = $true

$outputPath = "C:\Packages\Plugins\Microsoft.Powershell.DSC\2.83.2.0\DSCWork\ConfigureSPVM.0\ConfigureSPVM"
ConfigureSPVM -DomainAdminCreds $DomainAdminCreds -SPSetupCreds $SPSetupCreds -SPFarmCreds $SPFarmCreds -SPAppPoolCreds $SPAppPoolCreds -SPPassphraseCreds $SPPassphraseCreds -DNSServer $DNSServer -DomainFQDN $DomainFQDN -DCName $DCName -SQLName $SQLName -SQLAlias $SQLAlias -SharePointVersion $SharePointVersion -ConfigureADFS $ConfigureADFS -EnableAnalysis $EnableAnalysis -ConfigurationData @{AllNodes=@(@{ NodeName="localhost"; PSDscAllowPlainTextPassword=$true })} -OutputPath $outputPath
Set-DscLocalConfigurationManager -Path $outputPath
Start-DscConfiguration -Path $outputPath -Wait -Verbose -Force

#>
