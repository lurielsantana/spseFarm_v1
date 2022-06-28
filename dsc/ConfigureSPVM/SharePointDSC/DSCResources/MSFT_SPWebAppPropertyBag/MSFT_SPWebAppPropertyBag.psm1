function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.HashTable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Key,

        [Parameter()]
        [System.String]
        $Value,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = 'Present'
    )

    Write-Verbose -Message "Looking for SPWebApplication property '$Key'"

    $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]

        $spWebApp = Get-SPWebApplication -Identity $params.WebAppUrl -ErrorAction SilentlyContinue

        if ($null -eq $spWebApp)
        {
            $currentValue = $null
            $localEnsure = 'Absent'
        }
        else
        {
            if ($spWebApp.Properties)
            {
                if ($spWebApp.Properties.Contains($params.Key) -eq $true)
                {
                    $localEnsure = "Present"
                    $currentValue = $spWebApp.Properties[$params.Key]
                }
                else
                {
                    $localEnsure = "Absent"
                    $currentValue = $null
                }
            }
        }

        return @{
            WebAppUrl = $params.WebAppUrl
            Key       = $params.Key
            Value     = $currentValue
            Ensure    = $localEnsure
        }
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
        $WebAppUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Key,

        [Parameter()]
        [System.String]
        $Value,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = 'Present'
    )

    Write-Verbose -Message "Setting SPWebApplication property '$Key'"

    Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]

        $spWebApp = Get-SPWebApplication -Identity $params.WebAppUrl -ErrorAction SilentlyContinue

        if ($params.Ensure -eq 'Present')
        {
            Write-Verbose -Message "Adding property '$($params.Key)'='$($params.value)' to SPWebApplication.Properties"
            $spWebApp.Properties[$params.Key] = $params.Value
            $spWebApp.Update()
        }
        else
        {
            Write-Verbose -Message "Removing property '$($params.Key)' from SPWebApplication.Properties"
            $spWebApp.Properties.Remove($params.Key)
            $spWebApp.Update()
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
        $WebAppUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Key,

        [Parameter()]
        [System.String]
        $Value,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = 'Present'
    )

    Write-Verbose -Message "Testing SPWebApplication property '$Key'"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    if ($Ensure -eq 'Present')
    {
        $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
            -Source $($MyInvocation.MyCommand.Source) `
            -DesiredValues $PSBoundParameters `
            -ValuesToCheck @('Ensure', 'Key', 'Value')
    }
    else
    {
        $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
            -Source $($MyInvocation.MyCommand.Source) `
            -DesiredValues $PSBoundParameters `
            -ValuesToCheck @('Ensure', 'Key')

    }

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

Export-ModuleMember -Function *-TargetResource
