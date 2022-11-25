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

var frontDoorEndpointName = 'afd-${uniqueString(resourceGroup().id)}'
var frontDoorSkuName = 'Standard_AzureFrontDoor'
var frontDoorProfileName = 'MyFrontDoor'
var frontDoorOriginGroupName = 'MyOriginGroup'
var frontDoorOriginName = 'MyAppServiceOrigin'
var frontDoorRouteName = 'MyRoute'

param B2C_TENANT string
param B2C_CLIENT_ID string
param DOCKER_REGISTRY_SERVER_URL string
param DOCKER_REGISTRY_SERVER_USERNAME string
@secure()
param DOCKER_REGISTRY_SERVER_PASSWORD string

@secure()
param B2C_CLIENT_SECRET string

resource frontDoorProfile 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: frontDoorProfileName
  location: 'global'
  sku: {
    name: frontDoorSkuName
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
      ftpsState: 'Disabled'
      healthCheckPath: '/healthcheck'
      ipSecurityRestrictions: [
        {
          tag: 'ServiceTag'
          ipAddress: 'AzureFrontDoor.Backend'
          action: 'Allow'
          priority: 100
          headers: {
            'x-azure-fdid': [
              frontDoorProfile.properties.frontDoorId
            ]
          }
          name: 'Allow traffic from Front Door'
        }
      ]
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
  name: '${webAppName}/staging'
  kind: 'app'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
  }
  dependsOn: [
    webApp
  ]
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2021-06-01' = {
  name: frontDoorEndpointName
  parent: frontDoorProfile
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource frontDoorOriginGroup 'Microsoft.Cdn/profiles/originGroups@2021-06-01' = {
  name: frontDoorOriginGroupName
  parent: frontDoorProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 100
    }
  }
}

resource frontDoorOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2021-06-01' = {
  name: frontDoorOriginName
  parent: frontDoorOriginGroup
  properties: {
    hostName: webApp.properties.defaultHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: webApp.properties.defaultHostName
    priority: 1
    weight: 1000
  }
}

resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2021-06-01' = {
  name: frontDoorRouteName
  parent: frontDoorEndpoint
  dependsOn: [
    frontDoorOrigin // This explicit dependency is required to ensure that the origin group is not empty when the route is created.
  ]
  properties: {
    originGroup: {
      id: frontDoorOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
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

output appServiceHostName string = webApp.properties.defaultHostName
output frontDoorEndpointHostName string = frontDoorEndpoint.properties.hostName
