function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.HashTable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $RemoteWebAppUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $LocalWebAppUrl,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String] $Ensure = "Present"
    )

    Write-Verbose -Message "Getting remote farm trust '$Name'"

    $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]

        $returnValue = @{
            Name            = $params.Name
            RemoteWebAppUrl = $params.RemoteWebAppUrl
            LocalWebAppUrl  = $params.LocalWebAppUrl
            Ensure          = "Absent"
        }

        $issuer = Get-SPTrustedSecurityTokenIssuer -Identity $params.Name `
            -ErrorAction SilentlyContinue
        if ($null -eq $issuer)
        {
            return $returnValue
        }
        $rootAuthority = Get-SPTrustedRootAuthority -Identity $params.Name `
            -ErrorAction SilentlyContinue
        if ($null -eq $rootAuthority)
        {
            return $returnValue
        }
        $realm = $issuer.NameId.Split("@")
        $site = Get-SPSite -Identity $params.LocalWebAppUrl
        $serviceContext = Get-SPServiceContext -Site $site
        $currentRealm = Get-SPAuthenticationRealm -ServiceContext $serviceContext

        if ($realm[1] -ne $currentRealm)
        {
            return $returnValue
        }
        $returnValue.Ensure = "Present"
        return $returnValue
    }
    return $result
}

function Set-TargetResource()
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $RemoteWebAppUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $LocalWebAppUrl,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String] $Ensure = "Present"
    )

    Write-Verbose -Message "Setting remote farm trust '$Name'"

    if ($Ensure -eq "Present")
    {
        Write-Verbose -Message "Adding remote farm trust '$Name'"

        Invoke-SPDscCommand -Arguments $PSBoundParameters `
            -ScriptBlock {
            $params = $args[0]
            $remoteWebApp = $params.RemoteWebAppUrl.TrimEnd('/')

            $issuer = Get-SPTrustedSecurityTokenIssuer -Identity $params.Name `
                -ErrorAction SilentlyContinue
            if ($null -eq $issuer)
            {
                $endpoint = "$remoteWebApp/_layouts/15/metadata/json/1"
                $issuer = New-SPTrustedSecurityTokenIssuer -Name $params.Name `
                    -IsTrustBroker:$false `
                    -MetadataEndpoint $endpoint `
                    -Confirm:$false
            }

            $rootAuthority = Get-SPTrustedRootAuthority -Identity $params.Name `
                -ErrorAction SilentlyContinue
            if ($null -eq $rootAuthority)
            {
                $endpoint = "$remoteWebApp/_layouts/15/metadata/json/1/rootcertificate"
                New-SPTrustedRootAuthority -Name $params.Name `
                    -MetadataEndPoint $endpoint `
                    -Confirm:$false
            }
            $realm = $issuer.NameId.Split("@")
            $site = Get-SPSite -Identity $params.LocalWebAppUrl
            $serviceContext = Get-SPServiceContext -Site $site
            $currentRealm = Get-SPAuthenticationRealm -ServiceContext $serviceContext `
                -ErrorAction SilentlyContinue

            if ($realm[1] -ne $currentRealm)
            {
                Set-SPAuthenticationRealm -ServiceContext $serviceContext -Realm $realm[1]
            }

            $appPrincipal = Get-SPAppPrincipal -Site $params.LocalWebAppUrl `
                -NameIdentifier $issuer.NameId

            Set-SPAppPrincipalPermission -Site $params.LocalWebAppUrl `
                -AppPrincipal $appPrincipal `
                -Scope SiteCollection `
                -Right FullControl
        }
    }

    if ($Ensure -eq "Absent")
    {
        Write-Verbose -Message "Removing remote farm trust '$Name'"

        Invoke-SPDscCommand -Arguments $PSBoundParameters `
            -ScriptBlock {
            $params = $args[0]

            $issuer = Get-SPTrustedSecurityTokenIssuer -Identity $params.Name `
                -ErrorAction SilentlyContinue
            if ($null -ne $issuer)
            {
                $appPrincipal = Get-SPAppPrincipal -Site $params.LocalWebAppUrl `
                    -NameIdentifier $issuer.NameId
                Remove-SPAppPrincipalPermission -Site $params.LocalWebAppUrl `
                    -AppPrincipal $appPrincipal `
                    -Scope SiteCollection `
                    -Confirm:$false
            }

            Get-SPTrustedRootAuthority -Identity $params.Name `
                -ErrorAction SilentlyContinue `
            | Remove-SPTrustedRootAuthority -Confirm:$false
            if ($null -ne $issuer)
            {
                $issuer | Remove-SPTrustedSecurityTokenIssuer -Confirm:$false
            }
        }
    }
}

function Test-TargetResource()
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $RemoteWebAppUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $LocalWebAppUrl,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String] $Ensure = "Present"
    )

    Write-Verbose -Message "Testing remote farm trust '$Name'"

    $PSBoundParameters.Ensure = $Ensure

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @("Ensure")

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

function Export-TargetResource
{
    $VerbosePreference = "SilentlyContinue"
    $ParentModuleBase = Get-Module "SharePointDsc" -ListAvailable | Select-Object -ExpandProperty Modulebase
    $module = Join-Path -Path $ParentModuleBase -ChildPath  "\DSCResources\MSFT_SPRemoteFarmTrust\MSFT_SPRemoteFarmTrust.psm1" -Resolve
    $Content = ''
    $params = Get-DSCFakeParameters -ModulePath $module
    $tips = Get-SPTrustedSecurityTokenIssuer
    foreach ($tip in $tips)
    {
        $params.Name = $tip.Id
        $was = Get-SPWebApplication
        foreach ($wa in $was)
        {
            $site = Get-SPSite $wa.Url -ErrorAction SilentlyContinue
            if ($null -ne $site)
            {
                $params.LocalWebAppUrl = $wa.Url
                $results = Get-TargetResource @params
                if ($results.Ensure -eq "Present")
                {
                    $PartialContent = "        SPRemoteFarmTrust " + [System.Guid]::NewGuid().ToString() + "`r`n"
                    $PartialContent += "        {`r`n"
                    $results = Repair-Credentials -results $results
                    $currentBlock = Get-DSCBlock -Params $results -ModulePath $module
                    $currentBlock = Convert-DSCStringParamToVariable -DSCBlock $currentBlock -ParameterName "PsDscRunAsCredential"
                    $PartialContent += $currentBlock
                    $PartialContent += "        }`r`n"
                    $Content += $PartialContent
                }
            }
        }
    }
    return $Content
}

Export-ModuleMember -Function *-TargetResource
