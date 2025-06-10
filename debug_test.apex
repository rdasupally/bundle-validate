// Test static resources availability
System.debug('=== Static Resources Debug ===');
List<StaticResource> resources = [SELECT Name, DeveloperName FROM StaticResource];
for(StaticResource sr : resources) {
    System.debug('Available: ' + sr.Name + ' (Dev: ' + sr.DeveloperName + ')');
}

// Test if schema static resource exists
try {
    StaticResource schemaResource = [SELECT Id, Body FROM StaticResource WHERE Name = 'schema' LIMIT 1];
    String schemaJson = schemaResource.Body.toString();
    System.debug('Schema JSON Length: ' + schemaJson.length());
    System.debug('Schema Preview: ' + schemaJson.substring(0, Math.min(200, schemaJson.length())));
    
    // Parse the JSON
    List<Object> schemaArray = (List<Object>) JSON.deserializeUntyped(schemaJson);
    System.debug('Schema entities count: ' + schemaArray.size());
    
    for(Object schemaObj : schemaArray) {
        Map<String, Object> schemaMap = (Map<String, Object>) schemaObj;
        System.debug('Entity: ' + schemaMap.get('Entity'));
        System.debug('Dependencies: ' + schemaMap.get('Dependancies'));
    }
    
} catch(Exception e) {
    System.debug('Schema test failed: ' + e.getMessage());
}

// Test object type detection
System.debug('=== Object Type Detection ===');
String[] testObjects = new String[]{'Account', 'Test__c', 'Test_Suite__c'};
for(String objName : testObjects) {
    Schema.SObjectType objType = Schema.getGlobalDescribe().get(objName);
    System.debug('Object ' + objName + ' exists: ' + (objType != null));
} 