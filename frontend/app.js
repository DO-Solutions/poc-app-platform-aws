const API_URL = 'https://poc-app-platform-aws-defua.ondigitalocean.app';

document.addEventListener('DOMContentLoaded', () => {
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
});
