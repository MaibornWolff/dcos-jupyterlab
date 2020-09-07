# Partially taken from https://github.com/dcos-labs/dcos-jupyterlab-service/blob/master/jupyter_notebook_config.py
import base64
import json
import os
import stat
import subprocess
import traceback

from config_util.opts import calculate_spark_options
from notebook.auth import passwd


c = get_config()

c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False

# Allow CORS and TLS from behind Nginx/Marathon-LB/HAProxy
# Trust X-Scheme/X-Forwarded-Proto and X-Real-Ip/X-Forwarded-For
# Necessary if the proxy handles SSL
c.NotebookApp.trust_xheaders = True

# Set the Access-Control-Allow-Origin header
c.NotebookApp.allow_origin = '*'

# Allow requests where the Host header doesn't point to a local server
c.NotebookApp.allow_remote_access = True


# Set a password if JUPYTER_PASSWORD (override) is set
if os.getenv('JUPYTER_PASSWORD'):
    c.NotebookApp.password = passwd(os.getenv('JUPYTER_PASSWORD'))
    del(os.environ['JUPYTER_PASSWORD'])
elif os.getenv("JUPYTER_DISABLE_PASSWORD", "false").lower() == "true":
    c.NotebookApp.password = ''
    c.NotebookApp.token = ''

if os.getenv("JUPYTER_BASE_URL"):
    c.NotebookApp.base_url = os.getenv("JUPYTER_BASE_URL")

os.environ["LD_LIBRARY_PATH"] = "/opt/mesosphere/libmesos-bundle/lib"
os.environ["SPARK_USER"] = os.getenv("SPARK_USER", "nobody")
os.environ["PYSPARK_PYTHON"] = "python3"
os.environ["HADOOP_HOME"] = "/etc/hadoop"
os.environ["HADOOP_CONF_DIR"] = "/etc/hadoop"
os.environ["CLASSPATH"] = "/etc/hadoop"
os.environ["JAVA_HOME"] = "/opt/jdk"
os.environ['MESOS_DIRECTORY'] = os.getenv('MESOS_SANDBOX')

try:
    for env in ['MESOS_EXECUTOR_ID', 'MESOS_FRAMEWORK_ID', 'MESOS_SLAVE_ID', 'MESOS_SLAVE_PID', 'MESOS_TASK_ID']:
        del os.environ[env]
except KeyError:
    pass


# Configure spark

spark_opts = []
for name, value in calculate_spark_options().items():
    spark_opts.append("--conf {}={}".format(name, value))
os.environ["SPARK_OPTS"] = ' '.join(spark_opts)

if os.getenv("KRB5_CONF_BASE64"):
    with open('/etc/krb5.conf', "wb") as krb_file:
        krb_file.write(base64.b64decode(os.getenv("KRB5_CONF_BASE64")))

# Generate a self-signed certificate
if os.getenv('GEN_CERT', "true").lower() == "true":

    pem_file = os.path.join(os.getenv('MESOS_SANDBOX'), '.jupyterlab_ssl.pem')
    # Generate a certificate if one doesn't exist on disk
    subprocess.check_call(['openssl', 'req', '-new',
                           '-newkey', 'rsa:2048',
                           '-days', '365',
                           '-nodes', '-x509',
                           '-subj', '/C=XX/ST=XX/L=XX/O=generated/CN=generated',
                           '-keyout', pem_file,
                           '-out', pem_file])
    # Restrict access to the file
    os.chmod(pem_file, stat.S_IRUSR | stat.S_IWUSR)
    c.NotebookApp.certfile = pem_file

# Clone git repo if configured
if os.getenv("GIT_REPO_URL") and os.getenv("GIT_REPO_URL").lower() not in ("changeme", "todo"):
    try:
        subprocess.check_call(["git", "config", "--global", "http.sslVerify", "false"])
        if os.getenv("GIT_USER_NAME"):
            subprocess.check_call(["git", "config", "--global", "user.name", os.getenv("GIT_USER_NAME")])
        if os.getenv("GIT_USER_EMAIL"):
            subprocess.check_call(["git", "config", "--global", "user.email", os.getenv("GIT_USER_EMAIL")])
        subprocess.check_call(["git", "clone", os.getenv("GIT_REPO_URL")], cwd=os.getenv('MESOS_SANDBOX'))
    except:
        traceback.print_exc()
