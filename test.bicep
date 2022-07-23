param StorageAccountName string
param RunCsxContent string
param ProjContent string
param FunctionRuntime string
param NetFrameWorkVersion string
param Use32BitWorker bool

param ApplicationInsightsName string = '${resourceGroup().name}-ai'
param ServerFarmName string = '${resourceGroup().name}-srv'
param EventHubNamespaceName string = '${resourceGroup().name}-ehn'
param EventHubName string = '${resourceGroup().name}-eh'
param WebsiteName string = '${resourceGroup().name}-web'
param FunctionName string = 'HelloWorld'

param SubscriptionId string = subscription().id
param RgName string = resourceGroup().name
param Location string = resourceGroup().location

resource applicationInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: ApplicationInsightsName
  kind: 'web'
  location: Location
  properties: {
    Application_Type: 'web'
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: StorageAccountName
  location: Location
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

resource serverfarm 'Microsoft.Web/serverfarms@2018-11-01' = {
  name: ServerFarmName
  location: Location
  kind: ''
  properties: {
    name: ServerFarmName
  }
  sku: {
    tier: 'Standard'
    name: 'S1'
  }
}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' = {
  name: EventHubNamespaceName
  location: Location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' = {
  name: '${EventHubNamespaceName}/${EventHubName}'
  properties: {
    messageRetentionInDays: 7
    partitionCount: 1
  }
  dependsOn: [
    eventHubNamespace
  ]
}

param EventHubAuthRuleResourceId string = 'Microsoft.EventHub/namespaces/${EventHubNamespaceName}/authorizationRules/RootManageSharedAccessKey'

resource website 'Microsoft.Web/sites@2018-11-01' = {
  name: WebsiteName
  location: Location
  kind: 'functionapp'
  tags: {
    'hidden-link: /app-insights-resource-id': '/subscriptions/${SubscriptionId}/resourceGroups/${RgName}/providers/Microsoft.Insights/components/${applicationInsights.name}'
  }
  properties: {
    name: WebsiteName
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: FunctionRuntime
        }        
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: '${reference(applicationInsights.id, '2015-05-01').InstrumentationKey}'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: '${reference(applicationInsights.id, '2015-05-01').ConnectionString}'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccountName};AccountKey=${listkeys(storageAccount.id, '2019-06-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'SERVERLESS_SECURITY_ENABLED'
          value: 'true'
        }
        {
          name: 'SERVERLESS_SECURITY_LOG_CONFIG'
          value: '${reference(applicationInsights.id, '2015-05-01').InstrumentationKey}'
        }
        {
          name: 'SERVERLESS_SECURITY_EVENT_HUB_NAME'
          value: EventHubName
        }
        {
          name: 'SERVERLESS_SECURITY_EVENT_HUB_CONNECTION_STRING'
          value: listkeys(EventHubAuthRuleResourceId, '2015-08-01').primaryConnectionString
        }
      ]      
      use32BitWorkerProcess: Use32BitWorker      
      alwaysOn: true
      netFrameworkVersion: NetFrameWorkVersion
      ftpsState: 'FtpsOnly'
    }
    serverFarmId: serverfarm.id
    httpsOnly: true
  }
  dependsOn: [
    eventHub
  ]
}

resource functions 'Microsoft.Web/sites/functions@2018-11-01' = {
  name: '${website.name}/${FunctionName}'
  properties: {
    config: {
      bindings: [
        {
          name: 'req'
          type: 'httpTrigger'
          direction: 'in'
          schedule: FunctionName
        }
        {
          name: '$return'
          type: 'http'
          direction: 'out'
        }
      ]
      disabled: false
    }
    files: {
      'run.csx': base64ToString((RunCsxContent))
      'function.proj': base64ToString(ProjContent)
    }
  }
}
