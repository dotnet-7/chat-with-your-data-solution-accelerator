


@description('Name of Azure OpenAI Resource')
param AzureOpenAIResource string

@description('Azure OpenAI Model Deployment Name')
param AzureOpenAIModel string = 'gpt-35-turbo'



@description('Azure OpenAI Key')
@secure()
param AzureOpenAIKey string

@description('Orchestration strategy: openai_function or langchain str. If you use a old version of turbo (0301), plese select langchain')
@allowed([
  'openai_function'
  'langchain'
])
param OrchestrationStrategy string


//

targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// Optional parameters to override the default azd resource naming conventions. Update the main.parameters.json file to provide values. e.g.,:
// "resourceGroupName": {
//      "value": "myGroupName"
// }
param applicationInsightsName string = ''

param resourceGroupName string = ''
param searchServiceName string = ''



param searchServiceResourceGroupName string = ''
param searchServiceLocation string = ''
// The free tier does not support managed identity (required) or semantic search (optional)
@allowed(['basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'])
param searchServiceSkuName string // Set in main.parameters.json


param storageAccountName string = ''
param storageResourceGroupName string = ''
param storageResourceGroupLocation string = location
param storageContainerName string = 'content'
param storageSkuName string // Set in main.parameters.json


param formRecognizerServiceName string = ''
param formRecognizerResourceGroupName string = ''
param contentsafetyResourceGroupName string = ''
param contentsafetyServiceName string = ''
param formRecognizerResourceGroupLocation string = location


param formRecognizerSkuName string = 'S0'


@description('Use Application Insights for monitoring and performance tracing')
param useApplicationInsights bool = false

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }




// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

resource contentsafetyResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(contentsafetyResourceGroupName)) {
  name: !empty(contentsafetyResourceGroupName) ? contentsafetyResourceGroupName : rg.name
}

resource formRecognizerResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(formRecognizerResourceGroupName)) {
  name: !empty(formRecognizerResourceGroupName) ? formRecognizerResourceGroupName : rg.name
}

resource searchServiceResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(searchServiceResourceGroupName)) {
  name: !empty(searchServiceResourceGroupName) ? searchServiceResourceGroupName : rg.name
}

resource storageResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(storageResourceGroupName)) {
  name: !empty(storageResourceGroupName) ? storageResourceGroupName : rg.name
}

// Monitor application with Azure Monitor
module monitoring './core/monitor/monitoring.bicep' = if (useApplicationInsights) {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
  }
}

module searchService 'core/search/search-services.bicep' = {
  name: 'search-service'
  scope: searchServiceResourceGroup
  params: {
    name: !empty(searchServiceName) ? searchServiceName : '${abbrs.searchSearchServices}${resourceToken}'
    location: !empty(searchServiceLocation) ? searchServiceLocation : location
    tags: tags
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    sku: {
      name: searchServiceSkuName
    }
    semanticSearch: 'free'
  }
}


module formRecognizer 'core/ai/cognitiveservices.bicep' = {
  name: 'formrecognizer'
  scope: formRecognizerResourceGroup
  params: {
    name: !empty(formRecognizerServiceName) ? formRecognizerServiceName : '${abbrs.cognitiveServicesFormRecognizer}${resourceToken}'
    kind: 'FormRecognizer'
    location: formRecognizerResourceGroupLocation
    tags: tags
    sku: {
      name: formRecognizerSkuName
    }
  }
}

module contentSafety './core/ai/cognitiveservices.bicep' = {
  name: 'contentsafety'
  scope: contentsafetyResourceGroup
  params: {
    name: !empty(contentsafetyServiceName) ? contentsafetyServiceName : '${abbrs.cognitiveServicesContentSafety}${resourceToken}'
    kind: 'ContentSafety'
    location: formRecognizerResourceGroupLocation
    tags: tags
    sku: {
      name: formRecognizerSkuName
    }
  }
}




// module storage 'core/storage/storage-account.bicep' = {
//   name: 'storage'
//   scope: storageResourceGroup
//   params: {
//     name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
//     location: storageResourceGroupLocation
//     tags: tags
//     publicNetworkAccess: 'Enabled'
//     sku: {
//       name: storageSkuName
//     }
//     deleteRetentionPolicy: {
//       enabled: true
//       days: 2
//     }
//     containers: [
//       {
//         name: storageContainerName
//         publicAccess: 'None'
//       }
//     ]
//   }
// }


module deployments 'core/test.bicep' = {
  name: 'deployments'
  scope: rg
  params: {
    location: storageResourceGroupLocation

    AzureOpenAIKey: AzureOpenAIKey
    AzureOpenAIResource: AzureOpenAIResource
    AzureOpenAIModel: AzureOpenAIModel
    OrchestrationStrategy: OrchestrationStrategy
    //StorageAccountID: storage.outputs.storageid
    FormRecognizerName: formRecognizer.outputs.name
    ContentSafetyName: contentSafety.outputs.name
    AzureCognitiveSearch: '${abbrs.searchSearchServices}${resourceToken}'
    ResourceToken: resourceToken
  }
  dependsOn:[
    //storage
  ]
}
