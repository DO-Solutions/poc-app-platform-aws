// Determine API URL based on current domain
const API_URL = window.location.hostname === 'poc-app-platform-aws.digitalocean.solutions' 
    ? 'https://poc-app-platform-aws.digitalocean.solutions'
    : 'https://poc-app-platform-aws-defua.ondigitalocean.app';

let refreshInterval;
let countdown = 30;
let countdownInterval;

// Utility function to format timestamp and calculate age
function formatTimestampWithAge(timestampStr) {
    if (!timestampStr) {
        return {
            display: 'No data',
            ageSeconds: null,
            className: 'timestamp-stale'
        };
    }
    
    try {
        const timestamp = new Date(timestampStr);
        const now = new Date();
        const ageSeconds = Math.floor((now - timestamp) / 1000);
        
        // Format the timestamp for display
        const formatted = timestamp.toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, ' UTC');
        const ageText = ageSeconds < 60 
            ? `(${ageSeconds}s ago)` 
            : ageSeconds < 3600 
                ? `(${Math.floor(ageSeconds / 60)}m ${ageSeconds % 60}s ago)`
                : `(${Math.floor(ageSeconds / 3600)}h ${Math.floor((ageSeconds % 3600) / 60)}m ago)`;
        
        // Determine color class based on age
        let className = 'timestamp-fresh';
        if (ageSeconds > 90) {
            className = 'timestamp-stale';
        } else if (ageSeconds > 60) {
            className = 'timestamp-warning';
        }
        
        return {
            display: `${formatted} ${ageText}`,
            ageSeconds,
            className
        };
    } catch (error) {
        console.error('Error parsing timestamp:', timestampStr, error);
        return {
            display: 'Invalid timestamp',
            ageSeconds: null,
            className: 'timestamp-stale'
        };
    }
}

// Update timestamp display for an element
function updateTimestampElement(elementId, timestampStr, fallbackStatus = 'error') {
    const element = document.getElementById(elementId);
    if (!element) return;
    
    // Clear existing classes
    element.classList.remove('timestamp-fresh', 'timestamp-warning', 'timestamp-stale');
    
    if (!timestampStr && fallbackStatus === 'error') {
        element.textContent = 'Connection error';
        element.classList.add('timestamp-stale');
        return;
    }
    
    const timestampInfo = formatTimestampWithAge(timestampStr);
    element.textContent = timestampInfo.display;
    element.classList.add(timestampInfo.className);
}

// Show loading indicator
function showLoading() {
    document.getElementById('loading-indicator').style.display = 'inline';
    document.getElementById('refresh-btn').disabled = true;
}

// Hide loading indicator
function hideLoading() {
    document.getElementById('loading-indicator').style.display = 'none';
    document.getElementById('refresh-btn').disabled = false;
}

