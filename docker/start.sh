#!/bin/bash
# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

set -e

# Exec the specified command or fall back on bash
if [ $# -eq 0 ]; then
    cmd=( "bash" )
else
    cmd=( "$@" )
fi

run-hooks () {
    # Source scripts or run executable files in a directory
    if [[ ! -d "$1" ]] ; then
        return
    fi
    echo "$0: running hooks in $1"
    for f in "$1/"*; do
        case "$f" in
            *.sh)
                echo "$0: running $f"
                source "$f"
                ;;
            *)
                if [[ -x "$f" ]] ; then
                    echo "$0: running $f"
                    "$f"
                else
                    echo "$0: ignoring $f"
                fi
                ;;
        esac
    done
    echo "$0: done running hooks in $1"
}

run-hooks /usr/local/bin/start-notebook.d

# bootstrap requires that ${LIBPROCESS_IP} or ${MESOS_CONTAINER_IP} be set
if [ -z ${LIBPROCESS_IP+x} ]; then
    CONTAINER_IP=$(LIBPROCESS_IP="0.0.0.0" bootstrap -get-task-ip);
    export LIBPROCESS_IP="${CONTAINER_IP}"
else
    CONTAINER_IP=$(bootstrap -get-task-ip)
fi

export SPARK_LOCAL_IP=${CONTAINER_IP}
export LIBPROCESS_IP=${SPARK_LOCAL_IP}

export CONTAINER_IP
echo "CONTAINER_IP: ${CONTAINER_IP}"
echo "LIBPROCESS_IP: ${LIBPROCESS_IP}"

if [ -z ${MESOS_CONTAINER_IP+x} ]; then
    export MESOS_CONTAINER_IP="${CONTAINER_IP}"
fi
echo "MESOS_CONTAINER_IP: ${MESOS_CONTAINER_IP}"


# ${HOME} is set to ${MESOS_SANDBOX} on DC/OS and won't have a default IPython profile
# We have to manually check since `ipython profile locate default` *creates* the config
if [ ! -f "${MESOS_SANDBOX}/.ipython/profile_default/ipython_kernel_config.py" ]; then
    ipython profile create default
fi

# Copy over beakerx.json so that we have a sane set of defaults for Mesosphere DC/OS
mkdir -p "${MESOS_SANDBOX}/.jupyter"
# if [ ! -f "${MESOS_SANDBOX}/.jupyter/beakerx.json" ]; then
#     mkdir -p "${MESOS_SANDBOX}/.jupyter"
#     cp "/home/jovyan/.jupyter/beakerx.json" "${MESOS_SANDBOX}/.jupyter/"
# fi
if [ ! -f "${MESOS_SANDBOX}/.jupyter/jupyter_notebook_config.py" ]; then
    cp "/home/jovyan/.jupyter/jupyter_notebook_config.py" "${MESOS_SANDBOX}/.jupyter/"
fi

if [ -f "${MESOS_SANDBOX}/hdfs-site.xml" ]; then
    cp "${MESOS_SANDBOX}/hdfs-site.xml" /etc/hadoop/hdfs-site.xml
fi
if [ -f "${MESOS_SANDBOX}/core-site.xml" ]; then
    cp "${MESOS_SANDBOX}/core-site.xml" /etc/hadoop/core-site.xml
fi


export HOME=${MESOS_SANDBOX}
export JUPYTER_CONFIG_DIR=${HOME}/.jupyter
export PYTHONPATH="${PYTHONPATH}:/opt/python_util/"

export HADOOP_HOME=/etc/hadoop/
export HADOOP_CONF_DIR=/etc/hadoop
export CLASSPATH=$CLASSPATH:$HADOOP_CONF_DIR


