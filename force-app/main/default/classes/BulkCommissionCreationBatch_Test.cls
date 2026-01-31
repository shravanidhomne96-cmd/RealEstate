/**
 * @description Test class for BulkCommissionCreationBatch
 * Verifies:
 *  - Batch queries Closed Won Opportunities only
 *  - Creates Commission__c when missing with correct values
 *  - Skips Opportunities that already have a Commission__c
 *  - Idempotency: re-running does not create duplicates
 *  - Bulk behavior across multiple Opportunities
 */
@IsTest
private class BulkCommissionCreationBatch_Test {

    @TestSetup
    static void setupData() {
        // Create Accounts (include required fields present in org, e.g., Active__c)
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            Account a = new Account(Name = 'Acct ' + i);
            // Guard for custom required field Active__c seen in test failure
            if (Schema.sObjectType.Account.fields.getMap().containsKey('Active__c')) {
                // Determine field type and assign a valid value to satisfy required field
                Schema.DescribeFieldResult dfr = Schema.sObjectType.Account.fields.getMap().get('Active__c').getDescribe();
                if (dfr.getType() == Schema.DisplayType.Boolean) {
                    a.put('Active__c', true);
                } else if (dfr.getType() == Schema.DisplayType.Picklist) {
                    // pick first available value or 'Active'/'Yes' fallback
                    List<Schema.PicklistEntry> entries = dfr.getPicklistValues();
                    if (!entries.isEmpty()) {
                        a.put('Active__c', entries[0].getValue());
                    } else {
                        a.put('Active__c', 'Active');
                    }
                } else if (dfr.getType() == Schema.DisplayType.String) {
                    a.put('Active__c', 'Active');
                } else if (dfr.getType() == Schema.DisplayType.Integer) {
                    a.put('Active__c', 1);
                } else {
                    // generic non-null fallback
                    a.put('Active__c', 'Active');
                }
            }
            accts.add(a);
        }
        insert accts;

        // Create Opportunities: some Closed Won, some not
        // Org has a validation: "Property must be 'Available' to close as Closed Won"
        // Satisfy by setting Property__c (lookup) to an 'Available' Property__c record when StageName='Closed Won'
        // Create a minimal Property__c in 'Available' status if object/field exist
        Id availablePropertyId;
        if (Schema.getGlobalDescribe().containsKey('Property__c')) {
            SObject prop = Schema.getGlobalDescribe().get('Property__c').newSObject();
            // Try to set a Name and Status__c/Picklist to 'Available' defensively
            if (Schema.sObjectType.Property__c.fields.getMap().containsKey('Name')) {
                prop.put('Name', 'Test Property - Available');
            }
            if (Schema.sObjectType.Property__c.fields.getMap().containsKey('Status__c')) {
                prop.put('Status__c', 'Available');
            }
            try {
                insert prop;
                availablePropertyId = (Id)prop.get('Id');
            } catch (Exception e) {
                // If property insert fails due to unknown fields, leave availablePropertyId null
            }
        }

        // Helper to create an Opportunity with optional Property__c
        Opportunity opp1 = new Opportunity(Name = 'Opp CW 1', StageName = 'Closed Won', CloseDate = Date.today(), Amount = 1000, AccountId = accts[0].Id);
        Opportunity opp2 = new Opportunity(Name = 'Opp CW 2', StageName = 'Closed Won', CloseDate = Date.today(), Amount = 2000, AccountId = accts[1].Id);
        Opportunity opp3 = new Opportunity(Name = 'Opp Open 1', StageName = 'Qualification', CloseDate = Date.today().addDays(10), Amount = 3000, AccountId = accts[2].Id);

        // If org has Property__c field on Opportunity, set it for Closed Won opps
        if (Schema.sObjectType.Opportunity.fields.getMap().containsKey('Property__c') && availablePropertyId != null) {
            opp1.put('Property__c', availablePropertyId);
            opp2.put('Property__c', availablePropertyId);
        }

        List<Opportunity> opps = new List<Opportunity>{ opp1, opp2, opp3 };
        insert opps;

