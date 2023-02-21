param location string = resourceGroup().location
param production bool = false

var cosmosDbAccountName = 'cosmos-${uniqueString(resourceGroup().id)}'
var databaseName = 'BookJournal'
var containerName = 'JournalEntries'

param appServicePlanSku string = 'F1'
var appServicePlanName = 'appServicePlan-${uniqueString(resourceGroup().id)}'
var webAppName = 'bookJournalWebApp-${uniqueString(resourceGroup().id)}'
var linuxFxVersion = 'PYTHON|3.8'
var appInsightsName = 'bookJournalAI-${uniqueString(resourceGroup().id)}'

param B2C_TENANT string
param B2C_CLIENT_ID string
param DOCKER_REGISTRY_SERVER_URL string
param DOCKER_REGISTRY_SERVER_USERNAME string
@secure()
param DOCKER_REGISTRY_SERVER_PASSWORD string

@secure()
param B2C_CLIENT_SECRET string

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
      ftpsState: 'Disabled'
      healthCheckPath: '/healthcheck'
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
          value: DOCKER_REGISTRY_SERVER_URL
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: DOCKER_REGISTRY_SERVER_USERNAME
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: DOCKER_REGISTRY_SERVER_PASSWORD
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
        {
          name: 'WEBSITE_SWAP_WARMUP_PING_PATH'
          value: '/healthcheck'
        }
        {
          name: 'WEBSITE_SWAP_WARMUP_PING_STATUSES'
          value: '200'
        }
        {
          name: 'WEBSITE_WARMUP_PATH'
          value: '/healthcheck'
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource stagingSlot 'Microsoft.Web/sites/slots@2022-03-01' = if (production) {
  parent: webApp
  name: 'staging'
  kind: 'app'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
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
    backupPolicy: {
      type: 'Continuous'
    }
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

output webAppName string = webAppName
