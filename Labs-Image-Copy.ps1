Param(

    [string] [Parameter(Mandatory=$true)] $sourceSnapshotName,
    [string] [Parameter(Mandatory=$false)] $sourceVhdUrl,# $sourceSnapshotName or $sourceVhdUrl must pass one ls112-tfs-server-2018-tfs2018-windows-snapshot-20180423.2        
    [string] [Parameter(Mandatory=$true)] $destSubscriptionId, #"9b26957f-5a38-47aa-a0fa-cd97f1dfdb12", #Windows Azure 企业
    [string] [Parameter(Mandatory=$true)] $destTenantId,
    [string] [Parameter(Mandatory=$true)] $destApplicationId,
    [string] [Parameter(Mandatory=$true)] $destApplicationKey,

    [string] [Parameter(Mandatory=$false)] $destAzEnvName = "AzureChinaCloud", # global(AzureCloud) or china(AzureChinaCloud)  Get-AzureRmEnvironment | Select-Object Name
    [string] [Parameter(Mandatory=$false)] $destVhdName = "vhd",# =sourceSnapshotName TODO : REMOVE
    [string] [Parameter(Mandatory=$true)] $destAzEnvLocation = "chinanorth", 

    [string] [Parameter(Mandatory=$false)] $uniqueSeed, # maybe a buildid
    [string] [Parameter(Mandatory=$false)] $vmName, # TODO: REMOVE
    [string] [Parameter(Mandatory=$true)] $destResourceGroupName, 
    [string] [Parameter(Mandatory=$true)] $storageAccountContainer = "vhds", # 3 and 24 characters in length and use numbers and lower-case letters  

    [string] [Parameter(Mandatory=$false)] $resultTemplateFilePath # if leave empty, will use $env:BUILD_SOURCESDIRECTORY + '\000-image-sync\labs-result-template.json'

 )

"## Check input parameters are valid ##########"

"sourceSnapshotName      is: $sourceSnapshotName"
"sourceVhdUrl            is: $sourceVhdUrl"
"destSubscriptionId      is: $destSubscriptionId"
"destAzEnvName           is: $destAzEnvName"
"destVhdName             is: $destVhdName"
"destAzEnvLocation       is: $destAzEnvLocation"
"uniqueSeed              is: $uniqueSeed"
"vmName                  is: $vmName"
"destResourceGroupName   is: $destResourceGroupName"
"storageAccountContainer is: $storageAccountContainer"
"resultTemplateFilePath  is: $resultTemplateFilePath"

if($sourceVhdUrl -eq $null -or $sourceVhdUrl -eq ''){
    throw "Params:sourceVhdUrl is null or empty."
}

if($destSubscriptionId -eq $null -or $destSubscriptionId -eq ''){
    throw "Param: destSubscriptionId if null or empty."
}

$destVhdName = $sourceSnapshotName + (Get-Date -Format fff) + ".vhd"
"destVhdName (generated)  is: $destVhdName"

"## Input Parameters are valid   ##########"

" "
" "
"## Run Section 01. ## Login dest Subscription: $destSubscriptionId ##########"

# login dest Subscription
$newsec = ConvertTo-SecureString -String $destApplicationKey -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential($destApplicationId, $newsec)
Login-AzureRmAccount -Credential $cred -TenantId $destTenantId -ServicePrincipal $destAzEnvName #AzureChinaCloud
"Successfully login to dest Subscription: $destSubscriptionId"

if($destSubscriptionId -ne $null){
    "Select dest Subscription: $destSubscriptionId"
    Select-AzureRmSubscription -SubscriptionId $destSubscriptionId   
}

" "
" "
"## Run Section 02. ## Setup Resource Group in dest Subscription ##########"

# find source resourceGroupName
$findRSName = (Find-AzureRmResourceGroup | where {$_.name -EQ $destResourceGroupName}).name

if($destResourceGroupName -ne $findRSName){
    # create targetResourceGroupName
    "Resource group $destResourceGroupName not exists, creating a new one. "
    New-AzureRmResourceGroup -Name $destResourceGroupName -Location $destAzEnvLocation
    "Resource group $destResourceGroupName created. "
}
else
{
    "Resource group $destResourceGroupName is already there."
}

" "
" "
"## Run Section 03. ## Setup StorageAccount and Container in dest Subscription ##########"

$destStorageAccountName=''
# Create a storage account name if none was provided
# Storage account name rule {snapshot prefix}(9) + 'x' + {subscription id}(14) = 24 

if ($destStorageAccountName -eq '') {
    $destStorageAccountName = $sourceSnapshotName.Replace('-', '').substring(0,9) + "x" + ((Get-AzureRmContext).Subscription.Id).Replace('-', '').substring(0, 14) 
    "Generated destStorageAccountName = $destStorageAccountName"
}

