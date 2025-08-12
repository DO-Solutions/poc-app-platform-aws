// Determine API URL based on current domain
const API_URL = window.location.hostname === 'poc-app-platform-aws.digitalocean.solutions' 
    ? 'https://poc-app-platform-aws.digitalocean.solutions'
    : 'https://poc-app-platform-aws-defua.ondigitalocean.app';

document.addEventListener('DOMContentLoaded', () => {
    // Fetch database status
    fetch(`${API_URL}/db/status`)
        .then(response => response.json())
        .then(data => {
            const pgStatus = document.getElementById('postgres-status');
            const valkeyStatus = document.getElementById('valkey-status');

            if (data.postgres && data.postgres.connected && data.postgres.readable && data.postgres.writable) {
                pgStatus.textContent = 'OK';
                pgStatus.classList.add('ok');
            } else {
                pgStatus.textContent = 'FAIL';
                pgStatus.classList.add('fail');
            }

            if (data.valkey && data.valkey.connected && data.valkey.ping_ok && data.valkey.set_get_ok) {
                valkeyStatus.textContent = 'OK';
                valkeyStatus.classList.add('ok');
            } else {
                valkeyStatus.textContent = 'FAIL';
                valkeyStatus.classList.add('fail');
            }
        })
        .catch(error => {
            console.error('Error fetching DB status:', error);
            document.getElementById('postgres-status').textContent = 'FAIL';
            document.getElementById('postgres-status').classList.add('fail');
            document.getElementById('valkey-status').textContent = 'FAIL';
            document.getElementById('valkey-status').classList.add('fail');
        });

    // Fetch IAM Roles Anywhere status
    fetch(`${API_URL}/iam/status`)
        .then(response => response.json())
        .then(data => {
            const iamStatus = document.getElementById('iam-status');
            const iamDetails = document.getElementById('iam-details');
            
            if (data.ok && data.role_arn) {
                iamStatus.textContent = 'OK';
                iamStatus.classList.add('ok');
                
                let detailText = `Role: ${data.role_arn}`;
                if (data.account && data.account !== 'N/A') {
                    detailText += `\nAccount: ${data.account}`;
                }
                if (data.note) {
                    detailText += `\n${data.note}`;
                }
                iamDetails.textContent = detailText;
            } else {
                iamStatus.textContent = 'FAIL';
                iamStatus.classList.add('fail');
                if (data.error) {
                    iamDetails.textContent = `Error: ${data.error}`;
                }
            }
        })
        .catch(error => {
            console.error('Error fetching IAM status:', error);
            document.getElementById('iam-status').textContent = 'FAIL';
            document.getElementById('iam-status').classList.add('fail');
            document.getElementById('iam-details').textContent = 'Connection error';
        });
});
