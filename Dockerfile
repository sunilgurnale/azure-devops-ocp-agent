FROM registry.access.redhat.com/ubi8/dotnet-60-runtime:latest
 
# These should be overridden in template deployment to interact with Azure service
ENV AZP_URL=http://dummyurl \
    AZP_POOL=Default \
    AZP_TOKEN=token \
    AZP_AGENT_NAME=myagent
 
# If a working directory was specified, create that directory
ENV AZP_WORK=/_work
 
ARG AZP_AGENT_VERSION=2.187.2
ARG OPENSHIFT_VERSION=4.9.7
 
ENV OPENSHIFT_BINARY_FILE="openshift-client-linux-${OPENSHIFT_VERSION}.tar.gz"
ENV OPENSHIFT_4_CLIENT_BINARY_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/${OPENSHIFT_BINARY_FILE}
 
ENV _BUILDAH_STARTED_IN_USERNS="" \
    BUILDAH_ISOLATION=chroot \
    STORAGE_DRIVER=vfs \
    HOME=/home/podman
 
USER root
 
# Install required packages ONLY (removed dnf upgrade to avoid subscription issues)
RUN dnf install -y --setopt=tsflags=nodocs \
        git \
        skopeo \
        podman-docker \
        curl \
        tar \
        ca-certificates \
        --exclude container-selinux && \
    dnf clean all
 
# Initialize CA trust store (base system)
RUN update-ca-trust
 
# Setup directories and permissions
RUN chown -R podman:0 /home/podman && \
    chmod -R 775 /home/podman && \
    chmod -R 775 /etc/alternatives && \
    chmod -R 775 /var/lib/alternatives && \
    chmod -R 775 /usr/bin && \
    chmod 775 /usr/share/man/man1 && \
    mkdir -p /var/lib/origin && \
    chmod 775 /var/lib/origin && \
    chmod u-s /usr/bin/newuidmap && \
    chmod u-s /usr/bin/newgidmap && \
    mkdir -p "$AZP_WORK" && \
    mkdir -p /azp/agent/_diag && \
    mkdir -p /usr/local/bin
 
WORKDIR /azp/agent
 
# Get the oc binary
RUN curl ${OPENSHIFT_4_CLIENT_BINARY_URL} > ${OPENSHIFT_BINARY_FILE} && \
    tar xzf ${OPENSHIFT_BINARY_FILE} -C /usr/local/bin && \
    rm -rf ${OPENSHIFT_BINARY_FILE} && \
    chmod +x /usr/local/bin/oc
 
# Download and extract the agent package
RUN curl https://vstsagentpackage.azureedge.net/agent/${AZP_AGENT_VERSION}/vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz \
    > vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz && \
    tar zxvf vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz && \
    rm -rf vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz
 
# Install the agent software
RUN chmod +x ./bin/installdependencies.sh && \
    ./bin/installdependencies.sh && \
    chmod -R g=u "$AZP_WORK" && \
    chown -R 0 "$AZP_WORK" && \
    chmod -R g=u /azp && \
    chown -R 0 /azp
 
WORKDIR $HOME
 
# ---- ONLY CHANGE FOR CONFIGMAP CA SUPPORT ----
# At container start, refresh trust store so mounted CA from:
# /etc/pki/ca-trust/source/anchors/custom-ca.crt
# becomes trusted.
 
ENTRYPOINT /bin/bash -c 'update-ca-trust && \
/azp/agent/bin/Agent.Listener configure --unattended \
  --agent "${AZP_AGENT_NAME}-${MY_POD_NAME}" \
  --url "$AZP_URL" \
  --auth PAT \
  --token "$AZP_TOKEN" \
  --pool "${AZP_POOL}" \
  --work /_work \
  --replace \
  --acceptTeeEula && \
/azp/agent/externals/node/bin/node /azp/agent/bin/AgentService.js interactive --once'
