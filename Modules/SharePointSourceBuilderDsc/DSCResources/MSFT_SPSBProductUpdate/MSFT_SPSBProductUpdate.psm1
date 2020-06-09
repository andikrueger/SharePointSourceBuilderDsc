function Get-TargetRessource
{
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Yes')]
        [System.String]
        $IsSingleInstance,

        [Parameter(Mandatory = $true)]
        [ValidateSet("SP2013", "ProjectServer2013", "SP2016", "SP2019")]
        [System.String]
        $ProductName,

        [Parameter(Mandatory = $true)]
        [System.String[]]
        $Patches,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TargetDirectory,

        [Parameter()]
        [ValidateSet("Present")]
        [System.String]
        $Ensure = "Present"
    )

    $returnValue = @{
        ProductName     = $ProductName
        Patches         = @()
        TargetDirectory = $TargetDirectory
        Ensure          = "Absent"
    }

    $baseDirectory = Join-Path $TargetDirectory -ChildPath $ProductName

    if (-not(Test-Path $baseDirectory))
    {
        $returnValue.TargetDirectory = $null
        return $returnValue
    }
    else
    {
        $folders = Get-ChildItem $baseDirectory -Directory
        if (-not($null -eq $folders) -and $folders.Count -gt 0)
        {
            $returnValue.Ensure = "Present"
            $folders | ForEach-Object -Process {
                $returnValue.Patches += $_.Name
            }
        }
    }

    return $returnValue
}
function Set-TargetRessource
{
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Yes')]
        [System.String]
        $IsSingleInstance,

        [Parameter(Mandatory = $true)]
        [ValidateSet("SP2013", "ProjectServer2013", "SP2016", "SP2019")]
        [System.String]
        $ProductName,

        [Parameter(Mandatory = $true)]
        [System.String[]]
        $Patches,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TargetDirectory,

        [Parameter()]
        [ValidateSet("Present")]
        [System.String]
        $Ensure = "Present"
    )

    $currentValues = Get-TargetRessource @PSBoundParameters

    $baseDirectory = Join-Path $TargetDirectory -ChildPath $ProductName

    if ($null -eq $currentValues.TargetDirectory)
    {
        New-Item -Path $baseDirectory -ItemType Directory -Force
    }

    $differences = Compare-Object -ReferenceObject $currentValues.Patches `
        -DifferenceObject $Patches

    if ($null -eq $differences)
    {
        Write-Verbose -Message "Patches do match. No further processing required."
    }
    else
    {
        Write-Verbose -Message "Patches do not match. PErforming corrective action."
        foreach ($difference in $differences)
        {
            $patch = $differences.InputObject

            $path = Join-Path -Path $baseDirectory -ChildPath $patch

            if (-not(Test-Path -Path $path))
            {
                New-Item -Path $path -ItemType Directory -Force
            }

            if ($difference.SideINdicator -eq "=>")
            {
                $patchDetails = Get-SPSBDscPatchDetail -ProductName $ProductName -PatchName $patch
                if ($null -eq $patchDetails)
                {
                    Write-Warning -Message "There was no patch found for '$patch'"
                    break
                }

                foreach ($patchDetail in $patchDetails)
                {
                    Start-SPSBDscFileTransfer -Destination $path -Source $patchDetail.Url -ExpandedFile $patchDetail.ExpandedFile
                    $filePath = Join-Path -Path $path -ChildPath $languagePackDetail.ExpandedFile
                    Remove-ReadOnlyAttribute -Path $filePath
                }

                foreach($patchDetail in $patchDetails)
                {
                    if($patchDetail.ExpandedFile.EndsWith(".exe"))
                    {
                        $sourcePath = Join-Path $path -ChildPath $patchDetail.ExpandedFile
                        $targetPath = Join-Path $path -ChildPath "Patch"

                        New-Item -Path $targetPath -ItemType Directory -Force

                        Expand-SPSBDscPatchFileToFolder -SourcePath $sourcePath -TargetPath $targetPath
                    }
                }
            }
        }
    }
}

function Test-TargetRessource
{
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Yes')]
        [System.String]
        $IsSingleInstance,

        [Parameter(Mandatory = $true)]
        [ValidateSet("SP2013", "ProjectServer2013", "SP2016", "SP2019")]
        [System.String]
        $ProductName,

        [Parameter(Mandatory = $true)]
        [System.String[]]
        $Patches,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TargetDirectory,

        [Parameter()]
        [ValidateSet("Present")]
        [System.String]
        $Ensure = "Present"
    )

    $currentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPSBDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPSBDscHashtableToString -Hashtable $PSBoundParameters)"

    $valuesToCheck = $PSBoundParameters.Keys
    if (-not($PSBoundParameters.ContainsKey("Ensure")))
    {
        $valuesToCheck += "Ensure"
    }

    $testResult = Test-SPSBDscParameterState -CurrentValues $currentValues `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck $valuesToCheck

    return $testResult
}

Export-ModuleMember -Function *-TargetResource
