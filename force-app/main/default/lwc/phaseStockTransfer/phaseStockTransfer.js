import { LightningElement, api, wire, track } from 'lwc';
import getAvailableStock from '@salesforce/apex/PhaseStockTransferController.getAvailableStock';
import transferStock from '@salesforce/apex/PhaseStockTransferController.transferStock';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class PhaseStockTransfer extends LightningElement {

    @api flowRecordId; // Source Phase Id
    @api destinationPhaseId; // Destination Phase Id (Flow se pass karo)

    @track stockData = [];
    error;
    wiredResult;

    // Fetch stock
    @wire(getAvailableStock, { phaseId: '$recordId' })
    wiredStock(result) {
        this.wiredResult = result;

        if (result.data) {
            this.stockData = result.data.map(item => {
                return { ...item, transferQty: 0 };
            });
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error.body.message;
        }
    }

    // Handle quantity change
    handleQtyChange(event) {
        const stockId = event.target.dataset.id;
        const value = parseFloat(event.target.value);

        this.stockData = this.stockData.map(item => {
            if (item.Id === stockId) {
                return { ...item, transferQty: value };
            }
            return item;
        });
    }

    // Transfer logic
    handleTransfer() {

        const selectedStock = this.stockData
            .filter(item => item.transferQty > 0)
            .map(item => {
                return {
                    stockId: item.Id,
                    inventoryItemId: item.Inventory_Item__c,
                    transferQty: item.transferQty
                };
            });

        if (selectedStock.length === 0) {
            this.showToast('Error', 'Enter at least one transfer quantity', 'error');
            return;
        }

        transferStock({
            sourcePhaseId: this.recordId,
            destinationPhaseId: this.destinationPhaseId,
            stockList: selectedStock
        })
        .then(() => {
            this.showToast('Success', 'Stock transferred successfully', 'success');
            return refreshApex(this.wiredResult);
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}
