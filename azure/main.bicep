param location string = resourceGroup().location

var cosmosDbAccountName = 'cosmos-${uniqueString(resourceGroup().id)}'
var databaseName = 'BookJournal'
var containerName = 'JournalEntries'

param appServicePlanSku string = 'F1'
var appServicePlanName = 'appServicePlan-${uniqueString(resourceGroup().id)}'
var webAppName = 'bookJournalWebApp-${uniqueString(resourceGroup().id)}'
var linuxFxVersion = 'PYTHON|3.8'
var appInsightsName = 'bookJournalAI-${uniqueString(resourceGroup().id)}'
var acrName = 'acr${uniqueString(resourceGroup().id)}'

param B2C_TENANT string
param B2C_CLIENT_ID string

@secure()
param B2C_CLIENT_SECRET string

resource azureContainerRegistry 'Microsoft.ContainerRegistry/registries@2021-09-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  properties: {
    httpsOnly: true
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      appSettings: [
        {
          name: 'ACCOUNT_URI'
          value: cosmosDbAccount.properties.documentEndpoint
        }
        {
          name: 'ACCOUNT_KEY'
          value: cosmosDbAccount.listKeys().primaryMasterKey
        }
        {
          name: 'WEBSITES_PORT'
          value: '5000'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: azureContainerRegistry.properties.loginServer
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: azureContainerRegistry.listCredentials().username
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: azureContainerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'B2C_TENANT'
          value: B2C_TENANT
        }
        {
          name: 'B2C_CLIENT_ID'
          value: B2C_CLIENT_ID
        }
        {
          name: 'B2C_CLIENT_SECRET'
          value: B2C_CLIENT_SECRET
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'default'
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2022-05-15' = {
  name: toLower(cosmosDbAccountName)
  kind: 'GlobalDocumentDB'
  location: location
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-05-15' = {
  parent: cosmosDbAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-05-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/userid'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/_etag/?'
          }
        ]
      }
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}
