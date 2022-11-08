#!/bin/bash

echo -n "Please enter a Key-Vault Name: "
read $keyvaultname

# Create an App Service app with deployment from GitHub
# set -e # exit if error
# Variable block
let "randomIdentifier=$RANDOM*$RANDOM"
location="West Europe"
resourceGroup="traffic-manager-rg-$randomIdentifier"
tag="deploy-github.sh"
gitrepo=https://github.com/mnestler-git/TM_westeurope.git 

trafficManagerDNSName=dispatcher$RANDOM
trafficManagerDNSEastUS=eastus$RANDOM
trafficManagerDNSWestEurope=westeurope$RANDOM

# Create a resource group.
echo "Creating $resourceGroup in "$location"..."
az group create --name $resourceGroup --location "$location" --tag $tag

# Create a Traffic Manager profile
# This parent profile is used as the entry point for your application traffic
# In later steps, child profiles for individual Azure regions are created and attached
az network traffic-manager profile create \
    --resource-group $resourceGroup \
    --name dispatcher \
    --routing-method geographic \
    --unique-dns-name $trafficManagerDNSName


# Create a Traffic Manager profile for East US
az network traffic-manager profile create \
    --resource-group $resourceGroup \
    --name eastus \
    --routing-method priority \
    --unique-dns-name $trafficManagerDNSEastUS

# Create a Traffic Manager profile for West Europe
az network traffic-manager profile create \
    --resource-group $resourceGroup \
    --name westeurope \
    --routing-method priority \
    --unique-dns-name $trafficManagerDNSWestEurope


#####################################
####Create West Europe Web App#######
#####################################

appServicePlan="appserviceplanwesteurope$randomIdentifier"
webappWestEurope="appWEU$randomIdentifier"


# Create an App Service plan in `S1` tier.
echo "Creating $appServicePlan"
az appservice plan create --name $appServicePlan --resource-group $resourceGroup --sku S1 --location "westeurope"

# Create a web app.
echo "Creating $webappWestEurope"
az webapp create --name $webappWestEurope --resource-group $resourceGroup --plan $appServicePlan

# Get Personal Access Token for Github repository which is stored in keyvault
githubAccessToken=$(az keyvault secret show --name "GithubPersonalAccessToken1" --vault-name $keyvaultname --query value -o tsv)

# Deploy code from a private GitHub repository. 
az webapp deployment source config --branch master --manual-integration --name $webappWestEurope --repo-url $gitrepo --resource-group $resourceGroup --git-token $githubAccessToken




# Use curl to see the web app.
#site="http://$webapp.azurewebsites.net"
#echo $site
#curl "$site" # Optionally, copy and paste the output of the previous command into a browser to see the web app

#################################
####Create East US Web App#######
#################################


gitrepo=https://github.com/mnestler-git/TM_eastuse.git 
appServicePlan="appserviceplaneastus$randomIdentifier"
webappEastUS="appEUS$randomIdentifier"

# Create an App Service plan in `S1` tier.
echo "Creating $appServicePlan"
az appservice plan create --name $appServicePlan --resource-group $resourceGroup --sku S1 --location "eastus"

# Create a web app.
echo "Creating $webappEastUS"
az webapp create --name $webappEastUS --resource-group $resourceGroup --plan $appServicePlan

# Deploy code from a private GitHub repository. 
az webapp deployment source config --branch master --manual-integration --name $webappEastUS --repo-url $gitrepo --resource-group $resourceGroup --git-token $githubAccessToken


# Add endpoint for East US Traffic Manager profile
# This endpoint is for the East US Web App, and sets with a high priority of 1
az network traffic-manager endpoint create \
    --resource-group $resourceGroup \
    --name eastus \
    --profile-name eastus \
    --type azureEndpoints \
    --target-resource-id $(az webapp show \
        --resource-group $resourceGroup \
        --name $webappEastUS \
        --query id \
        --output tsv) \
    --priority 1


# Add endpoint for East US Traffic Manager profile
# This endpoint is for the West Europe Web App, and sets with a low priority of 100
az network traffic-manager endpoint create \
    --resource-group $resourceGroup \
    --name westeurope \
    --profile-name eastus \
    --type azureEndpoints \
    --target-resource-id $(az webapp show \
        --resource-group $resourceGroup \
        --name $webappWestEurope \
        --query id \
        --output tsv) \
    --priority 100


# Add endpoint for West Europe Traffic Manager profile
# This endpoint is for the West Europe Web App, and sets with a high priority of 1
az network traffic-manager endpoint create \
    --resource-group $resourceGroup \
    --name westeurope \
    --profile-name westeurope \
    --type azureEndpoints \
    --target-resource-id $(az webapp show \
        --resource-group $resourceGroup \
        --name $webappWestEurope \
        --query id \
        --output tsv) \
    --priority 1

# Add endpoint for West Europe Traffic Manager profile
# This endpoint is for the East US Web App, and sets with a low priority of 100
az network traffic-manager endpoint create \
    --resource-group $resourceGroup \
    --name eastus \
    --profile-name westeurope \
    --type azureEndpoints \
    --target-resource-id $(az webapp show \
        --resource-group $resourceGroup \
        --name $webappEastUS \
        --query id \
        --output tsv) \
    --priority 100


###!!!!!!!!!!!!!!!###
# This command didn't not work in the cloud shell (08.11.2022). I guess because of the newest 
# version of azure cli. The command works with the version 2.27.2.
###!!!!!!!!!!!!!!###
# Add nested profile to parent Traffic Manager geographic routing profile
# The East US Traffic Manager profile is attached to the parent Traffic Manager profile
az network traffic-manager endpoint create \
    --resource-group $resourceGroup \
    --name eastus \
    --profile-name dispatcher \
    --type nestedEndpoints \
    --target-resource-id $(az network traffic-manager profile show \
        --resource-group $resourceGroup \
        --name eastus \
        --query id \
        --output tsv) \
    --geo-mapping GEO-NA \
    --min-child-endpoints 1

# Add nested profile to parent Traffic Manager geographic routing profile
# The West Europe Traffic Manager profile is attached to the parent Traffic Manager profile
az network traffic-manager endpoint create \
    --resource-group $resourceGroup \
    --name westeurope \
    --profile-name dispatcher \
    --type nestedEndpoints \
    --target-resource-id $(az network traffic-manager profile show \
        --resource-group $resourceGroup \
        --name westeurope \
        --query id \
        --output tsv) \
    --geo-mapping GEO-EU \
    --min-child-endpoints 1

#########!!!!!!!!!!!!##########
#This commands works only if the two other previous commands worked
#########!!!!!!!!!!!!##########
# Add custom hostname to Web App
# As we want to distribute traffic from each region through the central Traffic Manager profile, the
# Web App must identify itself on a custom domain
# This hostname is for the East US Web App
az webapp config hostname add \
    --resource-group $resourceGroup \
    --webapp-name $webappEastUS \
    --hostname $trafficManagerDNSName.trafficmanager.net

# Add custom hostname to Web App
# As we want to distribute traffic from each region through the central Traffic Manager profile, the
# Web App must identify itself on a custom domain
# This hostname is for the East US Web App
az webapp config hostname add \
    --resource-group $resourceGroup \
    --webapp-name $webappWestEurope \
    --hostname $trafficManagerDNSName.trafficmanager.net