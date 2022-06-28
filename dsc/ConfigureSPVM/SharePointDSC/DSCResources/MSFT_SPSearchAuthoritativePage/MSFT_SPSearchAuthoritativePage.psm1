function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ServiceAppName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [System.Single]
        $Level,

        [Parameter()]
        [ValidateSet("Authoratative", "Demoted")]
        [System.String]
        $Action,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure
    )

    Write-Verbose -Message "Getting Authoratative Page Setting for '$Path'"

    $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]

        $nullReturn = @{
            ServiceAppName = $params.ServiceAppName
            Path           = ""
            Level          = $params.Level
            Action         = $params.Action
            Ensure         = "Absent"
        }

        $serviceApp = Get-SPEnterpriseSearchServiceApplication -Identity $params.ServiceAppName
        if ($null -eq $serviceApp)
        {
            return $nullReturn
        }

        $searchObjectLevel = [Microsoft.Office.Server.Search.Administration.SearchObjectLevel]::Ssa
        $searchOwner = New-Object -TypeName "Microsoft.Office.Server.Search.Administration.SearchObjectOwner" -ArgumentList $searchObjectLevel

        if ($params.Action -eq "Authoratative")
        {
            $queryAuthority = Get-SPEnterpriseSearchQueryAuthority -Identity $params.Path `
                -Owner $searchOwner `
                -SearchApplication $serviceApp `
                -ErrorAction SilentlyContinue
            if ($null -eq $queryAuthority)
            {
                return $nullReturn
            }
            else
            {

                return @{
                    ServiceAppName = $params.ServiceAppName
                    Path           = $params.Path
                    Level          = $queryAuthority.Level
                    Action         = $params.Action
                    Ensure         = "Present"
                }
            }
        }
        else
        {
            $queryDemoted = Get-SPEnterpriseSearchQueryDemoted -Identity $params.Path `
                -Owner $searchOwner `
                -SearchApplication $serviceApp `
                -ErrorAction SilentlyContinue
            if ($null -eq $queryDemoted)
            {
                return $nullReturn
            }
            else
            {
                return @{
                    ServiceAppName = $params.ServiceAppName
                    Path           = $params.Path
                    Action         = $params.Action
                    Ensure         = "Present"
                }
            }
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
        $ServiceAppName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [System.Single]
        $Level,

        [Parameter()]
        [ValidateSet("Authoratative", "Demoted")]
        [System.String]
        $Action,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure
    )

    Write-Verbose -Message "Setting Authoratative Page Settings for '$Path'"

    $CurrentResults = Get-TargetResource @PSBoundParameters

    if ($CurrentResults.Ensure -eq "Absent" -and $Ensure -eq "Present")
    {
        $null = Invoke-SPDscCommand -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
            -ScriptBlock {
            $params = $args[0]
            $eventSource = $args[1]

            $serviceApp = Get-SPEnterpriseSearchServiceApplication -Identity $params.ServiceAppName
            $searchObjectLevel = [Microsoft.Office.Server.Search.Administration.SearchObjectLevel]::Ssa
            $searchOwner = New-Object -TypeName "Microsoft.Office.Server.Search.Administration.SearchObjectOwner" -ArgumentList $searchObjectLevel

            if ($null -eq $serviceApp)
            {
                $message = "Search Service App was not available."
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }
            if ($params.Action -eq "Authoratative")
            {
                New-SPEnterpriseSearchQueryAuthority -Url $params.Path `
                    -SearchApplication $serviceApp `
                    -Owner $searchOwner `
                    -Level $params.Level
            }
            else
            {
                New-SPEnterpriseSearchQueryDemoted -Url $params.Path -SearchApplication $serviceApp -Owner $searchOwner
            }
        }
    }
    if ($CurrentResults.Ensure -eq "Present" -and $Ensure -eq "Present")
    {
        $null = Invoke-SPDscCommand -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
            -ScriptBlock {
            $params = $args[0]
            $eventSource = $args[1]

            $serviceApp = Get-SPEnterpriseSearchServiceApplication -Identity $params.ServiceAppName
            $searchObjectLevel = [Microsoft.Office.Server.Search.Administration.SearchObjectLevel]::Ssa
            $searchOwner = New-Object -TypeName "Microsoft.Office.Server.Search.Administration.SearchObjectOwner" -ArgumentList $searchObjectLevel

            if ($null -eq $serviceApp)
            {
                $message = "Search Service App was not available."
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }

            if ($params.Action -eq "Authoratative")
            {
                Set-SPEnterpriseSearchQueryAuthority -Identity $params.ServiceAppName `
                    -SearchApplication $serviceApp `
                    -Owner $searchOwner `
                    -Level $params.Level
            }
        }
    }
    if ($Ensure -eq "Absent")
    {
        $null = Invoke-SPDscCommand -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
            -ScriptBlock {
            $params = $args[0]
            $eventSource = $args[1]

            $serviceApp = Get-SPEnterpriseSearchServiceApplication -Identity $params.ServiceAppName
            $searchObjectLevel = [Microsoft.Office.Server.Search.Administration.SearchObjectLevel]::Ssa
            $searchOwner = New-Object -TypeName "Microsoft.Office.Server.Search.Administration.SearchObjectOwner" -ArgumentList $searchObjectLevel

            if ($null -eq $serviceApp)
            {
                $message = "Search Service App was not available."
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }
            if ($params.Action -eq "Authoratative")
            {
                Remove-SPEnterpriseSearchQueryAuthority -Identity $params.ServiceAppName `
                    -SearchApplication $serviceApp `
                    -Owner $searchOwner `
                    -ErrorAction SilentlyContinue
            }
            else
            {
                Remove-SPEnterpriseSearchQueryDemoted -Identity $params.ServiceAppName `
                    -SearchApplication $serviceApp `
                    -Owner $searchOwner `
                    -ErrorAction SilentlyContinue
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
        $ServiceAppName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [System.Single]
        $Level,

        [Parameter()]
        [ValidateSet("Authoratative", "Demoted")]
        [System.String]
        $Action,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure
    )

    Write-Verbose -Message "Testing Authoratative Page Settings '$Path'"

    $PSBoundParameters.Ensure = $Ensure

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    if ($Ensure -eq "Present")
    {
        if ($Action -eq "Authoratative")
        {
            $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
                -Source $($MyInvocation.MyCommand.Source) `
                -DesiredValues $PSBoundParameters `
                -ValuesToCheck @("ServiceAppName",
                "Path",
                "Level",
                "Action",
                "Ensure")
        }
        else
        {
            $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
                -Source $($MyInvocation.MyCommand.Source) `
                -DesiredValues $PSBoundParameters `
                -ValuesToCheck @("ServiceAppName",
                "Path",
                "Action",
                "Ensure")
        }
    }
    else
    {
        $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
            -Source $($MyInvocation.MyCommand.Source) `
            -DesiredValues $PSBoundParameters `
            -ValuesToCheck @("ServiceAppName",
            "Action",
            "Ensure")
    }

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

Export-ModuleMember -Function *-TargetResource