$accountAvailable = Get-AzureRmStorageAccountNameAvailability -Name $destStorageAccountName

"resourceGroupName is $destResourceGroupName"
"storageAccountName is $destStorageAccountName"
"accountAvailable.NameAvailable is: " +$accountAvailable.NameAvailable
"accountAvailable.Reason is: " + $accountAvailable.Reason

if($accountAvailable.NameAvailable) {
    #create targetStorageAccount " 
    "$destStorageAccountName not Exists ，create new storage account"
    New-AzureRmStorageAccount -ResourceGroupName $destResourceGroupName -AccountName $destStorageAccountName -Location $destAzEnvLocation -Type "Standard_LRS"  
    Set-AzureRmCurrentStorageAccount -ResourceGroupName $destResourceGroupName -Name $destStorageAccountName
    $container = New-AzureStorageContainer -Name $storageAccountContainer      
}
elseif($accountAvailable.Reason -eq "AlreadyExists") {
    # get container
    "$destStorageAccountName already exists ，get container"
    Set-AzureRmCurrentStorageAccount -ResourceGroupName $destResourceGroupName -Name $destStorageAccountName
    $containerExists = Get-AzureStorageContainer -Prefix $storageAccountContainer
    if ($containerExists -eq $null)
    {
        $container = New-AzureStorageContainer -Name $storageAccountContainer
    }
    else
    {
        $container = AzureStorageContainer -Name $storageAccountContainer
    }
}
else {
    "$destStorageAccountName is not valid"
    throw "Reason:" + $accountAvailable.Reason +","+ $accountAvailable.Message
}

# Get destStorageAccount
$destStorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $destResourceGroupName -Name $destStorageAccountName;

" "
" "
"## Run Section 04. ## Start copying snapshot to dest Subscription ##########"

"## Start copy image"

$copyBlob = Start-AzureStorageBlobCopy -AbsoluteUri $sourceVhdUrl -DestContainer $storageAccountContainer -DestContext $destStorageAccount.Context -DestBlob $destVhdName;
$copyBlob

"Wait copy complete(maybe need 5 ~ 60 Minutes)..."
Do {
    $copyBlob = Get-AzureStorageBlobCopyState -Blob $destVhdName -Container $storageAccountContainer
    "--> copy status is " + $copyBlob.Status + " ... "
    Start-Sleep 10
} While($copyBlob.Status -eq "Pending")

"Copy complate!"

# stop copy
#Get-AzureStorageBlob -Container $storageAccountContainer | Stop-AzureStorageBlobCopy -Force

" "
" "
"## Run Section 05. ## Create VM Image in dest Subscription ##########"

# create new vm image from vhd file

if($destVhdName.ToLower().IndexOf("windows") -ge 0){
    $osType = "Windows";
}
elseif($destVhdName.ToLower().IndexOf("linux") -ge 0){
    $osType = "Linux";
}
else {
    throw "the destVhdName value: $destVhdName must Contain a osType(Windows or Linux)。refer sourceSnapshotName(value is:$sourceSnapshotName) format:ls112-tfs-server-2018-tfs2018-windows-snapshot-20180423.1"
}

$osVhdUri = "$($container.CloudBlobContainer.Uri.AbsoluteUri)/$destVhdName"
"osVhdUri is: $osVhdUri"

$imageConfig = New-AzureRmImageConfig -Location $destAzEnvLocation
Set-AzureRmImageOsDisk -Image $imageConfig -OsType $osType -OsState Generalized -BlobUri $osVhdUri

$imageName = $destVhdName.Replace(".vhd","").Replace("snapshot", "image")
"imageName is: $imageName"
$image = New-AzureRmImage -ImageName $imageName -ResourceGroupName $destResourceGroupName -Image $imageConfig
$image

"## Create new vm image completed"

" "
" "
"## Run Section 06. ## Generating result.json for labs ##########"

# replace all output string
$needReplaceVars = "#imageName#","#imageId#"

if ($resultTemplateFilePath -eq '')
{
    $resultTemplateFilePath=$env:BUILD_SOURCESDIRECTORY + '\000-image-sync\labs-result-template.json'
}

"using $resultTemplateFilePath"

$resultJsonContent = Get-Content $resultTemplateFilePath | Out-String 
$resultJsonContent=$resultJsonContent.Replace($needReplaceVars[0], $imageName);
$resultJsonContent=$resultJsonContent.Replace($needReplaceVars[1], $image.Id);

out-File -FilePath $resultTemplateFilePath -InputObject $resultJsonContent
echo $resultJsonContent

"## Image Sync Job is done! ##########"
