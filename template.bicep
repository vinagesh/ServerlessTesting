@description('The resource Id of the managed Identity to use for deployment')
param managedIdentityForDeployment string

resource runscript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'enablesecurity'
  kind: 'AzureCLI'
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityForDeployment}' : {}
    }
  }
  properties: {
    azCliVersion: '2.9.1'
    retentionInterval: 'P1D'
    primaryScriptUri: 'https://raw.githubusercontent.com/vinagesh/ServerlessTesting/main/test.ps1'  
  }
}
