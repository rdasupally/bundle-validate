@isTest
public class DataInsertTest {
    static Map<String, SObject> idToRecordMap = new Map<String, SObject>();
    
    @isTest
    public static void testDatainsert() {
        // read static resource schema.json
        try {
            StaticResource schemaResource = [SELECT Id, Body FROM StaticResource WHERE Name = 'schema'];
            String schemaJson = schemaResource.Body.toString();
            System.debug('Schema JSON loaded successfully. Length: ' + schemaJson.length());
            System.debug('Schema JSON content preview (first 500 chars): ' + schemaJson.substring(0, Math.min(500, schemaJson.length())));
            
            // parse schemaJson to JSON object according to the structure of the schema.json, json is an array of objects
            List<Object> schemaArray = (List<Object>) JSON.deserializeUntyped(schemaJson);
            System.debug('Schema parsed successfully. Number of entities: ' + schemaArray.size());
            
            List<String> processedEntities = new List<String>();
            Map<String, List<SObject>> allRecordsToInsert = new Map<String, List<SObject>>();
            
            for (Object schemaObject : schemaArray) {
                Map<String, Object> schemaMap = (Map<String, Object>) schemaObject;
                String entity = (String) schemaMap.get('Entity');
                List<Object> dependancies = (List<Object>) schemaMap.get('Dependancies');
                
                System.debug('Processing entity: ' + entity);
                System.debug('Entity structure: ' + JSON.serialize(schemaMap));
                
                for (Object dependancy : dependancies) {
                    try {
                        Map<String, Object> dependancyMap = (Map<String, Object>) dependancy;
                        String dependancyEntity = (String) dependancyMap.get('Entity');
                        String dependancyDataset = (String) dependancyMap.get('DataSet');
                        
                        System.debug('Processing dependency: ' + dependancyEntity + ' with dataset: ' + dependancyDataset);
                        
                        // Debug: Check if static resource exists
                        if (!staticResourceExists(dependancyDataset)) {
                            System.debug('WARNING: Static resource not found: ' + dependancyDataset);
                            continue;
                        }
                        
                        StaticResource dependancyResource = [SELECT Id, Body FROM StaticResource WHERE Name = :dependancyDataset];
                        String dataCsv = dependancyResource.Body.toString();
                        
                        System.debug('CSV data loaded for ' + dependancyDataset + '. Length: ' + dataCsv.length());
                        System.debug('CSV preview (first 200 chars): ' + dataCsv.substring(0, Math.min(200, dataCsv.length())));
                        
                        // Create sObjects dynamically from CSV data
                        List<SObject> dynamicRecords = createSObjectsFromCSV(dependancyEntity, dataCsv);
                        
                        if (!dynamicRecords.isEmpty()) {
                            // Store records for batch insertion
                            if (!allRecordsToInsert.containsKey(dependancyEntity)) {
                                allRecordsToInsert.put(dependancyEntity, new List<SObject>());
                            }
                            
                            allRecordsToInsert.get(dependancyEntity).addAll(dynamicRecords);
                            System.debug('Prepared ' + dynamicRecords.size() + ' records for ' + dependancyEntity);
                        } else {
                            System.debug('No records created for ' + dependancyEntity);
                        }
                        
                    } catch (Exception e) {
                        System.debug('Error processing dependency: ' + e.getMessage());
                        System.debug('Stack trace: ' + e.getStackTraceString());
                    }
                }
            }
            
            // Debug summary before insertion
            System.debug('=== Final Summary Before Insertion ===');
            System.debug('Total entity types to insert: ' + allRecordsToInsert.size());
            for (String entityType : allRecordsToInsert.keySet()) {
                System.debug('Entity: ' + entityType + ', Records: ' + allRecordsToInsert.get(entityType).size());
                for (SObject record : allRecordsToInsert.get(entityType)) {
                    System.debug('Record: ' + record);
                }
            }
            
            // Batch insert all records by entity type
            insertRecordsByEntity(allRecordsToInsert);

            for (String entityType : allRecordsToInsert.keySet()) {
                System.debug('inserted Entity: ' + entityType + ', Records: ' + allRecordsToInsert.get(entityType).size());
                for (SObject record : allRecordsToInsert.get(entityType)) {
                    System.debug('inserted Record: ' + record);
                }
            }
            
            // Update idToRecordMap with Salesforce IDs after insertion
            updateIdToRecordMapWithSalesforceIds();
            
            // Now we need to map the Test_Suite_Test__c field with respective Test_Suite__c and Test__c ids dynamically
            createJunctionRecords();
            
            
        } catch (Exception e) {
            System.debug('FATAL ERROR in testDatainsert: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw e; // Re-throw to make test fail if there's a critical error
        }
        
        System.debug('=== DataInsert Test Completed ===');
    }
    
    
    // Helper method to check if static resource exists
    private static Boolean staticResourceExists(String resourceName) {
        try {
            List<StaticResource> resources = [SELECT Id FROM StaticResource WHERE Name = :resourceName LIMIT 1];
            return !resources.isEmpty();
        } catch (Exception e) {
            System.debug('Error checking static resource existence: ' + e.getMessage());
            return false;
        }
    }
    
    // Helper method to insert records in batches by entity type
    private static void insertRecordsByEntity(Map<String, List<SObject>> recordsByEntity) {
        for (String entityType : recordsByEntity.keySet()) {
            List<SObject> records = recordsByEntity.get(entityType);
            try {
                insert records;
                System.debug('Successfully inserted ' + records.size() + ' records for ' + entityType);
                
            } catch (DmlException e) {
                System.debug('DML Error inserting records for ' + entityType + ':' + e.getMessage());
                for (Integer i = 0; i < e.getNumDml(); i++) {
                    System.debug('  Record ' + i + ': ' + e.getDmlMessage(i));
                }
            } catch (Exception e) {
                System.debug('General error inserting records for ' + entityType + ': ' + e.getMessage());
            }
        }
    }
    
    // Helper method to update idToRecordMap with Salesforce IDs after insertion
    private static void updateIdToRecordMapWithSalesforceIds() {
        try {
            System.debug('Updating idToRecordMap with Salesforce IDs after insertion');
            System.debug('idToRecordMap size before update: ' + idToRecordMap.size());
            
            // The records in idToRecordMap now have their Salesforce IDs populated after insert
            for (String externalId : idToRecordMap.keySet()) {
                SObject record = idToRecordMap.get(externalId);
                Id salesforceId = record.Id;
                System.debug('External ID "' + externalId + '" -> Salesforce ID "' + salesforceId + '"');
            }
            
        } catch (Exception e) {
            System.debug('Error updating idToRecordMap: ' + e.getMessage());
        }
    }
    
    // Helper method to create sObjects dynamically from CSV data
    // Assumes objects are available during validation deployment
    public static List<SObject> createSObjectsFromCSV(String objectType, String csvData) {
        System.debug('=== createSObjectsFromCSV Debug Start ===');
        System.debug('Object Type: ' + objectType);
        System.debug('CSV Data Length: ' + (csvData != null ? csvData.length() + '': 'null'));
        
        List<SObject> records = new List<SObject>();
        
        if (String.isBlank(csvData) || String.isBlank(objectType)) {
            System.debug('Invalid input: objectType=' + objectType + ', csvData is blank=' + String.isBlank(csvData));
            return records;
        }
        
        try {
            // Try to get sObject type - first from global describe, then from Type.forName for local objects
            System.debug('Attempting to get SObject type for: ' + objectType);
            Schema.SObjectType sObjectType = getSObjectType(objectType);
            if (sObjectType == null) {
                System.debug('Object type not found: ' + objectType + '. Available objects: ' + getAvailableCustomObjects());
                return records;
            }
            System.debug('SObject type found successfully: ' + sObjectType);
            
            // Get field information for validation - handle cases where describe might not be available
            Map<String, Schema.SObjectField> fieldsMap = new Map<String, Schema.SObjectField>();
            try {
                Schema.DescribeSObjectResult objectDescribe = sObjectType.getDescribe();
                fieldsMap = objectDescribe.fields.getMap();
            } catch (Exception describeEx) {
                System.debug('Cannot describe object ' + objectType + '. Will attempt field setting without validation: ' + describeEx.getMessage());
            }
            
            System.debug('Processing CSV for object: ' + objectType + ' with ' + fieldsMap.size() + ' available fields');
            System.debug('Fields Map: ' + fieldsMap);
            
            List<String> lines = csvData.split('\n');
            if (lines.isEmpty()) {
                System.debug('CSV data is empty for object: ' + objectType);
                return records;
            }
            
            // Parse headers and validate
            String headersString = lines[0].trim();
            List<String> headers = headersString.split(',');
            
            // Clean headers (remove BOM, quotes, whitespace)
            for (Integer i = 0; i < headers.size(); i++) {
                headers[i] = cleanFieldName(headers[i]);
            }
            
            System.debug('CSV headers for ' + objectType + ': ' + headers);
            
            // Validate headers against object fields
            Set<String> validHeaders = validateHeaders(headers, fieldsMap);
            if (validHeaders.isEmpty()) {
                System.debug('No valid headers found for object: ' + objectType);
                return records;
            }

            System.debug('Valid headers: ' + validHeaders);
            
            // Process each data row
            for (Integer i = 1; i < lines.size(); i++) {
                String dataLine = lines[i].trim();
                if (String.isBlank(dataLine)) continue;
                
                System.debug('Data line: ' + dataLine);
                List<String> dataValues = parseCSVLine(dataLine);
                System.debug('Data values: ' + dataValues);
                // Create new sObject instance dynamically
                SObject record = sObjectType.newSObject();
                Boolean hasValidData = false;
                
                String externalId = '';
                // Populate fields dynamically
                for (Integer j = 0; j < headers.size() && j < dataValues.size(); j++) {
                    if (headers[j].toLowerCase() == 'id') {
                        externalId = dataValues[j];
                        continue;
                    }

                    if (!validHeaders.contains(headers[j])) {
                        continue;
                    }
                    String fieldName = headers[j];
                    String fieldValue = dataValues[j];
                    
                    if (String.isNotBlank(fieldName) && String.isNotBlank(fieldValue)) {
                        if (setFieldValue(record, fieldName, fieldValue, fieldsMap)) {
                            hasValidData = true;
                        }
                    }
                }
                
                // Only add record if it has at least some valid data
                if (hasValidData) {
                    idToRecordMap.put(externalId, record);
                    records.add(record);
                }
            }
            
            System.debug('Created ' + records.size() + ' records from CSV for ' + objectType);
            
        } catch (Exception e) {
            System.debug('Error creating sObjects from CSV for ' + objectType + ': ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
        
        return records;
    }
    
    // Helper method to clean field names
    private static String cleanFieldName(String fieldName) {
        if (String.isBlank(fieldName)) return '';
        
        // Remove BOM, quotes, and extra whitespace
        return fieldName.trim().replace('"', '').replace('\uFEFF', '');
    }
    
    // Helper method to validate headers against object fields
    private static Set<String> validateHeaders(List<String> headers, Map<String, Schema.SObjectField> fieldsMap) {
        Set<String> validHeaders = new Set<String>();
        
        for (String header : headers) {
            System.debug('Validating header: ' + header);
            if (String.isNotBlank(header)) {
                // If we have field metadata, validate against it
                // skip id field
                if (header.toLowerCase() == 'id') {
                    continue;
                }
                if (!fieldsMap.isEmpty() && fieldsMap.containsKey(header.toLowerCase())) {
                    try {
                        Schema.SObjectField field = fieldsMap.get(header.toLowerCase());
                        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                        
                        validHeaders.add(header);
                        // if (fieldDescribe.isCreateable() || fieldDescribe.isUpdateable()) {
                        //     validHeaders.add(header);
                        // } else {
                        //     System.debug('Field not createable/updateable: ' + header);
                        // }
                    } catch (Exception e) {
                        System.debug('Could not describe field ' + header + ', adding anyway: ' + e.getMessage());
                        validHeaders.add(header); // Add field even if we can't describe it
                    }
                } else if (fieldsMap.isEmpty()) {
                    // If we don't have field metadata (local objects), accept all headers
                    validHeaders.add(header);
                    System.debug('No field metadata available, accepting header: ' + header);
                } else {
                    System.debug('Invalid or non-existent field: ' + header);
                }
            }
        }
        
        return validHeaders;
    }
    
    // Helper method to parse CSV line with proper comma handling
    private static List<String> parseCSVLine(String line) {
        List<String> values = new List<String>();
        String[] splitValues = line.split(',');
        
        for (String value : splitValues) {
            values.add(value.trim().replace('"', ''));
        }
        
        return values;
    }
    
    // Helper method to set field value with proper type conversion
    private static Boolean setFieldValue(SObject record, String fieldName, String fieldValue, Map<String, Schema.SObjectField> fieldsMap) {
        try {
            Object convertedValue = fieldValue; // Default to string value
            
            // If we have field metadata, use it for type conversion
            if (!fieldsMap.isEmpty() && fieldsMap.containsKey(fieldName.toLowerCase())) {
                try {
                    System.debug('Setting object:' + record.getSObjectType() + ' field:' + fieldName + ' value:' + fieldValue);
                    Schema.SObjectField field = fieldsMap.get(fieldName.toLowerCase());
                    Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                    convertedValue = convertFieldValue(fieldValue, fieldDescribe.getType());
                } catch (Exception fieldEx) {
                    System.debug('Could not get field type for ' + fieldName + ', using string value: ' + fieldEx.getMessage());
                    convertedValue = fieldValue;
                }
            } else {
                // For local objects without metadata, try intelligent type conversion
                convertedValue = convertFieldValueIntelligently(fieldValue);
            }
            
            record.put(fieldName, convertedValue);
            return true;
        } catch (Exception e) {
            System.debug('Error setting field ' + fieldName + ' with value ' + fieldValue + ': ' + e.getMessage());
            return false;
        }
    }
    
    // Helper method to get SObject type - handles both deployed and local objects
    private static Schema.SObjectType getSObjectType(String objectType) {
        System.debug('getSObjectType called for: ' + objectType);
        
        // First try global describe (for deployed objects)
        System.debug('Trying Schema.getGlobalDescribe() for: ' + objectType);
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectType);
        
        if (sObjectType != null) {
            System.debug('Found via global describe: ' + sObjectType);
            return sObjectType;
        }
        System.debug('Not found in global describe, trying Type.forName');
        
        // If not found in global describe, try Type.forName for local objects
        try {
            Type objectTypeClass = Type.forName(objectType);
            if (objectTypeClass != null) {
                System.debug('Type.forName found: ' + objectTypeClass);
                // For custom objects, try to get the SObjectType through reflection
                Object instance = objectTypeClass.newInstance();
                if (instance instanceof SObject) {
                    return ((SObject) instance).getSObjectType();
                }
            } else {
                System.debug('Type.forName not found: ' + objectTypeClass);
            }
        } catch (Exception e) {
            System.debug('Could not create instance of ' + objectType + ' via Type.forName: ' + e.getMessage());
        }
        
        // Last resort: try to create the object directly if it's a standard object
        try {
            if (objectType.equalsIgnoreCase('Account')) {
                return Account.SObjectType;
            } else if (objectType.equalsIgnoreCase('Contact')) {
                return Contact.SObjectType;
            } else if (objectType.equalsIgnoreCase('Opportunity')) {
                return Opportunity.SObjectType;
            } else if (objectType.equalsIgnoreCase('Lead')) {
                return Lead.SObjectType;
            } else if (objectType.equalsIgnoreCase('Case')) {
                return Case.SObjectType;
            }
            // Add more standard objects as needed
        } catch (Exception e) {
            System.debug('Could not get standard object type for ' + objectType + ': ' + e.getMessage());
        }
        
        return null;
    }

    // Helper method to get available custom objects for debugging
    private static String getAvailableCustomObjects() {
        List<String> customObjects = new List<String>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        
        for (String objectName : globalDescribe.keySet()) {
            if (objectName.endsWith('__c')) {
                customObjects.add(objectName);
            }
        }
        
        return String.join(customObjects, ', ');
    }
    
    // Enhanced field value conversion with better error handling
    private static Object convertFieldValue(Object value, Schema.DisplayType fieldType) {
        if (value == null) return null;
        
        String stringValue = String.valueOf(value).trim();
        if (String.isBlank(stringValue) || stringValue.toLowerCase() == 'null') return null;
        
        try {
            switch on fieldType {
                when BOOLEAN {
                    return Boolean.valueOf(stringValue) || stringValue.toLowerCase() == 'true' || stringValue == '1';
                }
                when INTEGER {
                    return Integer.valueOf(stringValue);
                }
                when DOUBLE, CURRENCY, PERCENT {
                    return Decimal.valueOf(stringValue);
                }
                when DATE {
                    // Support multiple date formats
                    if (stringValue.contains('/')) {
                        List<String> parts = stringValue.split('/');
                        if (parts.size() == 3) {
                            return Date.newInstance(Integer.valueOf(parts[2]), Integer.valueOf(parts[0]), Integer.valueOf(parts[1]));
                        }
                    }
                    return Date.valueOf(stringValue);
                }
                when DATETIME {
                    return DateTime.valueOf(stringValue);
                }
                when REFERENCE {
                    // For lookup fields, assume the value is an ID
                    if (stringValue.length() == 15 || stringValue.length() == 18) {
                        return stringValue;
                    }
                    return null;
                }
                when else {
                    return stringValue;
                }
            }
        } catch (Exception e) {
            System.debug('Error converting field value "' + stringValue + '" to type ' + fieldType + ': ' + e.getMessage());
            return stringValue; // Return as string if conversion fails
        }
    }
    
    // Intelligent field value conversion when field metadata is not available
    private static Object convertFieldValueIntelligently(String value) {
        if (String.isBlank(value) || value.toLowerCase() == 'null') return null;
        
        String trimmedValue = value.trim();
        
        // Try boolean conversion
        if (trimmedValue.toLowerCase() == 'true' || trimmedValue.toLowerCase() == 'false' || trimmedValue == '1' || trimmedValue == '0') {
            try {
                return Boolean.valueOf(trimmedValue) || trimmedValue == '1';
            } catch (Exception e) {
                // Continue to next type
            }
        }
        
        // Try integer conversion
        if (trimmedValue.isNumeric() && !trimmedValue.contains('.')) {
            try {
                return Integer.valueOf(trimmedValue);
            } catch (Exception e) {
                // Continue to next type
            }
        }
        
        // Try decimal conversion
        if (trimmedValue.isNumeric()) {
            try {
                return Decimal.valueOf(trimmedValue);
            } catch (Exception e) {
                // Continue to next type
            }
        }
        
        // Try date conversion (various formats)
        if (trimmedValue.contains('/') || trimmedValue.contains('-')) {
            try {
                if (trimmedValue.contains('/')) {
                    List<String> parts = trimmedValue.split('/');
                    if (parts.size() == 3) {
                        return Date.newInstance(Integer.valueOf(parts[2]), Integer.valueOf(parts[0]), Integer.valueOf(parts[1]));
                    }
                }
                return Date.valueOf(trimmedValue);
            } catch (Exception e) {
                // Continue to next type
            }
        }
        
        // Check if it looks like a Salesforce ID
        if (trimmedValue.length() == 15 || trimmedValue.length() == 18) {
            Pattern idPattern = Pattern.compile('[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?');
            if (idPattern.matcher(trimmedValue).matches()) {
                return trimmedValue; // Return as ID
            }
        }
        
        // Default to string
        return trimmedValue;
    }
    
    // Helper method to create sObject with fields
    public static SObject createSObjectWithFields(String objectType, Map<String, Object> fieldValues) {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectType);
        if (sObjectType != null) {
            SObject sObj = sObjectType.newSObject();
            for (String fieldName : fieldValues.keySet()) {
                sObj.put(fieldName, fieldValues.get(fieldName));
            }
            return sObj;
        }
        return null;
    }
    
    // Helper method to create junction records dynamically after parent records are inserted
    private static void createJunctionRecords() {
        System.debug('=== Creating Junction Records ===');
        
        try {
            // For simplicity, let's focus on creating Test_Suite_Test__c junction records
            // You can expand this logic for other junction objects
            String junctionObjectType = 'Test_Suite_Test__c';
            
            if (isJunctionObject(junctionObjectType)) {
                System.debug('Processing junction object: ' + junctionObjectType);
                processJunctionObject(junctionObjectType);
            }
            
        } catch (Exception e) {
            System.debug('Error creating junction records: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
    }
    
    // Helper method to determine if an object is a junction object
    private static Boolean isJunctionObject(String objectType) {
        try {
            // Get the object's fields to check for multiple master-detail relationships
            Schema.SObjectType sObjectType = getSObjectType(objectType);
            if (sObjectType == null) return false;
            
            Schema.DescribeSObjectResult objectDescribe = sObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldsMap = objectDescribe.fields.getMap();
            
            Integer masterDetailCount = 0;
            for (Schema.SObjectField field : fieldsMap.values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && 
                    fieldDescribe.isCustom() && 
                    !fieldDescribe.isNillable()) {
                    masterDetailCount++;
                }
            }
            
            // Junction objects typically have 2 or more master-detail relationships
            return masterDetailCount >= 2;
            
        } catch (Exception e) {
            System.debug('Error determining if ' + objectType + ' is a junction object: ' + e.getMessage());
            return false;
        }
    }
    
    // Helper method to process a junction object and create its records
    private static void processJunctionObject(String junctionObjectType) {
        try {
            // Construct the static resource name for the junction object
            String baseObjectName = junctionObjectType.replace('__c', '');
            String resourceName = findJunctionStaticResource(baseObjectName);
            
            if (String.isBlank(resourceName)) {
                System.debug('No static resource found for junction object: ' + junctionObjectType);
                return;
            }
            
            // Get the junction CSV data
            StaticResource junctionResource = [SELECT Id, Body FROM StaticResource WHERE Name = :resourceName];
            String junctionCsv = junctionResource.Body.toString();
            
            System.debug('Junction CSV data loaded for ' + junctionObjectType + '. Length: ' + junctionCsv.length());
            
            // Parse the junction CSV and create records dynamically
            List<SObject> junctionRecords = createJunctionRecordsFromCSV(junctionObjectType, junctionCsv);
            
            if (!junctionRecords.isEmpty()) {
                System.debug('Inserting ' + junctionRecords.size() + ' junction records for ' + junctionObjectType);
                insert junctionRecords;
                System.debug('Successfully inserted junction records for ' + junctionObjectType);
            } else {
                System.debug('No junction records to insert for ' + junctionObjectType);
            }
            
        } catch (Exception e) {
            System.debug('Error processing junction object ' + junctionObjectType + ': ' + e.getMessage());
        }
    }
    
    // Helper method to find the static resource name for a junction object
    private static String findJunctionStaticResource(String baseObjectName) {
        try {
            // Try common naming patterns
            List<String> possibleNames = new List<String>{
                baseObjectName.toLowerCase() + 's',
                baseObjectName.toLowerCase(),
                baseObjectName.replace('_', '').toLowerCase() + 's',
                baseObjectName.replace('_', '').toLowerCase(),
                'Testsuitetests' // Specific fallback for the current case
            };
            
            for (String possibleName : possibleNames) {
                if (staticResourceExists(possibleName)) {
                    System.debug('Found static resource: ' + possibleName + ' for junction object: ' + baseObjectName);
                    return possibleName;
                }
            }
            
            System.debug('No static resource found for junction object base name: ' + baseObjectName);
            return null;
            
        } catch (Exception e) {
            System.debug('Error finding static resource for ' + baseObjectName + ': ' + e.getMessage());
            return null;
        }
    }
    
    // Simplified method to create junction records from CSV
    private static List<SObject> createJunctionRecordsFromCSV(String junctionObjectType, String csvData) {
        List<SObject> junctionRecords = new List<SObject>();
        
        try {
            // Get the junction object SObject type
            Schema.SObjectType junctionSObjectType = getSObjectType(junctionObjectType);
            if (junctionSObjectType == null) {
                System.debug('Could not get SObject type for: ' + junctionObjectType);
                return junctionRecords;
            }
            
            // Get the junction object's field information
            Schema.DescribeSObjectResult objectDescribe = junctionSObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldsMap = objectDescribe.fields.getMap();
            
            // Parse CSV
            List<String> lines = csvData.split('\n');
            if (lines.isEmpty()) {
                System.debug('Junction CSV data is empty');
                return junctionRecords;
            }
            
            // Parse and clean headers
            String headersString = lines[0].trim();
            List<String> headers = headersString.split(',');
            for (Integer i = 0; i < headers.size(); i++) {
                headers[i] = cleanFieldName(headers[i]);
            }
            
            System.debug('Junction CSV headers: ' + headers);
            
            // Process each data row
            for (Integer i = 1; i < lines.size(); i++) {
                String dataLine = lines[i].trim();
                if (String.isBlank(dataLine)) continue;
                
                List<String> dataValues = parseCSVLine(dataLine);
                SObject junctionRecord = junctionSObjectType.newSObject();
                Boolean hasValidReferences = false;
                
                // Process each field
                for (Integer j = 0; j < headers.size() && j < dataValues.size(); j++) {
                    String fieldName = headers[j];
                    String fieldValue = dataValues[j];
                    
                    if (String.isBlank(fieldName) || String.isBlank(fieldValue)) continue;
                    
                    try {
                        // Check if this field is a reference field and if we have the referenced record
                        if (fieldsMap.containsKey(fieldName.toLowerCase())) {
                            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName.toLowerCase()).getDescribe();
                            
                            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                                // This is a reference field - try to find the referenced record
                                if (idToRecordMap.containsKey(fieldValue)) {
                                    SObject referencedRecord = idToRecordMap.get(fieldValue);
                                    Id salesforceId = referencedRecord.Id;
                                    if (salesforceId != null) {
                                        junctionRecord.put(fieldName, salesforceId);
                                        hasValidReferences = true;
                                        System.debug('Set reference field ' + fieldName + ' = ' + salesforceId + ' (from external ID: ' + fieldValue + ')');
                                    }
                                }
                            } else {
                                // Regular field
                                junctionRecord.put(fieldName, fieldValue);
                                System.debug('Set regular field ' + fieldName + ' = ' + fieldValue);
                            }
                        }
                    } catch (Exception e) {
                        System.debug('Error setting field ' + fieldName + ': ' + e.getMessage());
                    }
                }
                
                if (hasValidReferences) {
                    junctionRecords.add(junctionRecord);
                    System.debug('Created junction record: ' + junctionRecord);
                }
            }
            
        } catch (Exception e) {
            System.debug('Error creating junction records from CSV for ' + junctionObjectType + ': ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
        
        return junctionRecords;
    }
}