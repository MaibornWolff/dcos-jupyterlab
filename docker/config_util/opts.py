import os


class SparkOpt:
    def __init__(self, env, default=None, required=False):
        self.env = env
        self.default = default
        self.required = required


OPTS_CONF = {
    "spark.app.name": SparkOpt("SPARK_APP_NAME", "jupyterlab"),
    "spark.master": SparkOpt("SPARK_MASTER_URL", "mesos://zk://zk-1.zk:2181,zk-2.zk:2181,zk-3.zk:2181,zk-4.zk:2181,zk-5.zk:2181/mesos"),
    "spark.driver.cores": SparkOpt("SPARK_DRIVER_CORES", "1"),
    "spark.driver.memory": SparkOpt("SPARK_DRIVER_MEMORY"),
    "spark.executor.cores": SparkOpt('SPARK_EXECUTOR_CORES', "1"),
    "spark.executor.memory": SparkOpt('SPARK_EXECUTOR_MEMORY', "1024m"),
    "spark.cores.max": SparkOpt('SPARK_TOTAL_EXECUTOR_CORES', "2"),
    "spark.mesos.executor.docker.image": SparkOpt("SPARK_EXECUTOR_DOCKER_IMAGE", required=True),
    "spark.mesos.role": SparkOpt('MESOS_ROLE'),
    "spark.mesos.principal": SparkOpt("MESOS_PRINCIPAL"),
    "spark.driver.host": SparkOpt("CONTAINER_IP", required=True),
    "spark.driver.port": SparkOpt("PORT_SPARKDRIVER", "7077"),
    "spark.ui.port": SparkOpt("PORT_SPARKUI", "4040"),
    "spark.driver.extraJavaOptions": SparkOpt("SPARK_DRIVER_JAVA_OPTIONS"),
    "spark.executor.extraJavaOptions": SparkOpt("SPARK_EXECUTOR_JAVA_OPTIONS")
}


def calculate_spark_options():
    opts = dict()
    opts["spark.hadoop.fs.s3a.impl"] = "org.apache.hadoop.fs.s3a.S3AFileSystem"
    opts["spark.mesos.executor.home"] = "/opt/spark"
    opts["spark.mesos.containerizer"] = "mesos"
    opts["spark.mesos.executor.docker.forcePullImage"] = "true"
    opts["spark.jars.ivy"] = os.getenv("MESOS_SANDBOX")+"/.ivy2"

    for name, conf in OPTS_CONF.items():
        if conf.env:
            value = os.getenv(conf.env, conf.default)
        else:
            value = conf.default
        if conf.required and not value:
            raise Exception("'{}' is required but has no configured value and no default".format(name))
        if value:
            opts[name] = value

    if os.getenv("HDFS_URL"):
        url = os.getenv("HDFS_URL")
        opts["spark.mesos.uris"] = "{}/hdfs-site.xml,{}/core-site.xml".format(url, url)

    if os.getenv("KERBEROS_KEYTAB_SECRET"):
        opts["spark.driver.extraClassPath"] = "/etc/hadoop:/etc/hadoop/conf:/mnt/mesos/sandbox"
        opts["spark.executor.extraClassPath"] = "/etc/hadoop:/etc/hadoop/conf:/mnt/mesos/sandbox"
        opts["spark.yarn.keytab"] = "/mnt/mesos/sandbox/{}".format(os.getenv("KERBEROS_KEYTAB_NAME", "hdfs-keytab"))
        opts["spark.yarn.principal"] = os.getenv("KERBEROS_PRINCIPAL")
        opts["spark.executorEnv.SPARK_MESOS_KRB5_CONF_BASE64"] = os.getenv("KRB5_CONF_BASE64")

    if os.getenv("S3_ENDPOINT"):
        opts["spark.hadoop.fs.s3a.endpoint"] = os.getenv("S3_ENDPOINT")
        opts["spark.hadoop.fs.s3a.path.style.access"] = "true"
    if os.getenv("S3_ACCESS_KEY") and os.getenv("S3_SECRET_KEY"):
        opts["spark.hadoop.fs.s3a.access.key"] = os.getenv("S3_ACCESS_KEY")
        opts["spark.hadoop.fs.s3a.secret.key"] = os.getenv("S3_SECRET_KEY")

    extra_conf = os.getenv("SPARK_CONF")
    if extra_conf:
        for option in extra_conf.split(" "):
            name, value = option.split("=", 1)
            opts[name] = value

    return opts
