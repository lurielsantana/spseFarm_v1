function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $LiteralPath,

        [Parameter()]
        [System.String[]]
        $WebAppUrls = @(),

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter()]
        [System.String]
        $Version = "1.0.0.0",

        [Parameter()]
        [System.Boolean]
        $Deployed = $true,

        [Parameter()]
        [ValidateSet("14", "15", "All")]
        [System.String]
        $SolutionLevel
    )

    Write-Verbose -Message "Getting farm solution '$Name' settings"

    $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]

        $solution = Get-SPSolution -Identity $params.Name `
            -ErrorAction SilentlyContinue `
            -Verbose:$false

        if ($null -ne $solution)
        {
            $currentState = "Present"
            $deployed = $solution.Deployed
            $version = $Solution.Properties["Version"]
            $deployedWebApplications = @($solution.DeployedWebApplications `
                | Select-Object -ExpandProperty Url)
        }
        else
        {
            $currentState = "Absent"
            $deployed = $false
            $version = "0.0.0.0"
            $deployedWebApplications = @()
        }

        return @{
            Name          = $params.Name
            LiteralPath   = $LiteralPath
            Deployed      = $deployed
            Ensure        = $currentState
            Version       = $version
            WebAppUrls    = $deployedWebApplications
            SolutionLevel = $params.SolutionLevel
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
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $LiteralPath,

        [Parameter()]
        [System.String[]]
        $WebAppUrls = @(),

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter()]
        [System.String]
        $Version = "1.0.0.0",

        [Parameter()]
        [System.Boolean]
        $Deployed = $true,

        [Parameter()]
        [ValidateSet("14", "15", "All")]
        [System.String]
        $SolutionLevel
    )

    Write-Verbose -Message "Setting farm solution '$Name' settings"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    $PSBoundParameters.Ensure = $Ensure
    $PSBoundParameters.Version = $Version
    $PSBoundParameters.Deployed = $Deployed

    if ($Ensure -eq "Present")
    {
        if ($CurrentValues.Ensure -eq "Absent")
        {
            Write-Verbose -Message "Upload solution to the farm."

            $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
                -ScriptBlock {
                $params = $args[0]

                $runParams = @{ }
                $runParams.Add("LiteralPath", $params.LiteralPath)
                $runParams.Add("Verbose", $false)

                $solution = Add-SPSolution @runParams

                $solution.Properties["Version"] = $params.Version
                $solution.Update()

                return $solution
            }

            $CurrentValues.Version = $result.Properties["Version"]
        }

        if ($CurrentValues.Version -ne $Version)
        {
            # If the solution is not deployed and the versions do not match we have to
            # remove the current solution and add the new one
            if (-not $CurrentValues.Deployed)
            {
                Write-Verbose -Message ("Remove current version " + `
                        "('$($CurrentValues.Version)') of solution...")

                $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
                    -ScriptBlock {
                    $params = $args[0]

                    $runParams = @{ }
                    $runParams.Add("Identity", $params.Name)
                    $runParams.Add("Confirm", $false)
                    $runParams.Add("Verbose", $false)

                    Remove-SPSolution $runParams

                    $runParams = @{ }
                    $runParams.Add("LiteralPath", $params.LiteralPath)

                    $solution = Add-SPSolution @runParams

                    $solution.Properties["Version"] = $params.Version
                    $solution.Update()

                    return $solution
                }

                $CurrentValues.Version = $result.Properties["Version"]
            }
            else
            {
                Write-Verbose -Message ("Update solution from " + `
                        "'$($CurrentValues.Version)' to $Version...")

                $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
                    -ScriptBlock {
                    $params = $args[0]

                    $solution = Get-SPSolution -Identity $params.Name -Verbose:$false

                    $runParams = @{ }
                    $runParams.Add("Identity", $params.Name)
                    $runParams.Add("LiteralPath", $params.LiteralPath)
                    $runParams.Add("GACDeployment", $solution.ContainsGlobalAssembly)
                    $runParams.Add("Confirm", $false)
                    $runParams.Add("Local", $false)
                    $runParams.Add("Verbose", $false)

                    Update-SPSolution @runParams

                    $solution = Get-SPSolution -Identity $params.Name -Verbose:$false
                    $solution.Properties["Version"] = $params.Version
                    $solution.Update()

                    # Install new features...
                    Install-SPFeature -AllExistingFeatures -Confirm:$false
                }
            }
        }

    }
    else
    {
        # If ensure is absent we should also retract the solution first
        $Deployed = $false
    }

    if ($Deployed -ne $CurrentValues.Deployed)
    {
        Write-Verbose -Message ("The deploy state of $Name is " + `
                "'$($CurrentValues.Deployed)' but should be '$Deployed'.")
        if ($CurrentValues.Deployed)
        {
            # Retract Solution globally
            $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
                -ScriptBlock {
                $params = $args[0]

                $runParams = @{ }
                $runParams.Add("Identity", $params.Name)
                $runParams.Add("Confirm", $false)
                $runParams.Add("Verbose", $false)

                $solution = Get-SPSolution -Identity $params.Name -Verbose:$false

                if ($solution.ContainsWebApplicationResource)
                {
                    if ($null -eq $params.WebAppUrls -or $params.WebAppUrls.Length -eq 0)
                    {
                        $runParams.Add("AllWebApplications", $true)

                        Uninstall-SPSolution @runParams
                    }
                    else
                    {
                        foreach ($webApp in $params.WebAppUrls)
                        {
                            $runParams["WebApplication"] = $webApp

                            Uninstall-SPSolution @runParams
                        }
                    }
                }
                else
                {
                    Uninstall-SPSolution @runParams
                }
            }
        }
        else
        {
            # Deploy solution
            $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
                -ScriptBlock {
                $params = $args[0]

                $solution = Get-SPSolution -Identity $params.Name -Verbose:$false

                $runParams = @{
                    Identity      = $solution
                    GACDeployment = $solution.ContainsGlobalAssembly
                    Local         = $false
                    Verbose       = $false
                }
                if ($params.ContainsKey("SolutionLevel") -eq $true)
                {
                    $runParams.Add("CompatibilityLevel", $params.SolutionLevel)
                }

                if (!$solution.ContainsWebApplicationResource)
                {
                    Install-SPSolution @runParams
                }
                else
                {
                    if ($null -eq $params.WebAppUrls -or $params.WebAppUrls.Length -eq 0)
                    {
                        $runParams.Add("AllWebApplications", $true)

                        Install-SPSolution @runParams
                    }
                    else
                    {
                        foreach ($webApp in $params.WebAppUrls)
                        {
                            $runParams["WebApplication"] = $webApp

                            try
                            {
                                Write-Verbose "Installing solution in Web Application $webApp"
                                Install-SPSolution @runParams -ErrorAction Stop
                            }
                            catch
                            {
                                # There may be an ongoing deployment to another web application location.
                                # Try the exponential backoff approach.
                                $backOff = 2
                                while ($backOff -le 256)
                                {
                                    try
                                    {
                                        Write-Verbose "There is an active deployment ongoing. Waiting $backOff seconds."
                                        Start-Sleep -Seconds $backOff
                                        Install-SPSolution @runParams -ErrorAction Stop
                                        break
                                    }
                                    catch
                                    {
                                        $backOff = $backOff * 2
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if ($Ensure -eq "Present")
    {
        Write-Verbose -Message "Waiting for farm solution '$Name' job"
        Wait-SPDscSolutionJob -SolutionName $Name
    }

    if ($Ensure -eq "Absent" -and $CurrentValues.Ensure -ne "Absent")
    {
        Write-Verbose -Message "Removing farm solution '$Name'"

        $result = Invoke-SPDscCommand -Arguments $PSBoundParameters `
            -ScriptBlock {
            $params = $args[0]

            $runParams = @{
                Identity = $params.Name
                Confirm  = $false
                Verbose  = $false
            }

            Remove-SPSolution @runParams

        }
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $LiteralPath,

        [Parameter()]
        [System.String[]]
        $WebAppUrls = @(),

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter()]
        [System.String]
        $Version = "1.0.0.0",

        [Parameter()]
        [System.Boolean]
        $Deployed = $true,

        [Parameter()]
        [ValidateSet("14", "15", "All")]
        [System.String]
        $SolutionLevel
    )

    Write-Verbose -Message "Testing farm solution '$Name' settings"

    $PSBoundParameters.Ensure = $Ensure

    $CurrentValues = Get-TargetResource @PSBoundParameters
    if ($CurrentValues.ContainsKey("WebAppUrls") -and $CurrentValues.WebAppUrls.Count -ne 0)
    {
        $CurrentValues.WebAppUrls = $CurrentValues.WebAppUrls.TrimEnd("/")
    }

    if ($PSBoundParameters.ContainsKey("WebAppUrls") -and $PSBoundParameters.WebAppUrls.Count -ne 0)
    {
        $PSBoundParameters.WebAppUrls = $PSBoundParameters.WebAppUrls.TrimEnd("/")
    }

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $valuesToCheck = @("Ensure", "Version", "Deployed")
    if ($WebAppUrls.Count -gt 0)
    {
        $valuesToCheck += "WebAppUrls"
    }

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck $valuesToCheck

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

function Wait-SPDscSolutionJob
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $SolutionName
    )

    Start-Sleep -Seconds 5

    $args = @{
        Name = $SolutionName
    }

    $null = Invoke-SPDscCommand -Arguments $args `
        -ScriptBlock {
        $params = $args[0]

        $gc = Start-SPAssignment -Verbose:$false

        $solution = Get-SPSolution -Identity $params.Name -Verbose:$false -AssignmentCollection $gc

        if ($solution.JobExists -eq $true)
        {
            Write-Verbose -Message "Waiting for solution '$($params.Name)'..."
            $loopCount = 0
            while ($solution.JobExists -and $loopCount -lt 600)
            {
                $solution = Get-SPSolution -Identity $params.Name -Verbose:$false -AssignmentCollection $gc

                Write-Verbose -Message ("$([DateTime]::Now.ToShortTimeString()) - Waiting for a " + `
                        "job for solution '$($params.Name)' to complete")
                $loopCount++
                Start-Sleep -Seconds 5

            }

            Write-Verbose -Message "Result: $($solution.LastOperationResult)"
            Write-Verbose -Message "Details: $($solution.LastOperationDetails)"
        }
        else
        {
            Write-Verbose -Message "Solution '$($params.Name)' has no job pending."
            return @{
                LastOperationResult  = "DeploymentSucceeded"
                LastOperationDetails = "Solution '$($params.Name)' has no job pending."
            }
        }

        Stop-SPAssignment $gc -Verbose:$false

        return @{
            LastOperationResult  = $solution.LastOperationResult
            LastOperationDetails = $solution.LastOperationDetails
        }
    }
}

function Export-TargetResource
{
    $VerbosePreference = "SilentlyContinue"
    $ParentModuleBase = Get-Module "SharePointDsc" -ListAvailable | Select-Object -ExpandProperty Modulebase
    $module = Join-Path -Path $ParentModuleBase -ChildPath  "\DSCResources\MSFT_SPFarmSolution\MSFT_SPFarmSolution.psm1" -Resolve
    $Content = ''
    $params = Get-DSCFakeParameters -ModulePath $module
    $solutions = Get-SPSolution

    $i = 1
    $total = $solutions.Length
    foreach ($solution in $solutions)
    {
        try
        {
            Write-Host "Scanning Solution [$i/$total] {$($solution.Name)}"
            $PartialContent = "        SPFarmSolution " + [System.Guid]::NewGuid().ToString() + "`r`n"
            $PartialContent += "        {`r`n"
            $params.Name = $solution.Name
            $results = Get-TargetResource @params
            if ($results.ContainsKey("ContainsGlobalAssembly"))
            {
                $results.Remove("ContainsGlobalAssembly")
            }
            $filePath = "`$AllNodes.Where{`$Null -ne `$_.SPSolutionPath}.SPSolutionPath+###" + $solution.Name + "###"
            $results["LiteralPath"] = $filePath
            $results = Repair-Credentials -results $results

            $currentBlock = Get-DSCBlock -Params $results -ModulePath $module
            $currentblock = Convert-DSCStringParamToVariable -DSCBlock $currentBlock -ParameterName "LiteralPath"
            $currentBlock = Convert-DSCStringParamToVariable -DSCBlock $currentBlock -ParameterName "PsDscRunAsCredential"
            $currentBlock = $currentBlock.Replace("###", "`"")
            $PartialContent += $currentBlock

            $PartialContent += "        }`r`n"

            $Content += $PartialContent
        }
        catch
        {
            $_
            $Global:ErrorLog += "[Farm Solution]" + $solution.Name + "`r`n"
            $Global:ErrorLog += "$_`r`n`r`n"
        }
        $i++
    }
    return $Content
}

Export-ModuleMember -Function *-TargetResource
