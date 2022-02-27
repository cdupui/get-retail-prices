# Get Configuration Variables

$StorageAccountName = Get-AutomationVariable -Name "StorageAccountName"  
$ContainerName = Get-AutomationVariable -Name "ContainerName"
$RetailPricesCsvFileNamePrefix = Get-AutomationVariable -Name "RetailPricesCsvFileNamePrefix"
$Currency = Get-AutomationVariable -Name "Currency"

# Connect with Run As Account Service Principal
# Will be replace by Managed Identity late around (Still in Preview)
# Connect to Azure with system-assigned managed identity
# Connect-AzAccount -Identity
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    #"Logging in to Azure..."
    Connect-AzAccount -ServicePrincipal -Tenant $servicePrincipalConnection.TenantID -ApplicationId $servicePrincipalConnection.ApplicationID -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

$Timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
$FileName = $RetailPricesCsvFileNamePrefix+$Timestamp+".csv"
$FilePath = $env:TEMP+"\"+$FileName

$Uri = "https://prices.azure.com/api/retail/prices?currencyCode='"+$Currency+"'&`$filter=pricetype eq 'Reservation'"
$Prices = Invoke-WebRequest -Method GET -UseBasicParsing -ContentType "application/json" -Uri $Uri -Headers $Headers | ConvertFrom-Json
$Prices.Items | ConvertTo-Csv -NoTypeInformation | Out-File -Append -FilePath $FilePath
$NextLink = $Prices.NextPageLink

While ($Null -ne $NextLink) {
   $Prices = Invoke-WebRequest -Method GET -UseBasicParsing -ContentType "application/json" -Uri $NextLink -Headers $Headers | ConvertFrom-Json
   $Prices.Items | ConvertTo-Csv -NoTypeInformation | Select-Object -skip 1 | Out-File -Append -FilePath $FilePath
   $NextLink = $Prices.NextPageLink
   $NextLink
}

$context=New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

$BlobContent = @{
  File             = $FilePath
  Container        = $ContainerName
  Blob             = $FileName
  Context          = $context
  StandardBlobTier = 'Hot'
}
Set-AzStorageBlobContent @BlobContent

