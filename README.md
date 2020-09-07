# Jupyterlab on DC/OS

This project provides a docker image and a package to run [Jupyterlab](https://jupyter.org/) on [DC/OS](https://dcos.io).
It includes the following special features:

* Support for DC/OS strict security mode (can run as user nobody and can launch spark jobs)
* Spark on Jupyter for Python and Scala with support for
  * kerberized HDFS
  * S3 access
  * [DC/OS Quota Management](https://docs.d2iq.com/mesosphere/dcos/2.1/multi-tenancy/quota-management/)
* Git support (clone git repo with notebooks during startup)

## Getting started

### Requirements

* DC/OS >= 1.13 (EE needed for kerberos support)
* At least 2 cores and 4 GB RAM free (4 cores and 6 GB if using spark)
* Edge-LB or Marathon-LB to expose the jupyter instance

### Provide package

Currently this package is not yet available from the DC/OS universe. As such you need to provide the package for your cluster yourself.

If you use the [DC/OS Package Registry](https://docs.d2iq.com/mesosphere/dcos/2.0/administering-clusters/package-registry/) you can download a bundle file from the github release page and upload it to your registry.

Otherwise you will have to provide the package yourself:

1. Install [dcosdev](https://github.com/swoehrl-mw/dcosdev) (fork with extra commands)
2. Install minio in your cluster
3. Set environment variables `MINIO_HOST`, `MINIO_ACCESS_KEY` and `MINIO_SECRET_KEY`
4. Run `dcosdev up`
5. Add the repo-file to your clusters package repositories (dcosdev will print the necessary command)
6. Now you can install the package (Note: Using this variant the version is always `snapshot`)

### Steps

1. Run `dcos package install jupyterlab`
2. Expose the service: either configure it in Edge-LB or see below on how to configure Marathon-LB

## Configuring jupyterlab

To configure the jupyterlab package you need to create a file `options.json`. See the following sub sections on the possible configuration options. Afterwards you need to install the package with `dcos package install jupyterlab --options=options.json`.

### Set a password

By default jupyterlab will generate a random token during startup and print that in its log. But you can also set a password during deployment:

```json
{
    "jupyterlab": {
        "password": "foobar"
    }
}
```

### DC/OS strict security mode

If your cluster is running in strict security mode you need to provide a DC/OS service account that spark can use to launch executors. Additionally if you have quotas enabled (starting with DC/OS 2.0) you need to configure the role that jupyterlab is running under (the name of the top-level marathon group jupyterlab is deployed in, e.g. if jupyterlab is running as `/analytics/dev/jupyterlab` the role is `analytics`).

```json
{
    "service": {
        "role": "<mesos-role>",
        "service_account": "<dcos-service-account-name>",
        "service_account_secret": "<path-to-service-account-secret>"
    }
}
```

### HDFS

If you want Spark to connect with HDFS you need to provide a URL from which spark can download the HDFS config files.

```json
{
    "jupyterlab": {
        "hdfs": {
            "enabled": true,
            "config_url": "http://api.hdfs.marathon.l4lb.thisdcos.directory/v1/endpoints"
        }
    }
}
```

If you do not use the DC/OS HDFS package installed at the default location you need to change the config url to your installation.

### Kerberos

If your HDFS is protected by Kerberos you additionally need to enable kerberos support and provide a `krb5.conf` and kerberos credentials (principal + keytab).

```json
{
    "jupyterlab": {
        "kerberos": {
            "enabled": true,
            "krb5conf_base64": "<base64-encoded-content of krb5.conf>",
            "principal": "<your-kerberos-principal>",
            "keytab_secret": "<path-to-a-secret-with-a-kerberos-keytab>"
        }
    }
}
```

The secret must be in a path where it is readable by the jupyterlab instance.

### S3

If you want to access AWS S3 or any other S3-compatible object storage with spark you need to configure credentials for it.

```json
{
    "jupyterlab": {
        "s3": {
            "enabled": true,
            "access_key": "<aws-access-key>",
            "secret_key": "<aws-secret-key>"
        }
    }
}
```

If you want to access MinIO you need to additionally provide the `endpoint` option (for example `http://minio.marathon.l4lb.thisdcos.directory:9000`).

Afterwards you can access S3 files from Spark using a path of `s3a://<bucket>/<path>` (e.g. `spark.read.text("s3a://my-bucket/some/data")`).

### Persistent storage

By default jupyterlab has no persistent storage and that means after a restart all notebooks are gone. To persist notebooks you can either use a git repository to save your work (see next section) or enable persistent storage.

You can either configure a local volume:

```json
{
    "service": {
        "storage": {
            "local_storage": {
                "enabled": true,
                "volume_size": 500
            }
        }
    }
}
```

Or you can use a host path (if for example you have an nfs share mounted on all hosts):

```json
{
    "service": {
        "storage": {
            "host_path": {
                "enabled": true,
                "path": "/mnt/data/jupyter"
            }
        }
    }
}
```

Once this is enabled jupyterlab will mount the local volume in the `work` folder. Any notebook stored there will be persisted across restarts (but if the node the instance is running on is lost the volume is also lost).

### Git

The jupyterlab package includes the feature to clone a git repository during startup. You can use this to automatically clone a repository with notebooks you want to use, and can also use it to persist/backup your work in git.

```json
{
    "jupyterlab": {
        "git": {
            "enabled": true,
            "repo_url": "<http-clone-url-to-your-repo>",
            "user_name": "<name-for-git-commits>",
            "user_email": "<email-for-git-commits>"
        }
    }
}
```

The repository must either be a public repository or the URL must include credentials (like `https://<my-user>:<access-token>@github.com/myuser/myrepo.git`).

The repository will be placed in a folder named like the repository. Using a terminal in jupyterlab you can navigate to that folder and execute a `git commit` and `git push` to save your notebooks (remember to first save any change for the notebook in jupyterlab).

### Exposing jupyterlab

To expose jupyterlab you can use either Edge-LB or Marathon-LB.

For Edge-LB please configure a frontend and a matching backend in a pool like the following:

```yaml
haproxy:
  backends:
    - name: jupyterlab
      protocol: HTTP
      services:
        - marathon:
            serviceID: "/jupyterlab"
          endpoint:
            portName: jupyter
```

Or if you use Marathon-LB add the following options:

```json
{
    "service": {
        "marathonlb": {
            "enabled": true,
            "hostname": "<hostname-jupyterlab-should-be-reachable-under>",
            "redirect_to_https": true
        }
    }
}
```

### Custom base url

By default jupyterlab is reachable via the root path. But you can also configure a custom base url for jupyter (for example if you want to use the same domain for multiple instances):

```json
{
    "service": {
        "base_url": "/my/instance"
    }
}
```

If you have configured Marathon-LB (see above) this base url will also be used for Marathon-LB (as `HAPROXY_0_PATH`).

### Host networking

By default jupyterlab uses the DC/OS overlay network. If you can't or don't want to use it you can also switch to host networking.

```json
{
    "service": {
        "virtual_network_enabled": false
    }
}
```

### SSL

For better security you can configure jupyterlab to secure its communication with SSL:

```json
{
    "jupyterlab": {
        "enable_ssl": true
    }
}
```

If you expose the instance using Edge-LB please remember to change the backend protocol from `HTTP` to `HTTPS`.

### Spark options

There are a number of options that allow you to configure spark. All of them are optional:

```json
{
    "jupyterlab": {
        "spark": {
            "executor_memory": "1024m",
            "driver_memory": "512m",
            "driver_cores": "1",
            "cores_max": "2",
            "executor_cores": "1",
            "extra_options": "",
            "driver_extra_java_options": "",
            "executor_extra_java_options": ""
        }
    }
}
```

* The number of executors is defined as `cores_max/executor_cores`.
* `driver_cores` and `driver_memory` must be less than the cpus/memory configured for the jupyterlab instance (as the driver process runs inside the jupyterlab instance).
* `extra_options` can be used to define extra spark options, must be provided as list of key=value pairs, space-separated (like `spark.foo=1 spark.bar=baz`)
* `driver_extra_java_options` will be passed as value for `spark.driver.extraJavaOptions`
* `executor_extra_java_options` will be passed as value for `spark.executor.extraJavaOptions`

### Jupyterlab Resources

If you need it you can also adjust the cpus and memory that the jupyterlab instance is deployed with:

```json
{
    "service": {
        "cpus": 2,
        "mem": 4096,
    }
}
```

## Using jupyterlab

### Spark with Scala

To use spark with scala launch a new notebook with the "Apache Toree - Scala" kernel. A spark driver will be lazily initialized as soon as you first use the `spark` variable (which points to a `SparkSession` object). The classical Pi example:

```scala
import scala.math.random
val slices = 2
val n = math.min(100000L * slices, Int.MaxValue).toInt // avoid overflow
val count = spark.sparkContext.parallelize(1 until n, slices).map { i =>
  val x = random * 2 - 1
  val y = random * 2 - 1
  if (x*x + y*y <= 1) 1 else 0
}.reduce(_ + _)
println(s"Pi is roughly ${4.0 * count / (n - 1)}")
```

You can also run spark SQL statements by using the `%%sql` magic:

```scala
spark.read.parquet("hdfs:///my/data").registerTempTable("foobar")
```

```sql
%%sql
SELECT * FROM foobar
```

The spark driver (and its executors) will keep running until you either stop the scala kernel or run `spark.stop`.

### Spark with Python

To use spark with python launch a new notebook with the "Python 3" kernel. To initialize spark you need to execute the following statement:

```python
from config_util.spark import initSpark
spark = initSpark()
```

Afterwards `spark` points to a `SparkSession` object.

If you want to also use Spark SQL you need to initialize the magic:

```python
%load_ext sparksql_magic
```

Afterwards you can use it like this:

```sql
%%sparksql
SELECT * FROM foobar
```

The spark driver (and its executors) will keep running until you either stop the scala kernel or run `spark.stop()`.

### Custom libraries

if you want to use any python library that is not included in jupyterlab you can install it on-the-fly. To do this just open a terminal in jupyterlab (via the launcher) and run `pip install <package>`. After the installation is complete you can import the library in your python notebooks. Note that packages installed this way are not persisted across restarts and will therefore have to be reinstalled on every instance startup.

## Roadmap / Planned Features

* GPU support
* Support for automatically installing custom python libraries during startup
* Support more kernels
* Support for machine learning libraries

## Development

The docker image is based on the [Jupyter Docker stacks](https://github.com/jupyter/docker-stacks) with parts from `base-notebook`, `minimal-notebook` and `spark-notebook` along with DC/OS-specific additions from [dcos-jupyterlab-service](https://github.com/dcos-labs/dcos-jupyterlab-service). Spark-specific configs are taken from [spark-build](https://github.com/mesosphere/spark-build).

### Release process

1. Update fields `version`, `upgradesFrom` and `downgradesTo` in `universe/package.json`
2. Tag commit with `vX.Y.Z`, make sure tag matches `version` from `universe/package.json`
3. Edit release draft and publish

### Noteworthy changes for DC/OS

* `nobody` user to conform to DC/OS
* File permissions to allow running as `nobody`
* Handling of `MESOS_SANDBOX`
* mesos libraries

## Acknowledgments

This package is heavily inspired by the following repositories:

* [Jupyter Docker stacks](https://github.com/jupyter/docker-stacks)
* [dcos-jupyterlab-service](https://github.com/dcos-labs/dcos-jupyterlab-service)

## Contributing

If you find a bug or have a feature request, please open an issue in Github. Or, if you want to contribute something, feel free to open a pull request.