# Handle special flags if we're root
if [ $(id -u) == 0 ] ; then

    # Only attempt to change the jovyan username if it exists
    if id jovyan &> /dev/null ; then
        echo "Set username to: $NB_USER"
        usermod -d /home/$NB_USER -l $NB_USER jovyan
    fi

    # Handle case where provisioned storage does not have the correct permissions by default
    # Ex: default NFS/EFS (no auto-uid/gid)
    if [[ "$CHOWN_HOME" == "1" || "$CHOWN_HOME" == 'yes' ]]; then
        echo "Changing ownership of /home/$NB_USER to $NB_UID:$NB_GID with options '${CHOWN_HOME_OPTS}'"
        chown $CHOWN_HOME_OPTS $NB_UID:$NB_GID /home/$NB_USER
    fi
    if [ ! -z "$CHOWN_EXTRA" ]; then
        for extra_dir in $(echo $CHOWN_EXTRA | tr ',' ' '); do
            echo "Changing ownership of ${extra_dir} to $NB_UID:$NB_GID with options '${CHOWN_EXTRA_OPTS}'"
            chown $CHOWN_EXTRA_OPTS $NB_UID:$NB_GID $extra_dir
        done
    fi

    if [ -d "${MESOS_SANDBOX}" ];then
        # Change ownership of $MESOS_SANDBOX so that ${NB_USER} can write to it
        chown -R "${NB_UID}:${NB_GID}" "${MESOS_SANDBOX}"
    fi

    # handle home and working directory if the username changed
    if [[ "$NB_USER" != "jovyan" ]]; then
        # changing username, make sure homedir exists
        # (it could be mounted, and we shouldn't create it if it already exists)
        if [[ ! -e "/home/$NB_USER" ]]; then
            echo "Relocating home dir to /home/$NB_USER"
            mv /home/jovyan "/home/$NB_USER" || ln -s /home/jovyan "/home/$NB_USER"
        fi
        # if workdir is in /home/jovyan, cd to /home/$NB_USER
        if [[ "$PWD/" == "/home/jovyan/"* ]]; then
            newcwd="/home/$NB_USER/${PWD:13}"
            echo "Setting CWD to $newcwd"
            cd "$newcwd"
        fi
    fi

    # Change UID:GID of NB_USER to NB_UID:NB_GID if it does not match
    if [ "$NB_UID" != $(id -u $NB_USER) ] || [ "$NB_GID" != $(id -g $NB_USER) ]; then
        echo "Set user $NB_USER UID:GID to: $NB_UID:$NB_GID"
        if [ "$NB_GID" != $(id -g $NB_USER) ]; then
            groupadd -g $NB_GID -o ${NB_GROUP:-${NB_USER}}
        fi
        userdel $NB_USER
        useradd --home /home/$NB_USER -u $NB_UID -g $NB_GID -G 100 -l $NB_USER
    fi

    # Enable sudo if requested
    if [[ "$GRANT_SUDO" == "1" || "$GRANT_SUDO" == 'yes' ]]; then
        echo "Granting $NB_USER sudo access and appending $CONDA_DIR/bin to sudo PATH"
        echo "$NB_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/notebook
    fi

    # Add $CONDA_DIR/bin to sudo secure_path
    sed -r "s#Defaults\s+secure_path\s*=\s*\"?([^\"]+)\"?#Defaults secure_path=\"\1:$CONDA_DIR/bin\"#" /etc/sudoers | grep secure_path > /etc/sudoers.d/path

    # Exec the command as NB_USER with the PATH and the rest of
    # the environment preserved
    run-hooks /usr/local/bin/before-notebook.d
    cd $HOME
    echo "Executing the command: ${cmd[@]}"
    exec sudo -E -H -u $NB_USER PATH=$PATH XDG_CACHE_HOME=/home/$NB_USER/.cache PYTHONPATH=${PYTHONPATH:-} "${cmd[@]}"
else
    if [[ "$NB_UID" == "$(id -u jovyan 2>/dev/null)" && "$NB_GID" == "$(id -g jovyan 2>/dev/null)" ]]; then
        # User is not attempting to override user/group via environment
        # variables, but they could still have overridden the uid/gid that
        # container runs as. Check that the user has an entry in the passwd
        # file and if not add an entry.
        STATUS=0 && whoami &> /dev/null || STATUS=$? && true
        if [[ "$STATUS" != "0" ]]; then
            if [[ -w /etc/passwd ]]; then
                echo "Adding passwd file entry for $(id -u)"
                cat /etc/passwd | sed -e "s/^jovyan:/nayvoj:/" > /tmp/passwd
                echo "jovyan:x:$(id -u):$(id -g):,,,:/home/jovyan:/bin/bash" >> /tmp/passwd
                cat /tmp/passwd > /etc/passwd
                rm /tmp/passwd
            else
                echo 'Container must be run with group "root" to update passwd file'
            fi
        fi

        # Warn if the user isn't going to be able to write files to $HOME.
        if [[ ! -w /home/jovyan ]]; then
            echo 'Container must be run with group "users" to update files'
        fi
    else
        # Warn if looks like user want to override uid/gid but hasn't
        # run the container as root.
        if [[ ! -z "$NB_UID" && "$NB_UID" != "$(id -u)" ]]; then
            echo 'Container must be run as root to set $NB_UID'
        fi
        if [[ ! -z "$NB_GID" && "$NB_GID" != "$(id -g)" ]]; then
            echo 'Container must be run as root to set $NB_GID'
        fi
    fi

    # Warn if looks like user want to run in sudo mode but hasn't run
    # the container as root.
    if [[ "$GRANT_SUDO" == "1" || "$GRANT_SUDO" == 'yes' ]]; then
        echo 'Container must be run as root to grant sudo permissions'
    fi

    # Execute the command
    run-hooks /usr/local/bin/before-notebook.d
    cd $HOME
    echo "Executing the command: ${cmd[@]}"
    exec "${cmd[@]}"
fi
