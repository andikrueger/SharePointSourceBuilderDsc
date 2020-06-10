function Expand-SPSBDscPatchFileToFolder
{
    [CmdletBinding()]
    param (
        # Source Path to copy files from
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SourcePath,

        # Target Path to copy files to
        [Parameter(Mandatory = $true)]
        [String]
        $TargetPath
    )

    Start-Process -FilePath "$SourcePath" -ArgumentList "/extract:`"$TargetPath`" /passive" -Wait -NoNewWindow
}

function Copy-SPSBDscImageFilesToFolder
{
    [CmdletBinding()]
    param (
        # Source Path to copy files from
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SourcePath,

        # Target Path to copy files to
        [Parameter(Mandatory = $true)]
        [String]
        $TargetPath
    )

    Robocopy.exe ("{0}:" -f $SourcePath) $TargetPath /E | Out-Null
}

function Mount-SPSBDscImage
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        # Path of the image
        [Parameter(Mandatory = $true)]
        [String]
        $SourcePath
    )

    Write-Verbose "Mount the image from $SourcePath"
    $image = Mount-DiskImage -ImagePath $SourcePath -PassThru
    $driveLetter = ($image | Get-Volume).DriveLetter
    return $driveLetter
}

function Dismount-SPSBDscImage
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        # Path of the image
        [Parameter(Mandatory = $true)]
        [String]
        $SourcePath
    )

    Write-Verbose "Dismount the image from $SourcePath"
    Dismount-DiskImage -ImagePath $SourcePath -PassThru
}


Function Remove-ReadOnlyAttribute
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $Path
    )

    foreach ($item in (Get-ChildItem -File -Path $Path -Recurse -ErrorAction SilentlyContinue))
    {
        $attributes = @((Get-ItemProperty -Path $item.FullName).Attributes)
        if ($attributes -match "ReadOnly")
        {
            # Set the file to just have the 'Archive' attribute
            Write-Verbose "Removing Read-Only attribute from file: $item"
            Set-ItemProperty -Path $item.FullName -Name Attributes -Value "Archive"
        }
    }
}

function Start-SPSBDscFileTransfer
{
    [CmdletBinding()]
    param(
        # Destination folder
        [Parameter(Mandatory = $true)]
        [String]
        $Destination,

        # Source URL
        [Parameter(Mandatory = $true)]
        [String]
        $Source,

        # Expanded File Name
        [Parameter(Mandatory = $true)]
        [String]
        $ExpandedFile
    )

    $targetPath = Join-Path $Destination -ChildPath $ExpandedFile

    $job = Start-BitsTransfer -Asynchronous `
        -Source $Source `
        -Destination $targetPath `
        -DisplayName "Downloading `'$destinationFile`' to $targetPath" `
        -Priority Foreground `
        -Description "From $Source" `
        -RetryInterval 60 `
        -RetryTimeout 3600 `
        -Verbose -ErrorVariable $err

    while ($job.JobState -eq "Connecting")
    {
        Write-Verbose "."
        Start-Sleep -Milliseconds 500
    }

    if ($err)
    {
        Throw
    }

    Write-Verbose "  - Downloading $destinationFile..."

    while ($job.JobState -ne "Transferred")
    {
        $percentDone = "{0:N2}" -f $($job.BytesTransferred / $job.BytesTotal * 100) + "% - $($job.JobState)"
        Write-Verbose $percentDone
        Start-Sleep -Milliseconds 500
        $backspaceCount = (($percentDone).ToString()).Length
        for ($count = 0; $count -le $backspaceCount; $count++)
        {
            Write-Verbose "`b `b"
        }
        if ($job.JobState -like "*Error")
        {
            Write-Verbose "  - An error occurred downloading $destinationFile, retrying..."
            Resume-BitsTransfer -BitsJob $job -Asynchronous | Out-Null
        }
    }
    Write-Verbose "  - Completing transfer..."
    Complete-BitsTransfer -BitsJob $job
}

function Get-AutoSPSourceBuilderXml
{
    [OutputType([XML])]
    param()

    $autoSpSourceBuilderUrl = "https://raw.githubusercontent.com/brianlala/AutoSPSourceBuilder/master/Scripts/AutoSPSourceBuilder.xml"
    $autoSpSourceBuilderXml = New-Object System.Xml.XmlDocument
    $autoSpSourceBuilderXml.Load($autoSpSourceBuilderUrl)

    return $autoSpSourceBuilderXml
}

function Get-SPSBDscPatchDetail
{
    [CmdletBinding()]
    [OutputType([Object[]])]
    param(
        # SharePoint Version Number
        [Parameter(Mandatory = $true)]
        [Int]
        $ProductName,

        # Patch Name
        [Parameter(Mandatory = $true)]
        [string]
        $PatchName
    )

    $autoSpSourceBuilderXml = Get-AutoSPSourceBuilderXml

    $productNode = $autoSpSourceBuilderXml.Products.Product | Where-Object -FilterScript {
        $_.Name -eq $ProductName
    }

    $cumulativeUpdates = $productNode.CumulativeUpdates.CumulativeUpdate | Where-Object -FilterScript {
        $_.Name -eq $SharePointPatchName
    }

    $returnValue = @()

    $cumulativeUpdates | ForEach-Object -Process {

        $expandedFile = $_.ExpandedFile

        if ($expandedFile.StartsWith("wss") `
                -or $expandedFile.StartsWith("sts") `
                -or $expandedFile.StartsWith("ubersrv2013") )
        {
            $returnValue += @{
                Url          = $_.Url
                ExpandedFile = $expandedFile
            }
        }
    }

    return $returnValue
}

function Get-SPSBDscLanguagePackDetail
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        # SharePoint Version Number
        [Parameter(Mandatory = $true)]
        [System.String]
        $ProductName,

        # Language like "de-de"
        [Parameter(Mandatory = $true)]
        [System.String]
        $Language
    )

    $autoSpSourceBuilderXml = Get-AutoSPSourceBuilderXml

    $productNode = $autoSpSourceBuilderXml.Products.Product | Where-Object -FilterScript {
        $_.Name -eq $SharePointVersion
    }

    $languagePack = $productNode.LanguagePacks.LanguagePack | Where-Object -FilterScript {
        $_.Name -eq $Language
    }

    try
    {
        $urlSegments = $languagePack.Url.Split('/')

        $returnValue += @{
            Url          = $languagePack.Url
            ExpandedFile = $urlSegments[$urlSegments.Count - 1]
        }
        return $returnValue
    }
    catch
    {
        return $null
    }

}


function Test-SPSBDscParameterState
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [HashTable]
        $CurrentValues,

        [Parameter(Mandatory = $true, Position = 2)]
        [Object]
        $DesiredValues,

        [Parameter(, Position = 3)]
        [Array]
        $ValuesToCheck
    )

    $returnValue = $true

    if (($DesiredValues.GetType().Name -ne "HashTable") -and `
        ($DesiredValues.GetType().Name -ne "CimInstance") -and `
        ($DesiredValues.GetType().Name -ne "PSBoundParametersDictionary"))
    {
        throw ("Property 'DesiredValues' in Test-SPDscParameterState must be either a " + `
                "Hashtable or CimInstance. Type detected was $($DesiredValues.GetType().Name)")
    }

    if (($DesiredValues.GetType().Name -eq "CimInstance") -and ($null -eq $ValuesToCheck))
    {
        throw ("If 'DesiredValues' is a CimInstance then property 'ValuesToCheck' must contain " + `
                "a value")
    }

    if (($null -eq $ValuesToCheck) -or ($ValuesToCheck.Count -lt 1))
    {
        $KeyList = $DesiredValues.Keys
    }
    else
    {
        $KeyList = $ValuesToCheck
    }

    $KeyList | ForEach-Object -Process {
        if (($_ -ne "Verbose"))
        {
            if (($CurrentValues.ContainsKey($_) -eq $false) -or `
                ($CurrentValues.$_ -ne $DesiredValues.$_) -or `
                (($DesiredValues.ContainsKey($_) -eq $true) -and `
                    ($null -ne $DesiredValues.$_ -and `
                            $DesiredValues.$_.GetType().IsArray)))
            {
                if ($DesiredValues.GetType().Name -eq "HashTable" -or `
                        $DesiredValues.GetType().Name -eq "PSBoundParametersDictionary")
                {
                    $CheckDesiredValue = $DesiredValues.ContainsKey($_)
                }
                else
                {
                    $CheckDesiredValue = Test-SPSBDscObjectHasProperty -Object $DesiredValues -PropertyName $_
                }

                if ($CheckDesiredValue)
                {
                    $desiredType = $DesiredValues.$_.GetType()
                    $fieldName = $_
                    if ($desiredType.IsArray -eq $true)
                    {
                        if (($CurrentValues.ContainsKey($fieldName) -eq $false) -or `
                            ($null -eq $CurrentValues.$fieldName))
                        {
                            Write-Verbose -Message ("Expected to find an array value for " + `
                                    "property $fieldName in the current " + `
                                    "values, but it was either not present or " + `
                                    "was null. This has caused the test method " + `
                                    "to return false.")
                            $returnValue = $false
                        }
                        else
                        {
                            $arrayCompare = Compare-Object -ReferenceObject $CurrentValues.$fieldName `
                                -DifferenceObject $DesiredValues.$fieldName
                            if ($null -ne $arrayCompare)
                            {
                                Write-Verbose -Message ("Found an array for property $fieldName " + `
                                        "in the current values, but this array " + `
                                        "does not match the desired state. " + `
                                        "Details of the changes are below.")
                                $arrayCompare | ForEach-Object -Process {
                                    Write-Verbose -Message "$($_.InputObject) - $($_.SideIndicator)"
                                }
                                $returnValue = $false
                            }
                        }
                    }
                    else
                    {
                        switch ($desiredType.Name)
                        {
                            "String"
                            {
                                if ([string]::IsNullOrEmpty($CurrentValues.$fieldName) -and `
                                        [string]::IsNullOrEmpty($DesiredValues.$fieldName))
                                {
                                }
                                else
                                {
                                    Write-Verbose -Message ("String value for property " + `
                                            "$fieldName does not match. " + `
                                            "Current state is " + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            "and desired state is " + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $returnValue = $false
                                }
                            }
                            "Int32"
                            {
                                if (($DesiredValues.$fieldName -eq 0) -and `
                                    ($null -eq $CurrentValues.$fieldName))
                                {
                                }
                                else
                                {
                                    Write-Verbose -Message ("Int32 value for property " + `
                                            "$fieldName does not match. " + `
                                            "Current state is " + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            "and desired state is " + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $returnValue = $false
                                }
                            }
                            "Int16"
                            {
                                if (($DesiredValues.$fieldName -eq 0) -and `
                                    ($null -eq $CurrentValues.$fieldName))
                                {
                                }
                                else
                                {
                                    Write-Verbose -Message ("Int16 value for property " + `
                                            "$fieldName does not match. " + `
                                            "Current state is " + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            "and desired state is " + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $returnValue = $false
                                }
                            }
                            "Boolean"
                            {
                                if ($CurrentValues.$fieldName -ne $DesiredValues.$fieldName)
                                {
                                    Write-Verbose -Message ("Boolean value for property " + `
                                            "$fieldName does not match. " + `
                                            "Current state is " + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            "and desired state is " + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $returnValue = $false
                                }
                            }
                            "Single"
                            {
                                if (($DesiredValues.$fieldName -eq 0) -and `
                                    ($null -eq $CurrentValues.$fieldName))
                                {
                                }
                                else
                                {
                                    Write-Verbose -Message ("Single value for property " + `
                                            "$fieldName does not match. " + `
                                            "Current state is " + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            "and desired state is " + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $returnValue = $false
                                }
                            }
                            default
                            {
                                Write-Verbose -Message ("Unable to compare property $fieldName " + `
                                        "as the type ($($desiredType.Name)) is " + `
                                        "not handled by the " + `
                                        "Test-SPDscParameterState cmdlet")
                                $returnValue = $false
                            }
                        }
                    }
                }
            }
        }
    }
    return $returnValue
}

function Test-SPSBDscObjectHasProperty
{
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [Object]
        $Object,

        [Parameter(Mandatory = $true, Position = 2)]
        [String]
        $PropertyName
    )

    if (([bool]($Object.PSobject.Properties.name -contains $PropertyName)) -eq $true)
    {
        if ($null -ne $Object.$PropertyName)
        {
            return $true
        }
    }
    return $false
}


function Convert-SPSBDscHashtableToString
{
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [System.Collections.Hashtable]
        $Hashtable
    )
    $values = @()
    foreach ($pair in $Hashtable.GetEnumerator())
    {
        try
        {
            if ($pair.Value -is [System.Array])
            {
                $str = "$($pair.Key)=($($pair.Value -join ","))"
            }
            elseif ($pair.Value -is [System.Collections.Hashtable])
            {
                $str = "$($pair.Key)={$(Convert-SPSBDscHashtableToString -Hashtable $pair.Value)}"
            }
            else
            {
                if ($null -eq $pair.Value)
                {
                    $str = "$($pair.Key)=`$null"
                }
                else
                {
                    $str = "$($pair.Key)=$($pair.Value)"
                }
            }
            $values += $str
        }
        catch
        {
            Write-Warning "There was an error converting the Hashtable to a string: $_"
        }
    }

    [array]::Sort($values)
    return ($values -join "; ")
}
