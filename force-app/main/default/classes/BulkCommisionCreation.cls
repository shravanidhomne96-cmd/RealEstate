global class BulkCommissionCreationBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id, Amount FROM Opportunity WHERE StageName = \'Closed Won\'');
    }
    
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Opportunity> oppList = (List<Opportunity>) scope;
        Set<Id> oppIds = new Set<Id>();
        
        for (Opportunity opp : oppList) {
            oppIds.add(opp.Id);
        }

        Set<Id> oppsWithCommission = new Set<Id>();
        for (Commission__c comm : [SELECT Opportunity__c FROM Commission__c WHERE Opportunity__c IN :oppIds]) {
            oppsWithCommission.add(comm.Opportunity__c);
        }

        List<Commission__c> commissionsToInsert = new List<Commission__c>();
        for (Opportunity opp : oppList) {
            if (!oppsWithCommission.contains(opp.Id)) {
                Commission__c comm = new Commission__c(
                    Opportunity__c = opp.Id,
                    Amount__c = opp.Amount,
                    Percent__c = 5
                );
                commissionsToInsert.add(comm);
            }
        }

        if (!commissionsToInsert.isEmpty()) {
            insert commissionsToInsert;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Bulk Commission Batch completed successfully');
    }
}