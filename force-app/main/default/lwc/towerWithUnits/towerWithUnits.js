import { LightningElement, api, wire, track } from 'lwc';
import getTowersWithUnits from '@salesforce/apex/TowerWithUnitsController.getTowersWithUnits';

export default class TowerWithUnits extends LightningElement {
    @api recordId;

    @track towers = [];
    @track error;
    isLoading = true;

    // Derived UI state getters
    get hasData() {
        return Array.isArray(this.towers) && this.towers.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.error && (!this.towers || this.towers.length === 0);
    }

    get errorMessage() {
        if (!this.error) return '';
        if (this.error.body && this.error.body.message) return this.error.body.message;
        if (this.error.message) return this.error.message;
        return 'An unexpected error occurred.';
    }

    @wire(getTowersWithUnits, { phaseId: '$recordId' })
    wiredTowers({ error, data }) {
        this.isLoading = false;
        if (data) {
            // Map data to add presentation fields used by the template (unitCountLabel, subUnitCountLabel, _expanded)
            this.towers = (data || []).map(t => {
                const units = Array.isArray(t.Property_Units__r) ? t.Property_Units__r : [];
                const unitCount = units.length;

                const mappedUnits = units.map(u => {
                    const subs = Array.isArray(u.Sub_Units__r) ? u.Sub_Units__r : [];
                    const subCount = subs.length;

                    // Derive friendly display details for Unit and Sub Units when fields exist
                    const unitDetails = {
                        type: u.Type__c || u.Unit_Type__c || '',
                        status: u.Status__c || u.Unit_Status__c || '',
                        area: u.Area__c || u.Built_Up_Area__c || ''
                    };
                    const hasUnitDetails = unitDetails.type || unitDetails.status || unitDetails.area;

                    const mappedSubs = subs.map(su => {
                        const suDetails = {
                            type: su.Type__c || su.Sub_Unit_Type__c || '',
                            status: su.Status__c || su.Sub_Unit_Status__c || '',
                            area: su.Area__c || su.Built_Up_Area__c || ''
                        };
                        const hasSuDetails = suDetails.type || suDetails.status || suDetails.area;
                        return {
                            ...su,
                            displayDetails: hasSuDetails ? suDetails : null
                        };
                    });

                    return {
                        ...u,
                        Sub_Units__r: mappedSubs,
                        _expanded: false,
                        subUnitCountLabel: `${subCount} ${subCount === 1 ? 'Sub Unit' : 'Sub Units'}`,
                        displayDetails: hasUnitDetails ? unitDetails : null
                    };
                });

                return {
                    ...t,
                    Property_Units__r: mappedUnits,
                    unitCountLabel: `${unitCount} ${unitCount === 1 ? 'Unit' : 'Units'}`
                };
            });
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.towers = [];
        }
    }

    handleToggleSubUnits(event) {
        const unitId = event.currentTarget.dataset.unitId;
        if (!unitId) return;

        // Find and toggle the unit in-place
        const towers = this.towers.map(t => {
            const units = (t.Property_Units__r || []).map(u => {
                if (u.Id === unitId) {
                    return { ...u, _expanded: !u._expanded };
                }
                return u;
            });
            return { ...t, Property_Units__r: units };
        });
        this.towers = towers;
    }
}
