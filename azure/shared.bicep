param location string = resourceGroup().location
var acrName = 'acr${uniqueString(resourceGroup().id)}'

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
