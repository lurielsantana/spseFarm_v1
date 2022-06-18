function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Yes')]
        [String]
        $IsSingleInstance,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Compliant", "NonCompliant")]
        [System.String]
        $State
    )

    Write-Verbose -Message "Getting MinRole compliance for the current farm"

    $installedVersion = Get-SPDscInstalledProductVersion
    if ($installedVersion.FileMajorPart -ne 16)
    {
        $message = "MinRole is only supported in SharePoint 2016, 2019 and Subscription Edition."
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $nonCompliantServices = Get-SPService | Where-Object -FilterScript {
            $_.CompliantWithMinRole -eq $false
        }
        $params = $args[0];

        if ($null -eq $nonCompliantServices)
        {
            return @{
                IsSingleInstance = "Yes"
                State            = "Compliant"
            }
        }
        else
        {
            return @{
                IsSingleInstance = "Yes"
                State            = "NonCompliant"
            }
        }
    }
    return $result
}

function Get-SPDscRoleTestMethod
{
    $assembly = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")
    $type = $assembly.GetType("Microsoft.SharePoint.Administration.SPServerRoleManager")
    $flags = [Reflection.BindingFlags] "NonPublic,Static"
    return $type.GetMethod("IsCompliantWithMinRole", $flags)
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Yes')]
        [String]
        $IsSingleInstance,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Compliant", "NonCompliant")]
        [System.String]
        $State
    )

    Write-Verbose -Message "Setting MinRole compliance for the current farm"

    $installedVersion = Get-SPDscInstalledProductVersion
    if ($installedVersion.FileMajorPart -ne 16)
    {
        $message = "MinRole is only supported in SharePoint 2016, 2019 and Subscription Edition."
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    if ($State -eq "NonCompliant")
    {
        $message = ("State can only be configured to 'Compliant'. The 'NonCompliant' value is only " + `
                "used to report when the farm is not compliant")
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $method = Get-SPDscRoleTestMethod

        Get-SPService | Where-Object -FilterScript {
            $_.CompliantWithMinRole -eq $false
        } | ForEach-Object -Process {
            $_.Instances | ForEach-Object -Process {
                $isCompliant = $method.Invoke($null, $_)

                if ($isCompliant -eq $false)
                {
                    if ($_.Status -eq "Disabled")
                    {
                        Write-Verbose -Message "Starting service '$($_.TypeName)' on '$($_.Server.Name)'"
                        Start-SPServiceInstance -Identity $_.Id | Out-Null
                    }
                    if ($_.Status -eq "Online")
                    {
                        Write-Verbose -Message "Stopping service '$($_.TypeName)' on '$($_.Server.Name)'"
                        Stop-SPServiceInstance -Identity $_.Id -Confirm:$false | Out-Null
                    }
                }
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
        [ValidateSet('Yes')]
        [String]
        $IsSingleInstance,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Compliant", "NonCompliant")]
        [System.String]
        $State
    )

    Write-Verbose -Message "Testing MinRole compliance for the current farm"

    if ($State -eq "NonCompliant")
    {
        $message = ("State can only be configured to 'Compliant'. The 'NonCompliant' value is only " + `
                "used to report when the farm is not compliant")
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @("State")

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

Export-ModuleMember -Function Get-TargetResource, `
    Test-TargetResource, `
    Set-TargetResource, `
    Get-SPDscRoleTestMethod
