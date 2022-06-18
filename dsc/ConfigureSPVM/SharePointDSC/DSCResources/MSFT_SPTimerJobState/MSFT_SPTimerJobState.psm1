function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TypeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [Parameter()]
        [System.Boolean]
        $Enabled,

        [Parameter()]
        [System.String]
        $Schedule
    )

    Write-Verbose -Message "Getting timer job settings for job '$TypeName'"

    if ($TypeName -eq "Microsoft.SharePoint.Administration.Health.SPHealthAnalyzerJobDefinition")
    {
        $message = ("You cannot use SPTimerJobState to change the schedule of " + `
                "health analyzer timer jobs.")
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    $result = Invoke-SPDscCommand -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
        -ScriptBlock {
        $params = $args[0]
        $eventSource = $args[1]

        try
        {
            $null = Get-SPFarm
        }
        catch
        {
            $message = ("No local SharePoint farm was detected. Timer job " + `
                    "settings will not be applied")
            Add-SPDscEvent -Message $message `
                -EntryType 'Error' `
                -EventID 100 `
                -Source $eventSource
            throw $message
        }

        $returnval = @{
            TypeName = $params.TypeName
        }

        if ($params.WebAppUrl -ne "N/A")
        {
            $wa = Get-SPWebApplication -Identity $params.WebAppUrl -ErrorAction SilentlyContinue
            if ($null -eq $wa)
            {
                $message = ("Specified web application not found!")
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }

            $timerjob = Get-SPTimerJob -Type $params.TypeName `
                -WebApplication $wa

            if ($timerjob.Count -eq 0)
            {
                $message = ("No timer jobs found. Please check the input values")
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }

            $returnval.WebAppUrl = $params.WebAppUrl
            $returnval.Enabled = -not $timerjob.IsDisabled
            $returnval.Schedule = $null
            if ($null -ne $timerjob.Schedule)
            {
                $returnval.Schedule = $timerjob.Schedule.ToString()
            }
        }
        else
        {
            $timerjob = Get-SPTimerJob -Type $params.TypeName
            if ($timerjob.Count -eq 1)
            {
                $returnval.WebAppUrl = "N/A"
                $returnval.Enabled = -not $timerjob.IsDisabled
                $returnval.Schedule = $null
                if ($null -ne $timerjob.Schedule)
                {
                    $returnval.Schedule = $timerjob.Schedule.ToString()
                }
            }
            else
            {
                $message = ("$($timerjob.Count) timer jobs found. Check input " + `
                        "values or use the WebAppUrl parameter.")
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }
        }
        return $returnval
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
        $TypeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [Parameter()]
        [System.Boolean]
        $Enabled,

        [Parameter()]
        [System.String]
        $Schedule
    )

    Write-Verbose -Message "Setting timer job settings for job '$TypeName'"

    if ($TypeName -eq "Microsoft.SharePoint.Administration.Health.SPHealthAnalyzerJobDefinition")
    {
        $message = ("You cannot use SPTimerJobState to change the schedule of " + `
                "health analyzer timer jobs.")
        Add-SPDscEvent -Message $message `
            -EntryType 'Error' `
            -EventID 100 `
            -Source $MyInvocation.MyCommand.Source
        throw $message
    }

    Invoke-SPDscCommand -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
        -ScriptBlock {
        $params = $args[0]
        $eventSource = $args[1]

        try
        {
            $null = Get-SPFarm
        }
        catch
        {
            $message = "No local SharePoint farm was detected. Timer job settings will not be applied"
            Add-SPDscEvent -Message $message `
                -EntryType 'Error' `
                -EventID 100 `
                -Source $eventSource
            throw $message
        }

        Write-Verbose -Message "Start update"

        if ($params.WebAppUrl -ne "N/A")
        {
            $wa = Get-SPWebApplication -Identity $params.WebAppUrl -ErrorAction SilentlyContinue
            if ($null -eq $wa)
            {
                $message = "Specified web application not found!"
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }

            $timerjob = Get-SPTimerJob -Type $params.TypeName `
                -WebApplication $wa

            if ($timerjob.Count -eq 0)
            {
                $message = ("No timer jobs found. Please check the input values")
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }

            if ($params.ContainsKey("Schedule") -eq $true)
            {
                if ($params.Schedule -ne $timerjob.Schedule.ToString())
                {
                    try
                    {
                        Set-SPTimerJob -Identity $timerjob `
                            -Schedule $params.Schedule `
                            -ErrorAction Stop
                    }
                    catch
                    {
                        if ($_.Exception.Message -like `
                                "*The time given was not given in the proper format*")
                        {
                            $message = ("Incorrect schedule format used. New schedule will " + `
                                    "not be applied.")
                            Add-SPDscEvent -Message $message `
                                -EntryType 'Error' `
                                -EventID 100 `
                                -Source $eventSource
                            throw $message
                        }
                        else
                        {
                            $message = ("Error occurred. Timer job settings will not be applied. " + `
                                    "Error details: $($_.Exception.Message)")
                            Add-SPDscEvent -Message $message `
                                -EntryType 'Error' `
                                -EventID 100 `
                                -Source $eventSource
                            throw $message
                        }
                    }
                }
            }

            if ($params.ContainsKey("Enabled") -eq $true)
            {
                if ($params.Enabled -ne (-not $timerjob.IsDisabled))
                {
                    if ($params.Enabled)
                    {
                        Write-Verbose -Message "Enable timer job $($params.TypeName)"
                        try
                        {
                            Enable-SPTimerJob -Identity $timerjob
                        }
                        catch
                        {
                            $message = ("Error occurred while enabling job. Timer job settings will " + `
                                    "not be applied. Error details: $($_.Exception.Message)")
                            Add-SPDscEvent -Message $message `
                                -EntryType 'Error' `
                                -EventID 100 `
                                -Source $eventSource
                            throw $message
                        }
                    }
                    else
                    {
                        Write-Verbose -Message "Disable timer job $($params.Name)"
                        try
                        {
                            Disable-SPTimerJob -Identity $timerjob
                        }
                        catch
                        {
                            $message = ("Error occurred while disabling job. Timer job settings will " + `
                                    "not be applied. Error details: $($_.Exception.Message)")
                            Add-SPDscEvent -Message $message `
                                -EntryType 'Error' `
                                -EventID 100 `
                                -Source $eventSource
                            throw $message
                        }
                    }
                }
            }
        }
        else
        {
            $timerjob = Get-SPTimerJob -Type $params.TypeName
            if ($timerjob.Count -eq 1)
            {
                if ($params.ContainsKey("Schedule") -eq $true)
                {
                    if ($params.Schedule -ne $timerjob.Schedule.ToString())
                    {
                        try
                        {
                            Set-SPTimerJob -Identity $timerjob `
                                -Schedule $params.Schedule `
                                -ErrorAction Stop
                        }
                        catch
                        {
                            if ($_.Exception.Message -like `
                                    "*The time given was not given in the proper format*")
                            {
                                $message = ("Incorrect schedule format used. New schedule will " + `
                                        "not be applied.")
                                Add-SPDscEvent -Message $message `
                                    -EntryType 'Error' `
                                    -EventID 100 `
                                    -Source $eventSource
                                throw $message
                            }
                            else
                            {
                                $message = ("Error occurred. Timer job settings will not be applied. " + `
                                        "Error details: $($_.Exception.Message)")
                                Add-SPDscEvent -Message $message `
                                    -EntryType 'Error' `
                                    -EventID 100 `
                                    -Source $eventSource
                                throw $message
                            }
                        }
                    }
                }

                if ($params.ContainsKey("Enabled") -eq $true)
                {
                    if ($params.Enabled -ne -not $timerjob.IsDisabled)
                    {
                        if ($params.Enabled)
                        {
                            Write-Verbose -Message "Enable timer job $($params.TypeName)"
                            try
                            {
                                Enable-SPTimerJob -Identity $timerjob
                            }
                            catch
                            {
                                $message = ("Error occurred while enabling job. Timer job settings will " + `
                                        "not be applied. Error details: $($_.Exception.Message)")
                                Add-SPDscEvent -Message $message `
                                    -EntryType 'Error' `
                                    -EventID 100 `
                                    -Source $eventSource
                                throw $message
                            }
                        }
                        else
                        {
                            Write-Verbose -Message "Disable timer job $($params.Name)"
                            try
                            {
                                Disable-SPTimerJob -Identity $timerjob
                            }
                            catch
                            {
                                $message = ("Error occurred while disabling job. Timer job settings will " + `
                                        "not be applied. Error details: $($_.Exception.Message)")
                                Add-SPDscEvent -Message $message `
                                    -EntryType 'Error' `
                                    -EventID 100 `
                                    -Source $eventSource
                                throw $message
                            }
                        }
                    }
                }
            }
            else
            {
                $message = ("$($timerjob.Count) timer jobs found. Check input " + `
                        "values or use the WebAppUrl parameter.")
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
        $TypeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebAppUrl,

        [Parameter()]
        [System.Boolean]
        $Enabled,

        [Parameter()]
        [System.String]
        $Schedule
    )

    Write-Verbose -Message "Testing timer job settings for job '$TypeName'"

    if ($TypeName -eq "Microsoft.SharePoint.Administration.Health.SPHealthAnalyzerJobDefinition")
    {
        $message = ("You cannot use SPTimerJobState to change the schedule of " + `
                "health analyzer timer jobs.")
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
        -DesiredValues $PSBoundParameters

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

function Export-TargetResource
{
    $VerbosePreference = "SilentlyContinue"
    $ParentModuleBase = Get-Module "SharePointDsc" -ListAvailable | Select-Object -ExpandProperty Modulebase
    $module = Join-Path -Path $ParentModuleBase -ChildPath  "\DSCResources\MSFT_SPTimerJobState\MSFT_SPTimerJobState.psm1" -Resolve
    $Content = ''
    $params = Get-DSCFakeParameters -ModulePath $module

    $spTimers = Get-SPTimerJob
    $totalTimers = $spTimers.Length
    $i = 0;
    foreach ($timer in $spTimers)
    {
        try
        {
            $i++
            Write-Host "Scanning Timer Job {"$timer.Name"}[$i/$totalTimers]..."
            if ($null -ne $timer -and $timer.TypeName -ne "Microsoft.SharePoint.Administration.Health.SPHealthAnalyzerJobDefinition")
            {
                $PartialContent = ''

                $params.TypeName = $timer.TypeName
                if ($null -ne $timer.WebApplication)
                {
                    $params.WebAppUrl = $timer.WebApplication.Url;
                }
                else
                {
                    $params.WebAppUrl = "N/A";
                }

                $PartialContent = "        SPTimerJobState " + [System.Guid]::NewGuid().toString() + "`r`n"
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
            $Global:ErrorLog += "[Timer Job]" + $timer.TypeName + "`r`n"
            $Global:ErrorLog += "$_`r`n`r`n"
        }
    }
    return $Content
}

Export-ModuleMember -Function *-TargetResource
