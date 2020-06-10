Configuration Example
{
    Import-DscResource -ModuleName SharePointSourceBuilderDsc

    Node localhost
    {
        SPSBProductUpdate ProductUpdates
        {
            IsSingleInstance = "Yes"
            ProductName      = "SP2019"
            Patches          = @("November 2019", "December 2019")
            TargetDirectory  = "C:\Sources\"
            Ensure           = "Present"
        }
    }
}
