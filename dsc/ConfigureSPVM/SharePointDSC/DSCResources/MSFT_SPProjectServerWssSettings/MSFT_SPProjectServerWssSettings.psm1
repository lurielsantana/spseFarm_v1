function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Url,

        [Parameter(Mandatory = $true)]
        [ValidateSet("AutoCreate", "UserChoice", "DontCreate")]
        [System.String]
        $CreateProjectSiteMode
    )

    Write-Verbose -Message "Getting WSS settings for $Url"

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
        $wssService = New-SPDscProjectServerWebService -PwaUrl $params.Url `
            -EndpointName WssInterop `
            -UseKerberos:$useKerberos

        $script:currentValue = $null
        Use-SPDscProjectServerWebService -Service $wssService -ScriptBlock {
            $settings = $wssService.ReadWssSettings()
            if ($null -ne $settings)
            {
                $script:currentValue = $settings.WssAdmin.WADMIN_AUTO_CREATE_SUBWEBS
            }
        }

        $currentValue = "Unknown"
        if ($null -ne $script:currentValue)
        {
            switch ($script:currentValue)
            {
                0
                {
                    $currentValue = "UserChoice"
                }
                1
                {
                    $currentValue = "AutoCreate"
                }
                2
                {
                    $currentValue = "DontCreate"
                }
            }
        }

        return @{
            Url                   = $params.Url
            CreateProjectSiteMode = $currentValue
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

        [Parameter(Mandatory = $true)]
        [ValidateSet("AutoCreate", "UserChoice", "DontCreate")]
        [System.String]
        $CreateProjectSiteMode
    )

    Write-Verbose -Message "Setting WSS settings for $Url"

    Invoke-SPDscCommand -Arguments @($PSBoundParameters, $PSScriptRoot) `
        -ScriptBlock {
        $params = $args[0]
        $scriptRoot = $args[1]

        $modulePath = "..\..\Modules\SharePointDsc.ProjectServerConnector\SharePointDsc.ProjectServerConnector.psm1"
        Import-Module -Name (Join-Path -Path $scriptRoot -ChildPath $modulePath -Resolve)

        $webAppUrl = (Get-SPSite -Identity $params.Url).WebApplication.Url
        $useKerberos = -not (Get-SPAuthenticationProvider -WebApplication $webAppUrl -Zone Default).DisableKerberos
        $wssService = New-SPDscProjectServerWebService -PwaUrl $params.Url `
            -EndpointName WssInterop `
            -UseKerberos:$useKerberos

        Use-SPDscProjectServerWebService -Service $wssService -ScriptBlock {
            $settings = $wssService.ReadWssSettings()

            switch ($params.CreateProjectSiteMode)
            {
                "UserChoice"
                {
                    $settings.WssAdmin.Rows[0]["WADMIN_AUTO_CREATE_SUBWEBS"] = 0
                }
                "AutoCreate"
                {
                    $settings.WssAdmin.Rows[0]["WADMIN_AUTO_CREATE_SUBWEBS"] = 1
                }
                "DontCreate"
                {
                    $settings.WssAdmin.Rows[0]["WADMIN_AUTO_CREATE_SUBWEBS"] = 2
                }
            }
            $wssService.UpdateWssSettings($settings)
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

        [Parameter(Mandatory = $true)]
        [ValidateSet("AutoCreate", "UserChoice", "DontCreate")]
        [System.String]
        $CreateProjectSiteMode
    )

    Write-Verbose -Message "Testing WSS settings for $Url"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

Export-ModuleMember -Function *-TargetResource
