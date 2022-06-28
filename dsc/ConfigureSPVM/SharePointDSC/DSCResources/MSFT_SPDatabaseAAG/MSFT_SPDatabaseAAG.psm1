function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AGName,

        [Parameter()]
        [System.String]
        $FileShare,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    Write-Verbose -Message "Getting AAG configuration for $DatabaseName"

    # Check if the April 2014 CU has been installed. The cmdlets have been added in this CU
    if ((Get-SPDscInstalledProductVersion).FileMajorPart -eq 15 `
            -and (Get-SPDscInstalledProductVersion).FileBuildPart -lt 4605)
    {
        $message = ("Adding databases to SQL Always-On Availability Groups " + `
                "require the SharePoint 2013 April 2014 CU to be installed. " + `
                "http://support.microsoft.com/kb/2880551")
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    if ($Ensure -eq "Present")
    {
        Write-Verbose -Message "Database(s) must be included in AAG $AGName"
        $result = Invoke-SPDscCommand -Arguments ($PSBoundParameters) `
            -ScriptBlock {
            $params = $args[0]

            $Ensure = "Present"
            $databases = Get-SPDatabase | Where-Object -FilterScript {
                $_.Name -like $params.DatabaseName
            }

            $dbname = $params.DatabaseName
            if ($null -ne $databases)
            {
                foreach ($database in $databases)
                {
                    $ag = $database.AvailabilityGroup
                    if ($null -ne $ag)
                    {
                        if ($ag.Name -ne $params.AGName)
                        {
                            $Ensure = "Absent"
                        }
                    }
                    else
                    {
                        $Ensure = "Absent"
                    }
                }
            }
            else
            {
                Write-Verbose -Message "Specified database(s) not found."
                $dbname = ""
            }

            return @{
                DatabaseName = $dbname
                AGName       = $params.AGName
                FileShare    = $params.FileShare
                Ensure       = $Ensure
            }
        }
    }
    else
    {
        Write-Verbose -Message "Database(s) must not be included in an AAG $AGName"
        $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
            -ScriptBlock {
            $params = $args[0]

            $Ensure = "Absent"
            $databases = Get-SPDatabase | Where-Object -FilterScript {
                $_.Name -like $params.DatabaseName
            }

            $dbname = $params.DatabaseName
            if ($null -ne $databases)
            {
                foreach ($database in $databases)
                {
                    $ag = $database.AvailabilityGroup
                    if ($null -ne $ag)
                    {
                        $Ensure = "Present"
                    }
                }
            }
            else
            {
                Write-Verbose -Message "Specified database(s) not found."
                $dbname = ""
            }

            return @{
                DatabaseName = $dbname
                AGName       = $params.AGName
                FileShare    = $params.FileShare
                Ensure       = $Ensure
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
        $DatabaseName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AGName,

        [Parameter()]
        [System.String]
        $FileShare,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    Write-Verbose -Message "Setting AAG configuration for $DatabaseName"

    # Check if the April 2014 CU has been installed. The cmdlets have been added in this CU
    if ((Get-SPDscInstalledProductVersion).FileMajorPart -eq 15 `
            -and (Get-SPDscInstalledProductVersion).FileBuildPart -lt 4605)
    {
        $message = ("Adding databases to SQL Always-On Availability Groups " + `
                "require the SharePoint 2013 April 2014 CU to be installed. " + `
                "http://support.microsoft.com/kb/2880551")
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    if ($Ensure -eq "Present")
    {
        Write-Verbose -Message "Checking AAG settings for $DatabaseName"
        Invoke-SPDscCommand -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
            -ScriptBlock {
            $params = $args[0]
            $eventSource = $args[1]

            # Check for SPSE, where cmdlets are renamed
            if ((Get-SPDscInstalledProductVersion).FileMajorPart -eq 16 -and `
                (Get-SPDscInstalledProductVersion).FileBuildPart -gt 13000)
            {
                $addCmd = 'Add-SPDatabaseToAvailabilityGroup'
                $removeCmd = 'Remove-SPDatabaseFromAvailabilityGroup'
            }
            else
            {
                $addCmd = 'Add-DatabaseToAvailabilityGroup'
                $removeCmd = 'Remove-DatabaseFromAvailabilityGroup'
            }

            $databases = Get-SPDatabase | Where-Object -FilterScript {
                $_.Name -like $params.DatabaseName
            }

            if ($null -ne $databases)
            {
                foreach ($database in $databases)
                {
                    $ag = $database.AvailabilityGroup
                    if ($null -ne $ag)
                    {
                        if ($ag.Name -ne $params.AGName)
                        {
                            # Remove it from the current AAG first
                            &$removeCmd -AGName $params.AGName `
                                -DatabaseName $database.Name `
                                -Force

                            # Now add it to the AAG it's meant to be in
                            $addParams = @{
                                AGName       = $params.AGName
                                DatabaseName = $database.Name
                            }
                            if ($params.ContainsKey("FileShare"))
                            {
                                $addParams.Add("FileShare", $params.FileShare)
                            }
                            &$addCmd @addParams
                        }
                    }
                    else
                    {
                        Write-Verbose -Message "Adding $DatabaseName to $AGName"
                        $cmdParams = @{
                            AGName       = $params.AGName
                            DatabaseName = $database.Name
                        }
                        if ($params.ContainsKey("FileShare"))
                        {
                            $cmdParams.Add("FileShare", $params.FileShare)
                        }
                        &$addCmd @cmdParams
                    }
                }
            }
            else
            {
                $message = "Specified database(s) not found."
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }
        }
    }
    else
    {
        Write-Verbose -Message "Removing $DatabaseName from $AGName"
        Invoke-SPDscCommand -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
            -ScriptBlock {
            $params = $args[0]
            $eventSource = $args[1]

            # Check for SPSE, where cmdlets are renamed
            if ((Get-SPDscInstalledProductVersion).FileMajorPart -eq 16 -and `
                (Get-SPDscInstalledProductVersion).FileBuildPart -gt 13000)
            {
                $removeCmd = 'Remove-SPDatabaseFromAvailabilityGroup'
            }
            else
            {
                $removeCmd = 'Remove-DatabaseFromAvailabilityGroup'
            }

            $databases = Get-SPDatabase | Where-Object -FilterScript {
                $_.Name -like $params.DatabaseName
            }

            if ($null -ne $databases)
            {
                foreach ($database in $databases)
                {
                    &$removeCmd -AGName $params.AGName `
                        -DatabaseName $database.Name `
                        -Force
                }
            }
            else
            {
                $message = "Specified database(s) not found."
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
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
        $DatabaseName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AGName,

        [Parameter()]
        [System.String]
        $FileShare,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    Write-Verbose -Message "Testing AAG configuration for $DatabaseName"

    $PSBoundParameters.Ensure = $Ensure

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @("Ensure", "DatabaseName")

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

function Export-TargetResource
{
    $VerbosePreference = "SilentlyContinue"
    $ParentModuleBase = Get-Module "SharePointDsc" -ListAvailable | Select-Object -ExpandProperty Modulebase
    $module = Join-Path -Path $ParentModuleBase -ChildPath  "\DSCResources\MSFT_SPDatabaseAAG\MSFT_SPDatabaseAAG.psm1" -Resolve
    $Content = ''
    $params = Get-DSCFakeParameters -ModulePath $module
    $databases = Get-SPDatabase
    foreach ($database in $databases)
    {
        try
        {
            if ($null -ne $database.AvailabilityGroup)
            {
                $PartialContent = "        SPDatabaseAAG " + [System.Guid]::NewGuid().ToString() + "`r`n"
                $PartialContent += "        {`r`n"
                $params.DatabaseName = $database.Name
                $params.AGName = $database.AvailabilityGroup
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
            $Global:ErrorLog += "[Database AvailabilityGroup]" + $database.Name + "`r`n"
            $Global:ErrorLog += "$_`r`n`r`n"
        }
    }
    return $Content
}

Export-ModuleMember -Function *-TargetResource
