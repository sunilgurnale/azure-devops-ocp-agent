FROM registry.access.redhat.com/ubi8/dotnet-60-runtime:latest
 
# Azure DevOps defaults (override at runtime)
ENV AZP_URL=http://dummyurl \
    AZP_POOL=Default \
    AZP_TOKEN=token \
    AZP_AGENT_NAME=myagent \
    AZP_WORK=/_work
 
ENV _BUILDAH_STARTED_IN_USERNS="" \
    BUILDAH_ISOLATION=chroot \
    STORAGE_DRIVER=vfs \
    HOME=/home/default
 
ARG AZP_AGENT_VERSION=4.269.0
 
USER root
 
# Install only required packages (no upgrade)
RUN dnf install -y --setopt=tsflags=nodocs \
    git \
    curl \
    tar \
    jq \
    ca-certificates \
    && dnf clean all
 
# Ensure base trust store exists
RUN update-ca-trust
 
# Create work directory
RUN mkdir -p "$AZP_WORK" && \
    mkdir -p /azp/agent && \
    chmod -R g=u /azp && \
    chmod -R g=u "$AZP_WORK"
 
WORKDIR /azp/agent
 
# Download Azure DevOps agent
RUN curl -L https://download.agent.dev.azure.com/agent/${AZP_AGENT_VERSION}/vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz \
    -o agent.tar.gz && \
    tar zxvf agent.tar.gz && \
    rm -f agent.tar.gz
 
# Install agent dependencies
RUN  /bin/bash -c './bin/installdependencies.sh' && \
    chmod -R 775 "$AZP_WORK" && \
    chown -R podman:root "$AZP_WORK" && \
    chmod -R 775 /azp && \
    chown -R podman:root /azp

USER 1001

# ---- ONLY CHANGE: Refresh trust at container startup ----
ENTRYPOINT ["/bin/bash", "-c", "\
update-ca-trust && \
./bin/Agent.Listener configure --unattended \
  --agent \"${AZP_AGENT_NAME}-${HOSTNAME}\" \
  --url \"$AZP_URL\" \
  --auth PAT \
  --token \"$AZP_TOKEN\" \
  --pool \"$AZP_POOL\" \
  --work \"$AZP_WORK\" \
  --replace \
  --acceptTeeEula && \
./bin/Agent.Listener run --once \
"]
