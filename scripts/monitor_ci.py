import subprocess
import time
import json
import sys

REPO = "hanthor/egg"
RUN_ID = "22049492629"

def get_status():
    cmd = ["gh", "run", "view", RUN_ID, "--repo", REPO, "--json", "status,conclusion,jobs"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error checking status: {res.stderr}")
        return None
    return json.loads(res.stdout)

print(f"Monitoring run {RUN_ID}...")
start_time = time.time()
while True:
    data = get_status()
    if not data:
        time.sleep(30)
        continue
        
    status = data.get("status")
    conclusion = data.get("conclusion")
    jobs = data.get("jobs", [])
    
    # Print summary of jobs
    ct_success = sum(1 for j in jobs if j["conclusion"] == "success")
    ct_failed = sum(1 for j in jobs if j["conclusion"] == "failure")
    ct_running = sum(1 for j in jobs if j["status"] == "in_progress")
    ct_pending = sum(1 for j in jobs if j["status"] == "queued")
    
    print(f"Status: {status}, Conclusion: {conclusion} | Success: {ct_success}, Failed: {ct_failed}, Running: {ct_running}, Pending: {ct_pending}")
    
    if ct_failed > 0:
        print("Run FAILED.")
        # Find failed jobs
        for j in jobs:
            if j["conclusion"] == "failure":
                print(f"Failed Job: {j['name']} ({j['url']})")
        sys.exit(1)
        
    if status == "completed":
        if conclusion == "success":
            print("Run SUCCEEDED.")
            sys.exit(0)
        else:
            print(f"Run finished with {conclusion}")
            sys.exit(1)
            
    # Timeout safely after 45 mins
    if time.time() - start_time > 45 * 60:
        print("Timeout monitoring run.")
        sys.exit(2)
        
    time.sleep(60)
