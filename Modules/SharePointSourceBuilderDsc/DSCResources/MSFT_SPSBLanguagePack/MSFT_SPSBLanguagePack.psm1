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
        $Languages,

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
        Languages       = @()
        TargetDirectory = $TargetDirectory
        Ensure          = "Absent"
    }

    if (-not(Test-Path -Path $TargetDirectory))
    {
        $returnValue.TargetDirectory = $null
        return $returnValue
    }
    else
    {
        $baseDirectory = Join-Path $TargetDirectory -ChildPath $ProductName

        $folders = Get-ChildItem $baseDirectory -Directory
        if (-not($null -eq $folders) -and $folders.Count -gt 0)
        {
            $folders | ForEach-Object -Process {
                $cultures = [System.Globalization.CultureInfo]::GetCultureInfo([System.Globalization.CultureTypes]::SpecificCultures)

                $isValidCulture = $false

                foreach ($culture in $cultures)
                {
                    if ($culture.Name -eq $_.Name)
                    {
                        $isValidCulture = $true

                        $languagePackDetail = Get-SPSBDscLanguagePackDetail -ProductName $ProductName -Language $_.Name
                        if ($null -eq $languagePackDetail)
                        {
                            Write-Warning -Message "No language pack available for culture '$_.Name'"
                        }
                        else
                        {
                            if (Test-Path -Path (Join-Path $_ -ChildPath $languagePackDetail.ExpandedFile))
                            {
                                if ($languagePackDetail.ExpandedFile.EndsWith(".img"))
                                {
                                    if ((Get-ChildItem $_ -Directory).Count -eq 1)
                                    {
                                        $returnValue.Languages += $_.Name
                                    }
                                }
                                else
                                {
                                    $returnValue.Languages += $_.Name
                                }
                                break
                            }
                        }
                    }
                }

                if (-not($isValidCulture))
                {
                    Write-Warning -Message "'$_.Name' is not a valid culture."
                }
            }
        }

        if ($returValue.Languages.Count -gt 0)
        {
            $returnValue.Ensure = "Present"
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
        $Languages,

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

    $differences = Compare-Object -ReferenceObject $currentValues.Languages `
        -DifferenceObject $Languages

    if ($null -eq $differences)
    {
        Write-Verbose -Message "Languges do match. No further processing required."
    }
    else
    {
        Write-Verbose -Message "Languages do not match. Performing corrective action."

        foreach ($difference in $differences)
        {
            $language = $difference.InputObject

            $path = Join-Path -Path $baseDirectory -ChildPath $language

            if (-not (Test-Path -Path $path))
            {
                New-Item -Path $path -ItemType Directory -Force
            }

            if ($difference.SideIndicator -eq "=>")
            {
                $languagePackDetail = Get-SPSBDscLanguagePackDetail -ProductName $ProductName -Language $language
                if ($null -eq $languagePackDetail)
                {
                    Write-Warning -Message "There was no language pack found for '$language'"
                    break
                }

                Start-SPSBDscFileTransfer -Destination $path -Source $languagePackDetail.Url -ExpandedFile $languagePackDetail.ExpandedFile

                $filePath = Join-Path -Path $path -ChildPath $languagePackDetail.ExpandedFile
                Remove-ReadOnlyAttribute -Path $filePath

                if ($languagePackDetail.ExpandedFile.EndsWith(".img"))
                {
                    $drive = Mount-SPSBDscImage -SourcePath $filePath
                    Copy-SPSBDscImageFilesToFolder -SourcePath $drive -TargetPath $path
                    Dismount-SPSBDscImage -SourcePath $filePath
                }
            }
            elseif ($difference.SideIndicator -eq "<=")
            {
                try
                {
                    Remove-Item -Path $path -Force -Confirm:$false
                }
                catch
                {
                    Write-Warning "Could not remove folder at '$path'."
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
        $Languages,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TargetDirectory,

        [Parameter()]
        [ValidateSet("Present")]
        [System.String]
        $Ensure = "Present"
    )

    $PSBoundParameters.Languages = $PSBoundParameters.Languages | Select-Object -Unique

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
