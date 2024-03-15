#! /bin/bash

# 1- Login & Create a resource group in Azure.
# 2- Create a resource group
#   2.1- Select a region from the 5 recomended regions.
#   2.2- Verify the region selected actually exists.
#   2.3- Create a new resource group, name provided by the user.
#   2.4- List all the resource groups.
# 3- Check and validate the parameters of the user's invocation: if all of them are valid files.
# 4- Upload the valid file to Azure storage.
#   4.1- Create a new Azure storage resource.
# 5- (Optional) Allow multiple file uploads.
#   5.1- Progress bar completion.
#   5.2- Shareable link after sucessful uploading the files.
#   5.3- File synchronization - If the file already exists in the cloud, prompt the user
#   to overwrite, skip, or rename the file.

setup() {
    # Install az cli on Linux
    # curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    # With Homebrew
    brew update && brew install azure-cli
    # the last parameter: output as a json in colors
    az login --use-device-code -o jsonc
    echo "You're logged in."
}

#Print out 5 recommended regions.
printout_regions() {
    # https://github.com/Azure/vagrant-azure#create-an-azure-active-directory-aad-application
    # If you want to pick specific subscription, run:
    subscriptionId='f3be56d8-b9d5-4d42-a130-60bd4c667031'
    az account set --subscription subscriptionId
    regions_array=($( az account list-locations --query "[?metadata.regionCategory=='Recommended'].{Name:name}" -o tsv | head -n 5))
    for i in "${regions_array[@]}"
    do
       echo "$i"
    done

}

#Select a region
check_region() {
    # This 'local' variable only is visible within this function. Therefore, default to global.
    local region_exists=false
    while [[ "$region_exists" == false ]]; do
        printout_regions
        # Ask the name of the user's region.
        read -p "Enter your region: " selected_region
        # Check if the region the user is trying to create already exists!
        for j in "${regions_array[@]}"
        do
            if [[ "$selected_region" == "$j" ]]; then
                region_exists=true
                echo "Valid region!"
                break
            #else
            #    continue
            fi
        done
    done
}

# Check if the resource group already exists!
check_resource_group() {
    while true; do
        read -p "Enter a name for your resource group: " resource_group
        if [ $(az group exists --name $resource_group) == true ]; then
            echo "Resource group $resource_group exists in $selected_region, provide another name..."
        else
            break
        fi
    done
}

# Create a resource group
new_resource_group() {
    echo "Creating the resource group: $resource_group in $selected_region"
    az group create -g $resource_group -l $selected_region | grep provisioningState
}

# List all resource groups
list_all() {
    az group list -o table
}

# Setup the resource group where the user is going to upload the file
setup_acc_rsgroup() {
    setup
    check_region
    check_resource_group
    new_resource_group
    list_all
}

# setup_acc_rsgroup

# 3- Read the parameters of the user's invocation and check if the file path parameter exists.
flag_param=$1
file_param=$2
file_path_resource_created_two_params() {
    echo "Flag parameter provided: $flag_param"
    echo "File path parameter provided: $file_param"
    # A reduce way to verify the file existance.
    [ ! -f $file_param ] && echo "File not found: $file_param"
}

# file_path_resource_created_two_params

# Check if the storage account already exists!
check_storage_acc() {
    if [ -z $resource_group ] # True if the length of string is zero.
    then
        resource_group="rg-ktorresrg"
    fi

    if [ -z $selected_region ]
    then
        selected_region="westus2"
    fi

    while true; do
        read -p "Enter storage account name: " storageAccountName
        # Checks if the name already exists
        local checkAccName=$(az storage account check-name --name $storageAccountName --query "nameAvailable")
        if [ $checkAccName == false ]
        then 
            echo "The name $storageAccountName is already taken, please provide another name..."
        else
            # Command to create a storage account
            az storage account create --name "$storageAccountName" --resource-group "$resource_group" --location "$selected_region" --sku Standard_LRS --encryption-services blob
            AZ_STORAGE_ACC_NAME=$storageAccountName
            # Command to list storage accounts
            # az storage account list -g "$resource_group"
            break
        fi
    done
}

# Create an Azure storage account
create_az_storage() {
    #check_storage_acc
    if [ -z $AZ_STORAGE_ACC_NAME ] # True if the length of string is zero.
    then
        export AZ_STORAGE_ACC_NAME="ktorressauploader"
    fi
    # Get the connection string for the storage account
    local azure_storage_connection_string=$(az storage account show-connection-string --name "$AZ_STORAGE_ACC_NAME" --resource-group "$resource_group" --output tsv)
    export AZURE_STORAGE_CONNECTION_STRING=$azure_storage_connection_string
    create_container
}

create_container() {
    # echo "AZURE_STORAGE_CONNECTION_STRING: $AZURE_STORAGE_CONNECTION_STRING"
    # echo "AZ_STORAGE_ACC_NAME: $AZ_STORAGE_ACC_NAME"
    while true; do
        read -p "Enter Container name: " container
        # Checks if the name already exists
        if [ "$(az storage container exists --name "$container" --account-name "$AZ_STORAGE_ACC_NAME" --query "exists")" = true ]; then 
            echo "The container name: $container is already taken, please provide another name..."
        else
            # Command to create a Container
            az storage container create --account-name $AZ_STORAGE_ACC_NAME --name $container --connection-string $AZURE_STORAGE_CONNECTION_STRING
            # Command to list Container
            #az storage container list
            break
        fi
    done
}

create_az_storage

for absolutePathFile in $@
do
    # echo "Entered arg is: $x"
    # Verify the list of file paramenters space separated, and let user know
    # if one or more files where not found.
    if [ ! -f $absolutePathFile ]; then
        echo "File not found: $absolutePathFile"
    else
        # Upload the file to Azure.
        #echo "_____Found____: $absolutePathFile"
        baseName=$(basename ${absolutePathFile})
        # Each parameter read it's a different file to be uploaded
        az storage blob upload -f $absolutePathFile -n $baseName -c $container
        # Generate a shared access signature for the file with read-only permission.
        #end=`date -u -d "30 minutes" '+%Y-%m-%dT%H:%MZ'`
        end='2024-03-16T00:00:00Z'
        urlReadAccessToken=$(az storage blob generate-sas --account-name $AZ_STORAGE_ACC_NAME --container-name $container --name $baseName --permissions r --expiry $end --https-only --full-uri)
        echo "URL to access the resorce uploaded: $urlReadAccessToken"
    fi
done
