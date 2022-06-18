function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Url,

        [Parameter()]
        [System.String]
        $ProjectProfessionalMinBuildNumber,

        [Parameter()]
        [System.String]
        $ServerCurrency,

        [Parameter()]
        [System.Boolean]
        $EnforceServerCurrency
    )

    Write-Verbose -Message "Getting additional settings for $Url"

    if ((Get-SPDscInstalledProductVersion).FileMajorPart -lt 16)
    {
        $message = ("Support for Project Server in SharePointDsc is only valid for " + `
                "SharePoint 2016 and 2019.")
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    $result = Invoke-SPDscCommand -Arguments @($PSBoundParameters, $PSScriptRoot) `
        -ScriptBlock {
        $params = $args[0]
        $scriptRoot = $args[1]

        $modulePath = "..\..\Modules\SharePointDsc.ProjectServerConnector\SharePointDsc.ProjectServerConnector.psm1"
        Import-Module -Name (Join-Path -Path $scriptRoot -ChildPath $modulePath -Resolve)

        $webAppUrl = (Get-SPSite -Identity $params.Url).WebApplication.Url
        $useKerberos = -not (Get-SPAuthenticationProvider -WebApplication $webAppUrl -Zone Default).DisableKerberos
        $adminService = New-SPDscProjectServerWebService -PwaUrl $params.Url `
            -EndpointName Admin `
            -UseKerberos:$useKerberos

        $script:ProjectProfessionalMinBuildNumberValue = $null
        $script:ServerCurrencyValue = $null
        $script:EnforceServerCurrencyValue = $false
        Use-SPDscProjectServerWebService -Service $adminService -ScriptBlock {
            $buildInfo = $adminService.GetProjectProfessionalMinimumBuildNumbers().Versions
            $script:ProjectProfessionalMinBuildNumberValue = "$($buildInfo.Major).$($buildInfo.Minor).$($buildInfo.Build).$($buildInfo.Revision)"
            $script:ServerCurrencyValue = $adminService.GetServerCurrency()
            $script:EnforceServerCurrencyValue = $adminService.GetSingleCurrencyEnforced()
        }

        return @{
            Url                               = $params.Url
            ProjectProfessionalMinBuildNumber = $script:ProjectProfessionalMinBuildNumberValue
            ServerCurrency                    = $script:ServerCurrencyValue
            EnforceServerCurrency             = $script:EnforceServerCurrencyValue
        }
    }
    return $result
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Url,

        [Parameter()]
        [System.String]
        $ProjectProfessionalMinBuildNumber,

        [Parameter()]
        [System.String]
        $ServerCurrency,

        [Parameter()]
        [System.Boolean]
        $EnforceServerCurrency
    )

    Write-Verbose -Message "Setting additional settings for $Url"

    if ((Get-SPDscInstalledProductVersion).FileMajorPart -lt 16)
    {
        $message = ("Support for Project Server in SharePointDsc is only valid for " + `
                "SharePoint 2016 and 2019.")
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    Invoke-SPDscCommand -Arguments @($PSBoundParameters, $PSScriptRoot) `
        -ScriptBlock {
        $params = $args[0]
        $scriptRoot = $args[1]

        $modulePath = "..\..\Modules\SharePointDsc.ProjectServerConnector\SharePointDsc.ProjectServerConnector.psm1"
        Import-Module -Name (Join-Path -Path $scriptRoot -ChildPath $modulePath -Resolve)

        $webAppUrl = (Get-SPSite -Identity $params.Url).WebApplication.Url
        $useKerberos = -not (Get-SPAuthenticationProvider -WebApplication $webAppUrl -Zone Default).DisableKerberos
        $adminService = New-SPDscProjectServerWebService -PwaUrl $params.Url `
            -EndpointName Admin `
            -UseKerberos:$useKerberos

        Use-SPDscProjectServerWebService -Service $adminService -ScriptBlock {
            if ($params.ContainsKey("ProjectProfessionalMinBuildNumber") -eq $true)
            {
                $buildInfo = $adminService.GetProjectProfessionalMinimumBuildNumbers()
                $versionInfo = [System.Version]::New($params.ProjectProfessionalMinBuildNumber)
                $buildInfo.Versions.Rows[0]["Major"] = $versionInfo.Major
                $buildInfo.Versions.Rows[0]["Minor"] = $versionInfo.Minor
                $buildInfo.Versions.Rows[0]["Build"] = $versionInfo.Build
                $buildInfo.Versions.Rows[0]["Revision"] = $versionInfo.Revision
                $adminService.SetProjectProfessionalMinimumBuildNumbers($buildInfo)
            }

            if ($params.ContainsKey("ServerCurrency") -eq $true)
            {
                $adminService.SetServerCurrency($params.ServerCurrency)
            }

            if ($params.ContainsKey("EnforceServerCurrency") -eq $true)
            {
                $adminService.SetSingleCurrencyEnforced($params.EnforceServerCurrency)
            }
        }
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Url,

        [Parameter()]
        [System.String]
        $ProjectProfessionalMinBuildNumber,

        [Parameter()]
        [System.String]
        $ServerCurrency,

        [Parameter()]
        [System.Boolean]
        $EnforceServerCurrency
    )

    Write-Verbose -Message "Testing additional settings for $Url"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @(
        "ProjectProfessionalMinBuildNumber"
        "ServerCurrency",
        "EnforceServerCurrency"
    )

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

Export-ModuleMember -Function *-TargetResource
