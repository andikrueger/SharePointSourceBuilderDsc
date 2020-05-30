function Get-TargetRessource
{
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Yes')]
        [System.String]
        $IsSingleInstance,

        [Parameter(Mandatory = $true)]
        [System.UInt32]
        $Version,

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
        Version         = $Version
        Languages       = @()
        TargetDirectory = $TargetDirectory
        Ensure          = "Absent"
    }

    if (-not(Test-Path $TargetDirectory))
    {
        $returnValue.TargetDirectory = ""
        return $returnValue
    }
    else
    {
        $folders = Get-ChildItem $source -Directory
        if (-not($null -eq $folders))
        {
            $returnValue.Ensure = "Present"
            $folders | ForEach-Object -Process {
                $returnValue.Languages += $_.Name
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
        [System.UInt32]
        $Version,

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

    foreach($language in $Languages){
        Write-Verbose "Processing $language"
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
        [System.UInt32]
        $Version,

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