// Fetch all data from APIs
async function fetchAllData() {
    showLoading();
    
    try {
        // Fetch all endpoints in parallel
        const [dbResponse, iamResponse, secretResponse] = await Promise.allSettled([
            fetch(`${API_URL}/db/status`),
            fetch(`${API_URL}/iam/status`),
            fetch(`${API_URL}/secret/status`)
        ]);

        // Process database status
        if (dbResponse.status === 'fulfilled' && dbResponse.value.ok) {
            const dbData = await dbResponse.value.json();
            
            // PostgreSQL status
            const pgStatus = document.getElementById('postgres-status');
            const pgEndpoint = document.getElementById('postgres-endpoint');
            
            if (dbData.postgres && dbData.postgres.connected && dbData.postgres.readable && dbData.postgres.writable) {
                pgStatus.textContent = 'OK';
                pgStatus.classList.remove('fail');
                pgStatus.classList.add('ok');
            } else {
                pgStatus.textContent = 'FAIL';
                pgStatus.classList.remove('ok');
                pgStatus.classList.add('fail');
            }
            
            if (dbData.postgres && dbData.postgres.host) {
                pgEndpoint.textContent = dbData.postgres.host;
            } else {
                pgEndpoint.textContent = 'Unknown';
            }
            
            updateTimestampElement('postgres-timestamp', dbData.postgres?.postgres_last_update);

            // Valkey status
            const valkeyStatus = document.getElementById('valkey-status');
            const valkeyEndpoint = document.getElementById('valkey-endpoint');
            
            if (dbData.valkey && dbData.valkey.connected && dbData.valkey.ping_ok && dbData.valkey.set_get_ok) {
                valkeyStatus.textContent = 'OK';
                valkeyStatus.classList.remove('fail');
                valkeyStatus.classList.add('ok');
            } else {
                valkeyStatus.textContent = 'FAIL';
                valkeyStatus.classList.remove('ok');
                valkeyStatus.classList.add('fail');
            }
            
            if (dbData.valkey && dbData.valkey.host) {
                valkeyEndpoint.textContent = dbData.valkey.host;
            } else {
                valkeyEndpoint.textContent = 'Unknown';
            }
            
            updateTimestampElement('valkey-timestamp', dbData.valkey?.valkey_last_update);
            
        } else {
            // Handle DB API failure
            document.getElementById('postgres-status').textContent = 'FAIL';
            document.getElementById('postgres-status').classList.add('fail');
            document.getElementById('valkey-status').textContent = 'FAIL';
            document.getElementById('valkey-status').classList.add('fail');
            document.getElementById('postgres-endpoint').textContent = 'Connection error';
            document.getElementById('valkey-endpoint').textContent = 'Connection error';
            updateTimestampElement('postgres-timestamp', null);
            updateTimestampElement('valkey-timestamp', null);
        }

        // Process IAM status
        if (iamResponse.status === 'fulfilled' && iamResponse.value.ok) {
            const iamData = await iamResponse.value.json();
            
            const iamStatus = document.getElementById('iam-status');
            const iamEndpoint = document.getElementById('iam-endpoint');
            
            if (iamData.ok && iamData.role_arn) {
                iamStatus.textContent = 'OK';
                iamStatus.classList.remove('fail');
                iamStatus.classList.add('ok');
                iamEndpoint.textContent = iamData.role_arn;
            } else {
                iamStatus.textContent = 'FAIL';
                iamStatus.classList.remove('ok');
                iamStatus.classList.add('fail');
                if (iamData.error) {
                    iamEndpoint.textContent = `Error: ${iamData.error}`;
                } else {
                    iamEndpoint.textContent = 'Authentication failed';
                }
            }
            
            // For IAM, we show credential creation time instead of worker timestamp
            updateTimestampElement('iam-timestamp', iamData.credentials_created);
            
        } else {
            document.getElementById('iam-status').textContent = 'FAIL';
            document.getElementById('iam-status').classList.add('fail');
            document.getElementById('iam-endpoint').textContent = 'Connection error';
            updateTimestampElement('iam-timestamp', null);
        }

        // Process Secrets Manager status
        if (secretResponse.status === 'fulfilled' && secretResponse.value.ok) {
            const secretData = await secretResponse.value.json();
            
            const secretStatus = document.getElementById('secret-status');
            const secretEndpoint = document.getElementById('secret-endpoint');
            
            if (secretData.ok && secretData.secret_value && secretData.secret_name) {
                secretStatus.textContent = 'OK';
                secretStatus.classList.remove('fail');
                secretStatus.classList.add('ok');
                
                // Display secret name and a portion of the secret value
                let displayText = `${secretData.secret_name}`;
                try {
                    // Try to parse as JSON to show a nice preview
                    const secretJson = JSON.parse(secretData.secret_value);
                    if (secretJson.test_value) {
                        displayText += ` - ${secretJson.test_value}`;
                    }
                } catch (e) {
                    // If not JSON, show first 50 chars
                    displayText += ` - ${secretData.secret_value.substring(0, 50)}...`;
                }
                secretEndpoint.textContent = displayText;
            } else {
                secretStatus.textContent = 'FAIL';
                secretStatus.classList.remove('ok');
                secretStatus.classList.add('fail');
                if (secretData.error) {
                    secretEndpoint.textContent = `Error: ${secretData.error}`;
                } else {
                    secretEndpoint.textContent = 'Secret retrieval failed';
                }
            }
            
            updateTimestampElement('secret-timestamp', secretData.secret_last_update);
            
        } else {
            document.getElementById('secret-status').textContent = 'FAIL';
            document.getElementById('secret-status').classList.add('fail');
            document.getElementById('secret-endpoint').textContent = 'Connection error';
            updateTimestampElement('secret-timestamp', null);
        }

    } catch (error) {
        console.error('Error fetching data:', error);
        // Set all to failed state
        const statusElements = ['postgres-status', 'valkey-status', 'iam-status', 'secret-status'];
        const endpointElements = ['postgres-endpoint', 'valkey-endpoint', 'iam-endpoint', 'secret-endpoint'];
        const timestampElements = ['postgres-timestamp', 'valkey-timestamp', 'iam-timestamp', 'secret-timestamp'];
        
        statusElements.forEach(id => {
            const el = document.getElementById(id);
            el.textContent = 'FAIL';
            el.classList.remove('ok');
            el.classList.add('fail');
        });
        
        endpointElements.forEach(id => {
            document.getElementById(id).textContent = 'Connection error';
        });
        
        timestampElements.forEach(id => {
            updateTimestampElement(id, null);
        });
    } finally {
        hideLoading();
    }
}

// Update countdown display
function updateCountdown() {
    const indicator = document.getElementById('auto-refresh-indicator');
    indicator.textContent = `Auto-refresh: ${countdown}s`;
    
    countdown--;
    if (countdown < 0) {
        countdown = 30;
        fetchAllData();
    }
}

// Start auto-refresh
function startAutoRefresh() {
    // Clear any existing intervals
    if (refreshInterval) clearInterval(refreshInterval);
    if (countdownInterval) clearInterval(countdownInterval);
    
    countdown = 30;
    countdownInterval = setInterval(updateCountdown, 1000);
}

// Manual refresh
function manualRefresh() {
    countdown = 30; // Reset countdown
    fetchAllData();
}

// Initialize the application
document.addEventListener('DOMContentLoaded', () => {
    // Set up refresh button
    document.getElementById('refresh-btn').addEventListener('click', manualRefresh);
    
    // Initial data fetch
    fetchAllData();
    
    // Start auto-refresh
    startAutoRefresh();
});

// Update timestamps every second to keep age display current
setInterval(() => {
    const timestampElements = document.querySelectorAll('.timestamp-text');
    timestampElements.forEach(element => {
        const text = element.textContent;
        // Only update if it contains a valid timestamp format (not "No data" or "Connection error")
        if (text.includes('UTC') && text.includes('ago)')) {
            const timestampMatch = text.match(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC/);
            if (timestampMatch) {
                const timestampStr = timestampMatch[1].replace(' ', 'T') + '.000Z';
                const timestampInfo = formatTimestampWithAge(timestampStr);
                
                // Update classes
                element.classList.remove('timestamp-fresh', 'timestamp-warning', 'timestamp-stale');
                element.classList.add(timestampInfo.className);
                element.textContent = timestampInfo.display;
            }
        }
    });
}, 1000);