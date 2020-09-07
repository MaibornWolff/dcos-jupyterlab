# Dockerfile partially taken and inspired by https://github.com/jupyter/docker-stacks and (for mesos stuff) https://github.com/dcos-labs/dcos-jupyterlab-service
# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

# Ubuntu 20.04 (focal)
# https://hub.docker.com/_/ubuntu/?tab=tags&name=focal
# OS/ARCH: linux/amd64
ARG ROOT_CONTAINER=ubuntu:focal-20200703@sha256:d5a6519d9f048100123c568eb83f7ef5bfcad69b01424f420f17c932b00dea76

ARG BASE_CONTAINER=$ROOT_CONTAINER
FROM $BASE_CONTAINER

ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"
ARG LIBMESOS_BUNDLE_URL="https://downloads.mesosphere.com/libmesos-bundle"
ARG LIBMESOS_BUNDLE_VERSION="1.12.0"
ARG MESOSPHERE_PREFIX="/opt/mesosphere"
ARG MESOS_MAVEN_URL="https://repo1.maven.org/maven2/org/apache/mesos/mesos"
ARG MESOS_VERSION="1.7.0"
ARG DCOS_COMMONS_URL="https://downloads.mesosphere.com/dcos-commons"
ARG DCOS_COMMONS_VERSION="0.57.2"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update \
 && apt-get install -yq --no-install-recommends \
    wget \
    curl \
    bzip2 \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
    run-one \
    build-essential \
    emacs-nox \
    vim-tiny \
    git \
    inkscape \
    jed \
    libsm6 \
    libxext-dev \
    libxrender1 \
    lmodern \
    netcat \
    python-dev \
    # ---- nbconvert dependencies ----
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-plain-generic \
    # ----
    tzdata \
    unzip \
    nano \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen


# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER
ENV BOOTSTRAP="${MESOSPHERE_PREFIX}/bin/bootstrap" \
    MESOSPHERE_PREFIX=${MESOSPHERE_PREFIX:-"/opt/mesosphere"} \
    MESOS_AUTHENTICATEE="com_mesosphere_dcos_ClassicRPCAuthenticatee" \
    MESOS_HTTP_AUTHENTICATEE="com_mesosphere_dcos_http_Authenticatee" \
    MESOS_MODULES="{\"libraries\": [{\"file\": \"libdcos_security.so\", \"modules\": [{\"name\": \"com_mesosphere_dcos_ClassicRPCAuthenticatee\"}]}]}" \
    MESOS_NATIVE_LIBRARY="${MESOSPHERE_PREFIX}/libmesos-bundle/lib/libmesos.so" \
    MESOS_NATIVE_JAVA_LIBRARY="${MESOSPHERE_PREFIX}/libmesos-bundle/lib/libmesos.so" \
    PATH="${MESOSPHERE_PREFIX}/bin:${PATH}" \
    APACHE_SPARK_VERSION=2.4.6 \
    HADOOP_VERSION=2.9.2

# Copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# Create NB_USER wtih name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \ 
    echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR

RUN addgroup --gid 99 nobody \
    && usermod -u 65534 -g 99 nobody \
    && usermod -a -G users nobody

RUN mkdir -p "${MESOSPHERE_PREFIX}/bin" \
    && curl -k --retry 3 -O "${LIBMESOS_BUNDLE_URL}/libmesos-bundle-${LIBMESOS_BUNDLE_VERSION}.tar.gz" \
    && tar xf "libmesos-bundle-${LIBMESOS_BUNDLE_VERSION}.tar.gz" -C "${MESOSPHERE_PREFIX}" \
    && cd "${MESOSPHERE_PREFIX}/libmesos-bundle/lib" \
    && curl -k --retry 3 -O "${MESOS_MAVEN_URL}/${MESOS_VERSION}/mesos-${MESOS_VERSION}.jar" \
    && curl -k --retry 3 -O "${MESOS_MAVEN_URL}/${MESOS_VERSION}/mesos-${MESOS_VERSION}-shaded-protobuf.jar" \
    && cd /tmp \
    && curl -k --retry 3 -O "${DCOS_COMMONS_URL}/artifacts/${DCOS_COMMONS_VERSION}/bootstrap.zip" \
    && unzip "bootstrap.zip" -d "${MESOSPHERE_PREFIX}/bin/" && rm bootstrap.zip


