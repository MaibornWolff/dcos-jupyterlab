#!/usr/bin/env bash

# Taken from https://github.com/mesosphere/spark-build/blob/master/conf/spark-env.sh

# This file is sourced when running various Spark programs.
# Copy it as spark-env.sh and edit that to configure Spark for your site.

# additional environment variables for monitoring and troubleshooting purposes:
parent_command="$@"
echo "${parent_command}"

# Dispatcher sets SPARK_APPLICATION_ORIGIN to distinguish between different services and
# provide better monitoring details. If this environment variable is not set,
# then a Driver is submitted directly via spark-submit.
if [[ ${parent_command} == *"MesosClusterDispatcher"* ]]; then
   export SPARK_INSTANCE_TYPE="dispatcher"
   if [[ -n "${DCOS_SERVICE_NAME}" ]]; then
      export SPARK_APPLICATION_ORIGIN="${DCOS_SERVICE_NAME}"
   fi
elif [[ ${parent_command} == *"SparkSubmit"* ]]; then
   export SPARK_INSTANCE_TYPE="driver"
   echo "spark.executorEnv.SPARK_APPLICATION_ORIGIN=${SPARK_APPLICATION_ORIGIN}" >> ${SPARK_HOME}/conf/spark-defaults.conf
elif [[ ${parent_command} == *"ExecutorBackend"* ]]; then
   export SPARK_INSTANCE_TYPE="executor"
fi

if [[ -z "${SPARK_APPLICATION_ORIGIN}" ]]; then
   export SPARK_APPLICATION_ORIGIN="spark-submit"
fi

echo "Spark application origin: '${SPARK_APPLICATION_ORIGIN}'. Container instance type: '${SPARK_INSTANCE_TYPE}'."

# A custom HDFS config can be fetched via spark.mesos.uris.  This
# moves those config files into the standard directory.  In DCOS, the
# CLI reads the "SPARK_HDFS_CONFIG_URL" marathon label in order to set
# spark.mesos.uris
mkdir -p "${HADOOP_CONF_DIR}"
[ -f "${MESOS_SANDBOX}/hdfs-site.xml" ] && cp "${MESOS_SANDBOX}/hdfs-site.xml" "${HADOOP_CONF_DIR}"
[ -f "${MESOS_SANDBOX}/core-site.xml" ] && cp "${MESOS_SANDBOX}/core-site.xml" "${HADOOP_CONF_DIR}"

cd $MESOS_SANDBOX

LD_LIBRARY_PATH=/opt/mesosphere/libmesos-bundle/lib
MESOS_NATIVE_JAVA_LIBRARY=/opt/mesosphere/libmesos-bundle/lib/libmesos.so

# Configuring bind address
if [ -f ${BOOTSTRAP} ]; then
    # If launched not by Mesos or running in a virtual network, we need to reset LIBPROCESS_IP
    # so that bootstrap is able to discover container IP properly
    if [[  (-z "$MESOS_CONTAINER_IP" && -z "$LIBPROCESS_IP") || "${VIRTUAL_NETWORK_ENABLED}" = true ]]; then
        export LIBPROCESS_IP=0.0.0.0
    fi

    SPARK_LOCAL_IP=$($BOOTSTRAP --get-task-ip)

    export SPARK_LOCAL_IP=${SPARK_LOCAL_IP}
    export LIBPROCESS_IP=${SPARK_LOCAL_IP}

    echo "spark.driver.host ${SPARK_LOCAL_IP}" >> ${SPARK_HOME}/conf/spark-defaults.conf

    echo "spark-env: Configured SPARK_LOCAL_IP with bootstrap: ${SPARK_LOCAL_IP}" >&2
else
    echo "spark-env: ERROR: Unable to find bootstrap to configure SPARK_LOCAL_IP at ${BOOTSTRAP}, exiting." >&2
    exit 1
fi

# I first set this to MESOS_SANDBOX, as a Workaround for MESOS-5866
# But this fails now due to MESOS-6391, so I'm setting it to /tmp
MESOS_DIRECTORY=/tmp

export MESOS_MODULES="{\"libraries\": [{\"file\": \"libdcos_security.so\", \"modules\": [{\"name\": \"com_mesosphere_dcos_ClassicRPCAuthenticatee\"}]}]}"
export MESOS_AUTHENTICATEE="com_mesosphere_dcos_ClassicRPCAuthenticatee"

echo "spark-env: User: $(whoami)" >&2


if [[ -n "${SPARK_MESOS_KRB5_CONF_BASE64}" ]]; then
    KRB5CONF=${SPARK_MESOS_KRB5_CONF_BASE64}
fi

if [[ -n "${KRB5_CONFIG_BASE64}" ]]; then
    KRB5CONF=${KRB5_CONFIG_BASE64}
fi

if [[ -n "${KRB5CONF}" ]]; then
    echo "Decoding base64 encoded krb5.conf" >&2
    if base64 --help | grep -q GNU; then
          BASE64_D="base64 -d" # GNU
      else
          BASE64_D="base64 -D" # BSD
    fi
    echo "spark-env: Copying krb config from $KRB5CONF to /etc/" >&2
    echo "${KRB5CONF}" | ${BASE64_D} > /etc/krb5.conf
else
    echo "spark-env: No SPARK_MESOS_KRB5_CONF_BASE64 to decode" >&2
fi
