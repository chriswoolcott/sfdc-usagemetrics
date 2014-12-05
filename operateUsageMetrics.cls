global class operateUsageMetrics implements Database.Batchable<sObject> {
	public String query;
	
	global Database.QueryLocator start (Database.BatchableContext BC) {
		return Database.getQueryLocator(query);
	}
	
	global void execute (Database.BatchableContext BC, List<MetricsDataFile> fileList) {
		//Get Record Types Once, not per each Metric as this will hit governor limits.
		Map<String, Id> rMap = new Map<String, Id>();
		for(RecordType r: [select Id, Name from RecordType where SObjectType = 'Metric__c']){
			rMap.put(r.Name, r.Id);
		}
		// Maps and Lists of objects to be upsert-ed – includes new data
		//Map containing existing (queried) and new daily customer metric records.
		Map<String, Daily_Customer_Metric__c> dcmMap = new Map<String, Daily_Customer_Metric__c>();
		//list to hold new DCMs for insert.
		Daily_Customer_Metric__c[] dcmList = new Daily_Customer_Metric__c[]{};
		List<Metric__c> allNewMetrics = new List<Metric__c>();
		//keys of potential Daily Customer Metric records that we want to query for.
		Set<String> keySet = new Set<String>();
		for (MetricsDataFile f : fileList) {
			// Split MetricsDataFile
			String[] arrayOfMetrics = ((f.MetricsDataFile).toString()).split('\n');
			for (String s : arrayOfMetrics) {
				// Remove quotations in each field value
				String cleanValues = s.remove('"');
				String[] metricsValues = cleanValues.split(',');
				// (Check allDailyCustomers Map)
				// Key is OrgID + Date
				//Check the file has some data, there seems to be blank rows returned in the results.
				if(metricsValues.size() > 1){
					String key = f.NamespacePrefix+' - '+metricsValues[0] + ' - ' + (f.MetricsStartDate).format();
					//add the key to a set, we will use this to query for existing Customer records later.
					keySet.add(key);
					// Perform data insertion of metrics
					Metric__c newMetric = new Metric__c();
					// Visualforce Page Metric
					if (f.MetricsType == 'Visualforce') {
						newMetric.Name = metricsValues[5];
						// Setting unique key (external ID)
						newMetric.Resource_Name__c = f.NamespacePrefix+' - '+(f.MetricsStartDate).date() + ' - ' +
						metricsValues[0] + ' - ' + metricsValues[5];
						newMetric.RecordTypeId = rMap.get('Visualforce Page');
						newMetric.Org_ID__c = metricsValues[0];
						newMetric.Namespace__c = f.NamespacePrefix;
						newMetric.Date__c = f.MetricsStartDate;
						//Indexes updated as they were wrong.
						newMetric.Total_Page_Views__c = Integer.valueOf(metricsValues[6]);
						newMetric.Unique_Users__c = Integer.valueOf(metricsValues[7]);
						newMetric.Avg_Load_Time__c = Integer.valueOf(metricsValues[8]);
					} 
					else if(f.MetricsType == 'CustomObject'){
						// Custom Object Metric 
						newMetric.Name =metricsValues[5];
						//Setting unique key(external ID)
						newMetric.Resource_Name__c = f.NamespacePrefix+' - '+(f.MetricsStartDate).date() + ' - ' +
						metricsValues[0] + ' - ' + metricsValues[5];
						newMetric.RecordTypeId = rMap.get('Custom Object');
						newMetric.Org_ID__c = metricsValues[0];
						newMetric.Namespace__c = f.NamespacePrefix;
						newMetric.Date__c = f.MetricsStartDate;
						//Indexes updated as they were wrong.
						newMetric.Total_Object_Records__c = Integer.valueOf(metricsValues[6]);
					}
					allNewMetrics.add(newMetric);
				}
			}
		}
		//At this point Metrics have been processed, no we need to query for existing DCMs and update (reparentable?) Master Detail
		//query for DCM's and update map.
		for(Daily_Customer_Metric__c dcm: [select Id, Key__c from Daily_Customer_Metric__c where Key__c in: keySet]){
			dcmMap.put(dcm.Key__c, dcm);
		}
		
		//reloop therough the MetricsDataFileRecords, create and DCM's that are missing.
		for (MetricsDataFile f : fileList) {
			// Split MetricsDataFile
			String[] arrayOfMetrics = ((f.MetricsDataFile).toString()).split('\n');
			for (String s : arrayOfMetrics) {
				// Remove quotations in each field value
				String cleanValues = s.remove('"');
				String[] metricsValues = cleanValues.split(',');
				// (Check allDailyCustomers Map)
				// Key is Namespace + OrgID + Date
				//Check the file has some data, there seems to be blank rows returned in the results.
				if(metricsValues.size() > 1){
					String key = f.NamespacePrefix+' - '+metricsValues[0] + ' - ' + (f.MetricsStartDate).format();
					if(!dcmMap.containsKey(key)){
						//doesn't contain the DCM, so create a new one.
						Daily_Customer_Metric__c dcm = new Daily_Customer_Metric__c();
						dcm.Key__c = key;
						dcm.Date__c = f.MetricsStartDate;
						dcm.Org_ID__c = metricsValues[0];
						dcm.Application_Name__c = f.NamespacePrefix;
						dcm.Customer_Name__c = metricsValues[1];
						dcm.Name = metricsValues[1] + ' - ' +
						(f.MetricsStartDate.date()).format();
						dcmMap.put(key, dcm);
						//add to list for insert
						dcmList.add(dcm);
					}
				}
			}
		}
		//insert the new DCMs
		insert dcmList;
		Metric__c[] upsertMetrics = new Metric__c[]{};
		//loop through metrics and assign DCM relationships
		for(Metric__c m: allNewMetrics){
			//create the key.
			string key = m.Namespace__c+' - '+m.Org_ID__c +' - '+m.Date__c.format();
			//if the DCM lookup is null, update it.
			if(m.Daily_Customer_Metric__c == null && dcmMap.get(key) != null && dcmMap.get(key).Id != null){
				m.Daily_Customer_Metric__c = dcmMap.get(key).Id;
				//add to list for insert.
				upsertMetrics.add(m);
			}
		}
		
		upsert upsertMetrics Resource_Name__c;
	}
	global void finish (Database.BatchableContext BC) {
	// Do nothing
	}
}