RUN wget -q $(wget -qO- https://www.apache.org/dyn/closer.lua/spark/spark-${APACHE_SPARK_VERSION}/spark-${APACHE_SPARK_VERSION}-bin-without-hadoop.tgz\?as_json | \
    python -c "import sys, json; content=json.load(sys.stdin); print(content['preferred']+content['path_info'])") && \
    tar xzf "spark-${APACHE_SPARK_VERSION}-bin-without-hadoop.tgz" -C /opt --owner root --group root --no-same-owner && \
    rm "spark-${APACHE_SPARK_VERSION}-bin-without-hadoop.tgz" && \
    ln -s "/opt/spark-${APACHE_SPARK_VERSION}-bin-without-hadoop" /opt/spark && \
    wget -q $(wget -qO- https://www.apache.org/dyn/closer.cgi/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz\?as_json | \
    python -c "import sys, json; content=json.load(sys.stdin); print(content['preferred']+content['path_info'])") && \
    tar xzf "hadoop-${HADOOP_VERSION}.tar.gz" -C /opt --owner root --group root --no-same-owner && \
    rm "hadoop-${HADOOP_VERSION}.tar.gz" && \
    ln -s "/opt/hadoop-${HADOOP_VERSION}" /opt/hadoop && \
    rm -rf /opt/hadoop/share/doc && \
    curl --retry 3 -fsSL -O "https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u212-b03/OpenJDK8U-jdk_x64_linux_hotspot_8u212b03.tar.gz" && \
    mkdir /opt/jdk && tar xf "OpenJDK8U-jdk_x64_linux_hotspot_8u212b03.tar.gz" -C "/opt/jdk" --strip-components=1 && rm OpenJDK8U-jdk_x64_linux_hotspot_8u212b03.tar.gz

COPY spark-env.sh /opt/spark/conf/

RUN touch /etc/krb5.conf && chmod ugo+rw /etc/krb5.conf && mkdir /etc/hadoop && chmod ugo+rwx /etc/hadoop && chmod -R ugo+rwx /opt/spark/conf

RUN cd /opt/spark/jars && curl -O https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar && \
    curl -O https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.199/aws-java-sdk-bundle-1.11.199.jar

ENV SPARK_HOME=/opt/spark \
    HADOOP_HOME=/opt/hadoop \
    HADOOP_CONF_DIR=/etc/hadoop \
    JAVA_HOME=/opt/jdk
ENV PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9-src.zip \
    PATH=$PATH:$SPARK_HOME/bin:$HADOOP_HOME/bin:$JAVA_HOME/jre/bin \
    LD_LIBRARY_PATH=":${MESOSPHERE_PREFIX}/libmesos-bundle/lib:${LD_LIBRARY_PATH}" \
    SPARK_DIST_CLASSPATH=/etc/hadoop:/opt/hadoop/share/hadoop/common/lib/*:/opt/hadoop/share/hadoop/common/*:/opt/hadoop/share/hadoop/hdfs:/opt/hadoop/share/hadoop/hdfs/lib/*:/opt/hadoop/share/hadoop/hdfs/*:/opt/hadoop/share/hadoop/yarn:/opt/hadoop/share/hadoop/yarn/lib/*:/opt/hadoop/share/hadoop/yarn/*:/opt/hadoop/share/hadoop/mapreduce/lib/*:/opt/hadoop/share/hadoop/mapreduce/*


USER $NB_UID
WORKDIR $HOME
ARG PYTHON_VERSION=3.6.9

# Setup work directory for backward-compatibility
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER

# Install conda as jovyan
ENV MINICONDA_VERSION=4.8.3 \
    CONDA_VERSION=4.8.3

WORKDIR /tmp
RUN wget --quiet https://repo.continuum.io/miniconda/Miniconda3-py38_${MINICONDA_VERSION}-Linux-x86_64.sh && \
    /bin/bash Miniconda3-py38_${MINICONDA_VERSION}-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm Miniconda3-py38_${MINICONDA_VERSION}-Linux-x86_64.sh && \
    echo "conda ${CONDA_VERSION}" >> $CONDA_DIR/conda-meta/pinned && \
    conda config --system --prepend channels conda-forge && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    conda config --system --set channel_priority strict && \
    if [ ! $PYTHON_VERSION = 'default' ]; then conda install --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    conda install --quiet --yes conda && \
    conda install --quiet --yes pip && \
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Install Tini
RUN conda install --quiet --yes 'tini=0.18.0' && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned && \
    conda clean --all -f -y && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Install Jupyter Notebook, Lab, and Hub
# Generate a notebook server config
# Cleanup temporary files
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
RUN conda install --quiet --yes \
    'notebook=6.0.3' \
    'jupyterhub=1.1.0' \
    'jupyterlab=2.1.5' \
    'pythreejs=2.2.0' \
    'ipycytoscape=1.0.3' \
    'ipyleaflet=0.13.3' \
    'bqplot=0.12.16' && \
    jupyter labextension install @jupyter-widgets/jupyterlab-manager --no-build && \
    jupyter labextension install bqplot jupyter-threejs jupyter-cytoscape jupyter-leaflet && \
    pip install toree sparksql-magic && jupyter toree install --sys-prefix --interpreters=Scala --spark_home=/opt/spark && \
    jupyter lab build -y && \
    jupyter lab clean -y && \
    conda clean --all -f -y && \
    npm cache clean --force && \
    rm -rf $CONDA_DIR/share/jupyter/lab/staging && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Configure container startup
EXPOSE 8888
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Copy local files as late as possible to avoid cache busting
COPY --chown="1000:100" jupyter_notebook_config.py "${HOME}/.jupyter/"
COPY --chown="1000:100" config_util /opt/python_util/config_util
RUN chmod o+rx "${HOME}/.jupyter" && chmod 775 "${HOME}/.jupyter/jupyter_notebook_config.py"
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/

WORKDIR $HOME
