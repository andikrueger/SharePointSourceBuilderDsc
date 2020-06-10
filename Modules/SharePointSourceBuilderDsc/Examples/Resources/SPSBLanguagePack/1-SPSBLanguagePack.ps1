Configuration Example
{
    Import-DscResource -ModuleName SharePointSourceBuilderDsc

    Node localhost
    {
        SPSBLanguagePack LanguagePack
        {
            IsSingleInstance = "Yes"
            ProductName      = "SP2019"
            Languages        = @("de-de")
            TargetDirectory  = "C:\Sources\"
            Ensure           = "Present"
        }
    }
}
