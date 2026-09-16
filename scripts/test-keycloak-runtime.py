"""Exercise the hook's helpers in its actual image, with no cluster or credentials."""
from pathlib import Path
import subprocess
import yaml

path = Path(__file__).resolve().parents[1] / "identity/keycloak/keycloak-reconcile-hook-job.yaml"
job = yaml.safe_load(path.read_text())
container = job["spec"]["template"]["spec"]["containers"][0]
script = container["command"][-1]
helpers = script[script.index("csv_value() {"):script.index('browser_flow="')]
checks = r'''
set -euo pipefail
rows='"cookie","Cookie","ALTERNATIVE",false,"",0
"forms","browser-with-conditional-otp forms","ALTERNATIVE",true,"flow",0
"nested","Username Password Form","REQUIRED",false,"",1
"stray1","otp-conditional-subflow","CONDITIONAL",true,"stray",0
"stray2","otp-conditional-subflow","CONDITIONAL",true,"stray",0'
[[ $(csv_value "$rows" 2 Cookie 1) == cookie ]]
[[ $(csv_value "$rows" 2 absent 1) == '' ]]
[[ $(csv_match_count "$rows" 2 otp-conditional-subflow) == 2 ]]
[[ $(csv_value "$rows" 2 otp-conditional-subflow 1 all) == $'stray1\nstray2' ]]
[[ $(csv_row_count "$(level0_rows "$rows")") == 4 ]]
[[ $(csv_row_count '') == 0 ]]
[[ $(urlencode_path 'a b/%') == 'a%20b%2F%25' ]]
forms_display_name='browser-with-conditional-otp forms'
[[ $(unexpected_top_rows '"x","Wrong",false') == Wrong ]]
[[ $(unexpected_top_rows '"x","Cookie",false') == '' ]]
echo 'Keycloak image: 9 helper assertions passed'
'''
subprocess.run(["shellcheck", "-s", "bash", "-"], input=script, text=True, check=True)
subprocess.run(["docker", "run", "--rm", "-i", "--network=none", "--entrypoint", "/bin/bash",
                container["image"], "-s"], input=helpers + checks, text=True, check=True)
