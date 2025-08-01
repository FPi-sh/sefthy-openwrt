import requests
import subprocess
import tempfile
import os
from time import sleep


TOKEN = subprocess.run(["uci", "-q", "get", "sefthy.config.token"], capture_output=True, text=True, check=True).stdout.strip()
VERSION = subprocess.run(["uci", "-q", "get", "sefthy.version.version"], capture_output=True, text=True, check=True).stdout.strip()

URL = "console.sefthy.cloud"
CONNECTOR_TYPE = "openwrt"

while True:
    try:
        status = requests.get(f"https://{URL}/cc84a0df-dbeb-4440-a68a-86b4f699cb06/get-status",
                              headers={"Authorization": TOKEN},
                              json={"version": VERSION})
        if status.status_code == 200:
            response = status.json()
            if "schedule_id" in response and response["schedule_id"]:
                playbook = requests.post(f"https://{URL}/cc84a0df-dbeb-4440-a68a-86b4f699cb06/get-playbook",
                                         headers={"Authorization": TOKEN},
                                         json={"schedule_id": response["schedule_id"]})
                if playbook.status_code == 200:
                    with tempfile.NamedTemporaryFile(suffix=".sh", delete=False, mode="w") as temp_script:
                        temp_script.write(playbook.text)
                        temp_script_path = temp_script.name

                    os.chmod(temp_script_path, 0o755)
                    proc = subprocess.Popen(
                        ["bash", temp_script_path],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL
                    )
                    out, _ = proc.communicate()
                    os.remove(temp_script_path)

                    playbook_name = response.get("playbook_name", "Playbook")
                    message_text = f"{playbook_name} playbook executed successfully"

                    if out:
                        output_str = out.decode().strip()
                        if output_str:
                            message_text += f" | Output: {output_str}"

                    if proc.returncode == 0:
                        requests.post(f"https://{URL}/cc84a0df-dbeb-4440-a68a-86b4f699cb06/send-message",
                                      headers={"Authorization": TOKEN},
                                      json={"message": message_text,
                                            "version": VERSION,
                                            "schedule_id": response["schedule_id"],
                                            "updated_version": None})
                    else:
                        requests.post(f"https://{URL}/cc84a0df-dbeb-4440-a68a-86b4f699cb06/send-message",
                                      headers={"Authorization": TOKEN},
                                      json={"message": f"Error while executing {playbook_name} playbook",
                                            "version": VERSION,
                                            "schedule_id": response["schedule_id"],
                                            "updated_version": None})
            elif "target_version" in response and response["target_version"]:
                targetVersion = response["target_version"]
                updater = requests.get(f"https://static.sefthy.cloud/velch/{CONNECTOR_TYPE}/{targetVersion}")
                if updater.status_code == 200:
                    with tempfile.NamedTemporaryFile(suffix=".sh", delete=False, mode="w") as temp_script:
                        temp_script.write(updater.text)
                        temp_script_path = temp_script.name

                    os.chmod(temp_script_path, 0o755)
                    proc = subprocess.Popen(
                        ["bash", temp_script_path],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )
                    proc.wait()
                    os.remove(temp_script_path)

                    if proc.returncode == 0:
                        try:
                            versionupdate = subprocess.run(f'uci set sefthy.version.version="{targetVersion}" && uci commit sefthy', shell=True, capture_output=True)
                        except Exception as e:
                            print("Error:", e)
                            print({versionupdate})
                        requests.post(f"https://{URL}/cc84a0df-dbeb-4440-a68a-86b4f699cb06/send-message",
                                      headers={"Authorization": TOKEN},
                                      json={"message": f"Connector updated to version {targetVersion}",
                                            "version": VERSION,
                                            "schedule_id": None,
                                            "updated_version": targetVersion})
                    else:
                        requests.post(f"https://{URL}/cc84a0df-dbeb-4440-a68a-86b4f699cb06/send-message",
                                      headers={"Authorization": TOKEN},
                                      json={"message": f"Error while updating connector to version {targetVersion}",
                                            "version": VERSION,
                                            "schedule_id": None,
                                            "updated_version": None})
            else:
                requests.post(f"https://{URL}/cc84a0df-dbeb-4440-a68a-86b4f699cb06/send-message",
                              headers={"Authorization": TOKEN},
                              json={"message": "Waiting for instructions",
                                    "version": VERSION,
                                    "schedule_id": None,
                                    "updated_version": None})
        sleep(180)
    except Exception as e:
        print(e)
        sleep(60)