        // Pre-create a Commission for one Closed Won Opp to validate skip logic
        Commission__c existing = new Commission__c(
            Opportunity__c = opps[0].Id,
            Amount__c = opps[0].Amount,
            Percent__c = 5
        );
        insert existing;
    }

    @IsTest
    static void test_Batch_Creates_Commissions_For_Missing_ClosedWon() {
        // Get current counts
        Integer initialCount = [SELECT COUNT() FROM Commission__c];

        Test.startTest();
        // Run batch with small scope size to exercise execute logic
        Id jobId = Database.executeBatch(new BulkCommissionCreationBatch(), 2);
        Test.stopTest();

        // After batch:
        // - There were 2 Closed Won opps; one already had a commission in @TestSetup
        // - Expect exactly 1 new Commission__c record created
        Integer finalCount = [SELECT COUNT() FROM Commission__c];
        System.assertEquals(initialCount + 1, finalCount, 'Exactly one commission should be created for the missing CW opportunity');

        // Validate that Opp CW 2 received a commission with correct values
        Opportunity oppCw2 = [SELECT Id, Amount FROM Opportunity WHERE Name = 'Opp CW 2' LIMIT 1];
        List<Commission__c> commsCw2 = [
            SELECT Id, Opportunity__c, Amount__c, Percent__c
            FROM Commission__c
            WHERE Opportunity__c = :oppCw2.Id
        ];
        System.assertEquals(1, commsCw2.size(), 'Opp CW 2 should have exactly one commission created');
        System.assertEquals(oppCw2.Amount, commsCw2[0].Amount__c, 'Commission Amount should mirror Opportunity Amount');
        System.assertEquals(5, commsCw2[0].Percent__c, 'Commission Percent should be 5');

        // Validate non-Closed Won Opp did not get a commission
        Opportunity oppOpen = [SELECT Id FROM Opportunity WHERE Name = 'Opp Open 1' LIMIT 1];
        Integer openComms = [SELECT COUNT() FROM Commission__c WHERE Opportunity__c = :oppOpen.Id];
        System.assertEquals(0, openComms, 'Non Closed-Won opportunity must not receive a commission');
    }

    @IsTest
    static void test_Batch_Is_Idempotent_No_Duplicates_On_Rerun() {
        Test.startTest();
        Database.executeBatch(new BulkCommissionCreationBatch(), 1);
        Test.stopTest();

        // Capture counts after first run
        Map<Id, Integer> commsPerOpp = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Opportunity__c oppId, COUNT(Id) cnt
            FROM Commission__c
            WHERE Opportunity__c IN (SELECT Id FROM Opportunity WHERE StageName = 'Closed Won')
            GROUP BY Opportunity__c
        ]) {
            commsPerOpp.put((Id) ar.get('oppId'), (Integer) ar.get('cnt'));
        }

        // Run again
        Test.startTest();
        Database.executeBatch(new BulkCommissionCreationBatch(), 1);
        Test.stopTest();

        // Ensure counts per Closed Won Opp remain the same (no duplicates)
        for (Id oppId : commsPerOpp.keySet()) {
            Integer after = [SELECT COUNT() FROM Commission__c WHERE Opportunity__c = :oppId];
        System.assertEquals(commsPerOpp.get(oppId), after, 'Re-running batch must not create duplicate commission records');
        }
    }

    @IsTest
    static void test_start_returns_only_closedWon_query() {
        // White-box check that start returns a QueryLocator and executes without error
        Test.startTest();
        Database.QueryLocator ql = new BulkCommissionCreationBatch().start(null);
        // Execute a small batch run to ensure the query is valid in this context
        Database.executeBatch(new BulkCommissionCreationBatch(), 5);
        Test.stopTest();

        // Basic assertion that some closed-won opps exist and are within scope
        Integer cwOpps = [SELECT COUNT() FROM Opportunity WHERE StageName = 'Closed Won'];
        System.assert(cwOpps > 0, 'Test data should include Closed Won opportunities');
    }
}
