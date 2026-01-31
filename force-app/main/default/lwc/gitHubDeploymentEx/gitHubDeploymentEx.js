import { LightningElement } from 'lwc';

export default class GitHubDeploymentEx extends LightningElement {
    message = 'LWC GitHub Deployment Successful';
    propertyName = 'Green Valley Apartment';
    location = 'Nagpur';
    price = '45,00,000';

    handleClick() {
        alert('Property details clicked!');
    }
}

