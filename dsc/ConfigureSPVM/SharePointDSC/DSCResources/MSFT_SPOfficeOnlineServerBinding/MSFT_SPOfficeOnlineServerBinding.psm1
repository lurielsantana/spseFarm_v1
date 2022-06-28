function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Internal-HTTP", "Internal-HTTPS", "External-HTTP", "External-HTTPS")]
        [System.String]
        $Zone,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DnsName,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    Write-Verbose -Message "Getting Office Online Server details for '$Zone' zone"

    $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]

        $currentZone = Get-SPWOPIZone
        $bindings = Get-SPWOPIBinding -WOPIZone $currentZone

        if ($null -eq $bindings)
        {
            return @{
                Zone    = $currentZone
                DnsName = $null
                Ensure  = "Absent"
            }
        }
        else
        {
            return @{
                Zone    = $currentZone
                DnsName = ($bindings | Select-Object -First 1).ServerName
                Ensure  = "Present"
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
        [ValidateSet("Internal-HTTP", "Internal-HTTPS", "External-HTTP", "External-HTTPS")]
        [System.String]
        $Zone,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DnsName,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    Write-Verbose -Message "Setting Office Online Server details for '$Zone' zone"

    $CurrentResults = Get-TargetResource @PSBoundParameters

    if ($Ensure -eq "Present")
    {
        if ($DnsName -ne $CurrentResults.DnsName -or $Zone -ne $CurrentResults.Zone)
        {
            if ([String]::IsNullOrEmpty($CurrentResults.DnsName) -eq $false `
                    -or $Zone -ne $CurrentResults.Zone)
            {
                Write-Verbose -Message ("Removing bindings for zone '$Zone' so new bindings " + `
                        "can be added")
                Invoke-SPDscCommand -Arguments $PSBoundParameters `
                    -ScriptBlock {
                    $params = $args[0]
                    Get-SPWOPIBinding -WOPIZone $params.Zone | Remove-SPWOPIBinding -Confirm:$false
                }
            }
            Write-Verbose -Message "Creating new bindings for '$DnsName' and setting zone to '$Zone'"
            Invoke-SPDscCommand -Arguments $PSBoundParameters `
                -ScriptBlock {
                $params = $args[0]

                $newParams = @{
                    ServerName = $params.DnsName
                }
                if ($params.Zone.ToLower().EndsWith("http") -eq $true)
                {
                    $newParams.Add("AllowHTTP", $true)
                }
                New-SPWOPIBinding @newParams
                Set-SPWOPIZone -zone $params.Zone
            }
        }
    }

    if ($Ensure -eq "Absent")
    {
        Write-Verbose -Message "Removing bindings for zone '$Zone'"
        Invoke-SPDscCommand -Arguments $PSBoundParameters `
            -ScriptBlock {
            $params = $args[0]
            Get-SPWOPIBinding -WOPIZone $params.Zone | Remove-SPWOPIBinding -Confirm:$false
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
        [ValidateSet("Internal-HTTP", "Internal-HTTPS", "External-HTTP", "External-HTTPS")]
        [System.String]
        $Zone,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DnsName,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    Write-Verbose -Message "Testing Office Online Server details for '$Zone' zone"

    $PSBoundParameters.Ensure = $Ensure

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $paramsToCheck = @("Ensure")
    if ($Ensure -eq "Present")
    {
        $paramsToCheck += @("Zone", "DnsName")
    }
    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck $paramsToCheck

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

function Export-TargetResource
{
    $VerbosePreference = "SilentlyContinue"
    $WOPIZone = Get-SPWOPIZone
    $bindings = Get-SPWOPIBinding  -WOPIZone $WOPIZone
    try
    {
        if ($null -ne $bindings)
        {
            $ParentModuleBase = Get-Module "SharePointDsc" -ListAvailable | Select-Object -ExpandProperty Modulebase
            $module = Join-Path -Path $ParentModuleBase -ChildPath  "\DSCResources\MSFT_SPOfficeOnlineServerBinding\MSFT_SPOfficeOnlineServerBinding.psm1" -Resolve
            $Content = ''
            $params = Get-DSCFakeParameters -ModulePath $module

            $PartialContent = "        SPOfficeOnlineServerBinding " + [System.Guid]::NewGuid().ToString() + "`r`n"
            $PartialContent += "        {`r`n"
            $results = Get-TargetResource @params
            $results = Repair-Credentials -results $results
            $currentBlock = Get-DSCBlock -Params $results -ModulePath $module
            $currentBlock = Convert-DSCStringParamToVariable -DSCBlock $currentBlock -ParameterName "PsDscRunAsCredential"
            $PartialContent += $currentBlock
            $PartialContent += "        }`r`n"
            $Content += $PartialContent
        }
    }
    catch
    {
        $Global:ErrorLog += "[Office Online Server Binding]`r`n"
        $Global:ErrorLog += "$_`r`n`r`n"
    }
    return $Content
}

Export-ModuleMember -Function *-TargetResource
