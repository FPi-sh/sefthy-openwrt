from flask import Flask, request, jsonify
import netifaces as ni
import subprocess
import ipaddress
import speedtest
import uci

app = Flask(__name__)

@app.route('/877f3040-1d61-4bcc-85ea-b0d1eb9ee904/config-monitor', methods=['POST'])
def config_monitor():
    data = request.get_json()
    monitor_ip = data.get('monitor_ip')
    action = data.get('action')
    
    if not monitor_ip or not action:
        return jsonify({'error': 'Missing parameters'}), 400
    
    if action not in ['add', 'remove']:
        return jsonify({'error': 'Invalid action'}), 400
    
    try:
        ipaddress.ip_address(monitor_ip)
    except ValueError:
        return jsonify({'error': 'Invalid IP address format'}), 400
    
    result = subprocess.run(['/opt/sefthy-wrt-monitor/monitor.sh', monitor_ip, action], capture_output=True)
    return jsonify({'exit_code': result.returncode}), 200

@app.route('/bb455419-9ca1-464d-a31c-0e9ea5f28792/get-macaddr', methods=['POST'])
def get_macaddr():
    data = request.get_json()
    ip = data.get('ip')
    
    if not ip:
        return jsonify({'error': 'ip is required'}), 400
    
    try:
        ipaddress.ip_address(ip)
    except ValueError:
        return jsonify({'error': 'Invalid IP address format'}), 400

    interface = uci.get('sefthy.config.selected_br')
    result = subprocess.run(f'arping -s 0.0.0.0 -c 1 -I {interface.stdout.decode("utf-8").strip()} {ip} | grep -oE "([0-9a-fA-F]{{2}}:){{5}}[0-9a-fA-F]{{2}}"', shell=True, capture_output=True)

    return jsonify({'exit_code': result.returncode,
                    'macaddr': result.stdout.decode('utf-8').strip(),
                    'stderr': result.stderr.decode('utf-8').strip()}), 200

@app.route('/3d9cb111-9955-41a3-9013-238787756ab0/dr-bridge-status', methods=['POST'])
def dr_bridge_status():
    interface = uci.get('sefthy.config.selected_br')
    result = subprocess.run([f'/usr/sbin/brctl show {interface.stdout.decode("utf-8").strip()} | grep sefthy'], shell=True, capture_output=True)
    if result.returncode == 0:
        return jsonify({
            'status': 'true'
        }), 200
    else:
        return jsonify({
            'status': 'false'
        }), 200

@app.route('/3d9cb111-9955-41a3-9013-238787756ab0/dr-bridge', methods=['POST'])
def config_br():
    data = request.get_json()
    action = data.get('action')
    
    if not action or action not in ['enable', 'disable']:
        return jsonify({'error': 'invalid or missing action'}), 400
    
    result = subprocess.run(['/opt/sefthy-wrt-config/config.sh', action], capture_output=True)
    return jsonify({'exit_code': result.returncode}), 200

@app.route('/66649197-8a2b-44b2-9bee-43d250e87c8c/speedtest', methods=['POST'])
def run_speedtest():
    st = speedtest.Speedtest(secure=True)
    return jsonify({'upload': st.upload()/1000000}), 200

if __name__ == '__main__':
    from waitress import serve
    sefthywgip = ni.ifaddresses('sefthy_wg')[ni.AF_INET][0]['addr']
    serve(app, host=sefthywgip, port=8080)