function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $AppDomain,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Prefix
    )

    Write-Verbose -Message "Getting app domain settings"

    $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]
        $appDomain = Get-SPAppDomain
        $prefix = Get-SPAppSiteSubscriptionName -ErrorAction SilentlyContinue

        return @{
            AppDomain = $appDomain
            Prefix    = $prefix
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
        $AppDomain,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Prefix
    )

    Write-Verbose -Message "Setting app domain settings"

    Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]

        Set-SPAppDomain $params.AppDomain
        Set-SPAppSiteSubscriptionName -Name $params.Prefix -Confirm:$false
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
        $AppDomain,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Prefix
    )

    Write-Verbose -Message "Testing app domain settings"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @("AppDomain", "Prefix")

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

function Export-TargetResource
{
    $VerbosePreference = "SilentlyContinue"
    [System.Array]$serviceApp = Get-SPServiceApplication | Where-Object { $_.GetType().Name -eq "AppManagementServiceApplication" }
    $appDomain = Get-SPAppDomain
    if ($serviceApp.Length -ge 1 -and $appDomain.Length -ge 1)
    {
        $ParentModuleBase = Get-Module "SharePointDsc" -ListAvailable | Select-Object -ExpandProperty Modulebase
        $module = Join-Path -Path $ParentModuleBase -ChildPath  "\DSCResources\MSFT_SPAppDomain\MSFT_SPAppDomain.psm1" -Resolve
        $Content = ''
        $params = Get-DSCFakeParameters -ModulePath $module
        $PartialContent = "        SPAppDomain " + [System.Guid]::NewGuid().ToString() + "`r`n"
        $PartialContent += "        {`r`n"
        $results = Get-TargetResource @params
        $results = Repair-Credentials -results $results
        $currentBlock = Get-DSCBlock -Params $results -ModulePath $module
        $currentBlock = Convert-DSCStringParamToVariable -DSCBlock $currentBlock -ParameterName "PsDscRunAsCredential"
        $PartialContent += $currentBlock
        $PartialContent += "        }`r`n"
        $Content += $PartialContent
    }
    return $Content
}

Export-ModuleMember -Function *-TargetResource
