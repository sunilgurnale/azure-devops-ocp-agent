FROM registry.access.redhat.com/ubi8/dotnet-60-runtime:latest
 
# These should be overridden in template deployment
ENV AZP_URL=http://dummyurl \
    AZP_POOL=Default \
    AZP_TOKEN=token \
    AZP_AGENT_NAME=myagent \
    AZP_WORK=/_work
 
ARG AZP_AGENT_VERSION=2.187.2
ARG OPENSHIFT_VERSION=4.9.7
 
ENV OPENSHIFT_BINARY_FILE="openshift-client-linux-${OPENSHIFT_VERSION}.tar.gz"
ENV OPENSHIFT_4_CLIENT_BINARY_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/${OPENSHIFT_BINARY_FILE}"
 
ENV _BUILDAH_STARTED_IN_USERNS="" \
    BUILDAH_ISOLATION=chroot \
    STORAGE_DRIVER=vfs \
    HOME=/home/podman
 
USER root
 
# Install required packages
RUN dnf install -y --setopt=tsflags=nodocs \
        git \
        skopeo \
        podman-docker \
        curl \
        tar \
        ca-certificates \
        --exclude container-selinux && \
    dnf clean all
 
# Initialize CA trust store
RUN update-ca-trust
 
# Setup directories and OpenShift-safe permissions
RUN mkdir -p /home/podman \
             /var/lib/origin \
             /usr/local/bin \
             /azp/agent/_diag \
             ${AZP_WORK} && \
    chgrp -R 0 /home/podman /var/lib/origin /azp ${AZP_WORK} && \
    chmod -R g+rwX /home/podman /var/lib/origin /azp ${AZP_WORK} && \
    chmod -R g=u /home/podman /var/lib/origin /azp ${AZP_WORK} && \
    chmod u-s /usr/bin/newuidmap /usr/bin/newgidmap
 
WORKDIR /azp/agent
 
# Install oc client
RUN curl -L ${OPENSHIFT_4_CLIENT_BINARY_URL} -o ${OPENSHIFT_BINARY_FILE} && \
    tar xzf ${OPENSHIFT_BINARY_FILE} -C /usr/local/bin && \
    rm -f ${OPENSHIFT_BINARY_FILE} && \
    chmod +x /usr/local/bin/oc
 
# Download Azure DevOps agent
RUN curl -L https://vstsagentpackage.azureedge.net/agent/${AZP_AGENT_VERSION}/vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz \
    -o vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz && \
    tar zxvf vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz && \
    rm -f vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz
 
# Install agent dependencies
RUN chmod +x ./bin/installdependencies.sh && \
    ./bin/installdependencies.sh && \
    chgrp -R 0 /azp ${AZP_WORK} && \
    chmod -R g+rwX /azp ${AZP_WORK} && \
    chmod -R g=u /azp ${AZP_WORK}
 
WORKDIR ${HOME}
 
# ---- CONFIGMAP CA SUPPORT ----
ENTRYPOINT ["/bin/bash", "-c", "\
if [ -f /etc/pki/ca-trust/source/anchors/custom-ca.crt ]; then \
  echo 'Custom CA found. Updating trust...'; \
  update-ca-trust; \
fi && \
/azp/agent/bin/Agent.Listener configure --unattended \
  --agent \"${AZP_AGENT_NAME}-${MY_POD_NAME}\" \
  --url \"$AZP_URL\" \
  --auth PAT \
  --token \"$AZP_TOKEN\" \
  --pool \"${AZP_POOL}\" \
  --work \"${AZP_WORK}\" \
  --replace \
  --acceptTeeEula && \
/azp/agent/externals/node/bin/node /azp/agent/bin/AgentService.js interactive --once \
"]
