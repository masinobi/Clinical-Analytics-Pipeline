import json
import random
from datetime import datetime, timezone
import urllib.request
import urllib.error

# My Zapier Catch-Hook Endpoint
WEBHOOK_URL = "https://hooks.zapier.com/hooks/catch/27402156/430dj8t/"

def generate_mock_ehr_payload():
    """
    Generates a structured, production-ready synthetic clinical record payload
    representing a longitudinal health or data quality validation milestone.
    """
    # High-risk cohort scenario simulation
    conditions = [
        ["E11.9", "Type 2 diabetes mellitus without complications"],
        ["I10", "Essential (primary) hypertension"],
        ["J45.909", "Unspecified asthma, uncomplicated"]
    ]
    
    selected_condition = random.choice(conditions)
    
    payload = {
        "metadata": {
            "source_pipeline": "Synthea_EHR_Ingest_v2",
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "environment": "simulation_sandbox"
        },
        "patient_cohort": {
            "patient_id": f"PT-{random.randint(10000, 99999)}",
            "age": random.randint(45, 78),
            "zip_code": "95112", # San Jose region
            "comorbid_risk_flags": {
                "type_2_diabetes": True,
                "hypertension": True
            }
        },
        "clinical_encounter": {
            "encounter_id": f"ENC-{random.randint(500000, 999999)}",
            "encounter_type": "Inpatient",
            "primary_dx_code": selected_condition[0],
            "primary_dx_description": selected_condition[1],
            "vitals_validation": {
                "systolic_bp": random.randint(135, 162),
                "diastolic_bp": random.randint(85, 102),
                "status": "FLAGGED_ALERT"
            }
        },
        "pipeline_audit": {
            "human_in_the_loop_required": True,
            "data_normalization_accuracy": 0.98
        }
    }
    return payload

def fire_webhook(url, payload):
    """
    Executes a synchronous HTTP POST request to stream structured 
    clinical payloads to the target webhook collector.
    """
    # Serialize python dict to strict JSON formatting string
    json_data = json.dumps(payload).encode('utf-8')
    
    # Configure production-standard HTTP Headers
    headers = {
        'Content-Type': 'application/json',
        'User-Agent': 'ClinicalDataPipeline-SimulationBot/1.0'
    }
    
    # Construct the network request
    req = urllib.request.Request(url, data=json_data, headers=headers, method='POST')
    
    print(f"[*] Initiating push to endpoint: {url}")
    print(f"[*] Transporting Patient ID: {payload['patient_cohort']['patient_id']}")
    
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            status_code = response.getcode()
            response_body = response.read().decode('utf-8')
            
            if status_code == 200:
                print(f"[+] Success: Ingestion trigger accepted by collector.")
                print(f"[+] Server Response Summary: {response_body}\n")
            else:
                print(f"[-] Warning: Received unexpected server status code: {status_code}")
                
    except urllib.error.HTTPError as e:
        print(f"[-] Transport Failure: HTTP Error encountered: {e.code} - {e.reason}")
        print(f"[-] Response payload content: {e.read().decode('utf-8')}")
    except urllib.error.URLError as e:
        print(f"[-] Critical Network Error: Remote endpoint unreachable: {e.reason}")

if __name__ == "__main__":
    # 1. Construct the synthetic record
    mock_dataset = generate_mock_ehr_payload()
    
    # 2. Fire the execution payload to the catch hook
    fire_webhook(WEBHOOK_URL, mock_dataset)


  
