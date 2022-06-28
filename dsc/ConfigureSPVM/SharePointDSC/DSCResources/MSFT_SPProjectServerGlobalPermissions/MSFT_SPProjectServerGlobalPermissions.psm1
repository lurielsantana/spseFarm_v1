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
        [System.String]
        $EntityName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("User", "Group")]
        [System.String]
        $EntityType,

        [Parameter()]
        [System.String[]]
        $AllowPermissions,

        [Parameter()]
        [System.String[]]
        $DenyPermissions
    )

    Write-Verbose -Message "Getting global permissions for $EntityType '$EntityName' at '$Url'"

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

    $result = Invoke-SPDscCommand -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source, $PSScriptRoot) `
        -ScriptBlock {
        $params = $args[0]
        $eventSource = $args[1]
        $scriptRoot = $args[2]

        if ((Get-SPProjectPermissionMode -Url $params.Url) -ne "ProjectServer")
        {
            $message = ("SPProjectServerGlobalPermissions is designed for Project Server " + `
                    "permissions mode only, and this site is set to SharePoint mode")
            Add-SPDscEvent -Message $message `
                -EntryType 'Error' `
                -EventID 100 `
                -Source $eventSource
            throw $message
        }

        $modulePath = "..\..\Modules\SharePointDsc.ProjectServerConnector\SharePointDsc.ProjectServerConnector.psm1"
        Import-Module -Name (Join-Path -Path $scriptRoot -ChildPath $modulePath -Resolve)

        $allowPermissions = @()
        $denyPermissions = @()
        $script:resultDataSet = $null

        switch ($params.EntityType)
        {
            "User"
            {
                $webAppUrl = (Get-SPSite -Identity $params.Url).WebApplication.Url
                $useKerberos = -not (Get-SPAuthenticationProvider -WebApplication $webAppUrl -Zone Default).DisableKerberos
                $resourceService = New-SPDscProjectServerWebService -PwaUrl $params.Url `
                    -EndpointName Resource `
                    -UseKerberos:$useKerberos

                $userId = Get-SPDscProjectServerResourceId -PwaUrl $params.Url -ResourceName $params.EntityName
                Use-SPDscProjectServerWebService -Service $resourceService -ScriptBlock {
                    $script:resultDataSet = $resourceService.ReadResourceAuthorization($userId)
                }
            }
            "Group"
            {
                $webAppUrl = (Get-SPSite -Identity $params.Url).WebApplication.Url
                $useKerberos = -not (Get-SPAuthenticationProvider -WebApplication $webAppUrl -Zone Default).DisableKerberos
                $securityService = New-SPDscProjectServerWebService -PwaUrl $params.Url `
                    -EndpointName Security `
                    -UseKerberos:$useKerberos

                Use-SPDscProjectServerWebService -Service $securityService -ScriptBlock {
                    $groupInfo = $securityService.ReadGroupList().SecurityGroups | Where-Object -FilterScript {
                        $_.WSEC_GRP_NAME -eq $params.EntityName
                    }
                    $script:resultDataSet = $securityService.ReadGroup($groupInfo.WSEC_GRP_UID)
                }
            }
        }

        $script:resultDataSet.GlobalPermissions.Rows | ForEach-Object -Process {
            $permissionName = Get-SPDscProjectServerPermissionName -PermissionId $_.WSEC_FEA_ACT_UID
            if ($_.WSEC_ALLOW -eq $true)
            {
                $allowPermissions += $permissionName
            }
            if ($_.WSEC_DENY -eq $true)
            {
                $denyPermissions += $permissionName
            }
        }

        return @{
            Url              = $params.Url
            EntityName       = $params.EntityName
            EntityType       = $params.EntityType
            AllowPermissions = $allowPermissions
            DenyPermissions  = $denyPermissions
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
        [System.String]
        $EntityName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("User", "Group")]
        [System.String]
        $EntityType,

        [Parameter()]
        [System.String[]]
        $AllowPermissions,

        [Parameter()]
        [System.String[]]
        $DenyPermissions
    )

    Write-Verbose -Message "Setting global permissions for $EntityType '$EntityName' at '$Url'"

    $currentValues = Get-TargetResource @PSBoundParameters

    $result = Invoke-SPDscCommand -Arguments @($PSBoundParameters, $PSScriptRoot, $currentValues) `
        -ScriptBlock {
        $params = $args[0]
        $scriptRoot = $args[1]
        $currentValues = $args[2]

        $modulePath = "..\..\Modules\SharePointDsc.ProjectServerConnector\SharePointDsc.ProjectServerConnector.psm1"
        Import-Module -Name (Join-Path -Path $scriptRoot -ChildPath $modulePath -Resolve)


        $allowPermsToAdd = @()
        $allowPermsToRemove = @()
        $denyPermsToAdd = @()
        $denyPermsToRemove = @()

        if ($params.ContainsKey("AllowPermissions") -eq $true)
        {
            $allowPermsDifference = Compare-Object -ReferenceObject $currentValues.AllowPermissions `
                -DifferenceObject $params.AllowPermissions

            $allowPermsDifference | ForEach-Object -Process {
                $diff = $_
                switch ($diff.SideIndicator)
                {
                    "<="
                    {
                        $allowPermsToRemove += $diff.InputObject
                    }
                    "=>"
                    {
                        $allowPermsToAdd += $diff.InputObject
                    }
                }
            }
        }
        if ($params.ContainsKey("DenyPermissions") -eq $true)
        {
            $denyPermsDifference = Compare-Object -ReferenceObject $currentValues.DenyPermissions `
                -DifferenceObject $params.DenyPermissions

            $denyPermsDifference | ForEach-Object -Process {
                $diff = $_
                switch ($diff.SideIndicator)
                {
                    "<="
                    {
                        $denyPermsToRemove += $diff.InputObject
                    }
                    "=>"
                    {
                        $denyPermsToAdd += $diff.InputObject
                    }
                }
            }
        }

        switch ($params.EntityType)
        {
            "User"
            {
                $webAppUrl = (Get-SPSite -Identity $params.Url).WebApplication.Url
                $useKerberos = -not (Get-SPAuthenticationProvider -WebApplication $webAppUrl -Zone Default).DisableKerberos
                $resourceService = New-SPDscProjectServerWebService -PwaUrl $params.Url `
                    -EndpointName Resource `
                    -UseKerberos:$useKerberos

                $userId = Get-SPDscProjectServerResourceId -PwaUrl $params.Url -ResourceName $params.EntityName
                Use-SPDscProjectServerWebService -Service $resourceService -ScriptBlock {
                    $dataSet = $resourceService.ReadResourceAuthorization($userId)

                    $allowPermsToAdd | ForEach-Object -Process {
                        $permissionId = Get-SPDscProjectServerGlobalPermissionId -PermissionName $_
                        $row = $dataSet.GlobalPermissions.NewGlobalPermissionsRow()
                        $row.RES_UID = $userId
                        $row.WSEC_FEA_ACT_UID = $permissionId
                        $row.WSEC_ALLOW = $true
                        $row.WSEC_DENY = $false
                        $dataSet.GlobalPermissions.AddGlobalPermissionsRow($row)
                    }

                    $allowPermsToRemove | ForEach-Object -Process {
                        $permissionId = Get-SPDscProjectServerGlobalPermissionId -PermissionName $_
                        $row = $dataSet.GlobalPermissions.FindByWSEC_FEA_ACT_UIDRES_UID($permissionId, $userId)
                        $row.Delete()
                    }

                    $denyPermsToAdd | ForEach-Object -Process {
                        $permissionId = Get-SPDscProjectServerGlobalPermissionId -PermissionName $_
                        $row = $dataSet.GlobalPermissions.NewGlobalPermissionsRow()
                        $row.RES_UID = $userId
                        $row.WSEC_FEA_ACT_UID = $permissionId
                        $row.WSEC_ALLOW = $false
                        $row.WSEC_DENY = $true
                        $dataSet.GlobalPermissions.AddGlobalPermissionsRow($row)
                    }

                    $denyPermsToRemove | ForEach-Object -Process {
                        $permissionId = Get-SPDscProjectServerGlobalPermissionId -PermissionName $_
                        $row = $dataSet.GlobalPermissions.FindByWSEC_FEA_ACT_UIDRES_UID($permissionId, $userId)
                        $row.Delete()
                    }

                    $resourceService.UpdateResources($dataSet, $false, $true)
                }
            }
            "Group"
            {
                $webAppUrl = (Get-SPSite -Identity $params.Url).WebApplication.Url
                $useKerberos = -not (Get-SPAuthenticationProvider -WebApplication $webAppUrl -Zone Default).DisableKerberos
                $securityService = New-SPDscProjectServerWebService -PwaUrl $params.Url `
                    -EndpointName Security `
                    -UseKerberos:$useKerberos

                Use-SPDscProjectServerWebService -Service $securityService -ScriptBlock {
                    $groupInfo = $securityService.ReadGroupList().SecurityGroups | Where-Object -FilterScript {
                        $_.WSEC_GRP_NAME -eq $params.EntityName
                    }
                    $dataSet = $securityService.ReadGroup($groupInfo.WSEC_GRP_UID)

                    $allowPermsToAdd | ForEach-Object -Process {
                        $permissionId = Get-SPDscProjectServerGlobalPermissionId -PermissionName $_
                        $row = $dataSet.GlobalPermissions.NewGlobalPermissionsRow()
                        $row.WSEC_GRP_UID = $groupInfo.WSEC_GRP_UID
                        $row.WSEC_FEA_ACT_UID = $permissionId
                        $row.WSEC_ALLOW = $true
                        $row.WSEC_DENY = $false
                        $dataSet.GlobalPermissions.AddGlobalPermissionsRow($row)
                    }

                    $allowPermsToRemove | ForEach-Object -Process {
                        $permissionId = Get-SPDscProjectServerGlobalPermissionId -PermissionName $_
                        $row = $dataSet.GlobalPermissions.FindByWSEC_FEA_ACT_UIDWSEC_GRP_UID($permissionId, $groupInfo.WSEC_GRP_UID)
                        $row.Delete()
                    }

                    $denyPermsToAdd | ForEach-Object -Process {
                        $permissionId = Get-SPDscProjectServerGlobalPermissionId -PermissionName $_
                        $row = $dataSet.GlobalPermissions.NewGlobalPermissionsRow()
                        $row.WSEC_GRP_UID = $groupInfo.WSEC_GRP_UID
                        $row.WSEC_FEA_ACT_UID = $permissionId
                        $row.WSEC_ALLOW = $false
                        $row.WSEC_DENY = $true
                        $dataSet.GlobalPermissions.AddGlobalPermissionsRow($row)
                    }

                    $denyPermsToRemove | ForEach-Object -Process {
                        $permissionId = Get-SPDscProjectServerGlobalPermissionId -PermissionName $_
                        $row = $dataSet.GlobalPermissions.FindByWSEC_FEA_ACT_UIDWSEC_GRP_UID($permissionId, $groupInfo.WSEC_GRP_UID)
                        $row.Delete()
                    }

                    $securityService.SetGroups($dataSet)
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
        [System.String]
        $Url,

        [Parameter(Mandatory = $true)]
        [System.String]
        $EntityName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("User", "Group")]
        [System.String]
        $EntityType,

        [Parameter()]
        [System.String[]]
        $AllowPermissions,

        [Parameter()]
        [System.String[]]
        $DenyPermissions
    )

    Write-Verbose -Message "Testing global permissions for $EntityType '$EntityName' at '$Url'"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @(
        "AllowPermissions",
        "DenyPermissions"
    )

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

Export-ModuleMember -Function *-TargetResource
